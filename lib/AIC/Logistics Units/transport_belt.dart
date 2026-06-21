import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/building.dart';

/// 传送带创建控制器：管理锚点、路径、预览、寻路等全部状态和逻辑
class TransportBeltController {
  static const String _beltBridgeId = 'belt_bridge_1x1';

  ProjectState project;
  final void Function(ProjectState) onProjectChanged;
  final void Function() onRebuildCache;
  final void Function() notifyListeners;
  final double Function() currentPhase;
  final Building? Function(String buildingId)? getBuilding;

  static double _defaultCurrentPhase() => 0.0;

  TransportBeltController({
    required this.project,
    required this.onProjectChanged,
    required this.onRebuildCache,
    required this.notifyListeners,
    this.currentPhase = _defaultCurrentPhase,
    this.getBuilding,
  });

  // === 状态 ===
  List<Offset> anchors = [];
  List<Offset> fullPath = [];
  List<Offset> confirmedPath = [];
  bool pathInvalid = false;
  List<Offset>? previewPath;
  Set<String>? previewOccupied;
  Offset? mouseGridPos;
  ConveyorBelt? _mergeTarget;

  /// 预览路径的转角上下文扩展（合并目标的路径，仅用于转角检测，不渲染为蓝色预览）
  List<Offset>? previewContextExtension;

  /// 预览路径上需要放置物流桥的交叉点（用于渲染物流桥预览）
  List<Offset> previewBridgeCells = [];

  String? _startingPortDirection;
  /// 首段路径允许的物理方向集合（如分流器允许 {up, left, right}）。
  /// null 表示无限制。非 null 时 BFS 第一步仅允许集合内的方向，
  /// 防止从建筑输出端口往输入端方向创建传送带。
  Set<String>? _startingPortAllowedDirections;
  String? _incomingDirection;
  String? _committedBeltId;
  int _lastCommittedPathLength = 0;

  /// 截断创建时，原传送带截断点之后的剩余格子（应视为阻挡）
  List<Offset> _truncatedBeltTail = [];

  /// 当前创建中传送带首格的入方向（用于预览渲染转角）
  String? get incomingDirection => _incomingDirection;
  bool get hasCommittedPath => _committedBeltId != null;

  // === 静态工具 ===
  static const double cellSize = 48.0;

  // === 公开 API ===

  void reset() {
    anchors = [];
    fullPath = [];
    confirmedPath = [];
    pathInvalid = false;
    previewPath = null;
    previewOccupied = null;
    previewContextExtension = null;
    previewBridgeCells = [];
    _mergeTarget = null;
    _startingPortDirection = null;
    _startingPortAllowedDirections = null;
    _incomingDirection = null;
    _committedBeltId = null;
    _lastCommittedPathLength = 0;
    _truncatedBeltTail = [];
  }

  /// 返回 true 表示点击已被处理
  bool handleTap(Offset gridPos) {
    if (anchors.isEmpty) {
      return _handleFirstAnchor(gridPos);
    }
    return _handleSubsequentAnchor(gridPos);
  }

  void handleHover(Offset gridPos) {
    if (mouseGridPos == gridPos) return;
    mouseGridPos = gridPos;
    _updatePreview();
    notifyListeners();
  }

  void handleRightClick() {
    _finish();
    notifyListeners();
  }

  /// 返回 true 表示 ESC 已被处理
  bool handleKeyEscape() {
    if (anchors.isNotEmpty) {
      _finish();
      notifyListeners();
      return true;
    }
    return false;
  }

  // === 内部实现 ===

  bool _handleFirstAnchor(Offset gridPos) {
    // 每次开始新传送带时清空入方向，防止上一轮 _finish() 遗留的
    // incomingDirection 导致新传送带首格预览显示为转角传送带。
    _incomingDirection = null;
    // 物流桥：允许从任意方向开始创建传送带
    final bridgeAtCell = _findBeltBridgeAtCell(gridPos);
    if (bridgeAtCell != null) {
      anchors.add(gridPos);
      _startingPortDirection = null;
      _incomingDirection = null;
      _updatePreview();
      notifyListeners();
      return true;
    }

    final belt = _findBeltAtCell(gridPos);
    if (belt != null) {
      // 1x1建筑（如分流器）输入/输出端口共享同一格子
      // 若该格子同时是设备输出端口，优先从输出端口创建新传送带，避免与输入传送带合并
      if (_isCellInBuilding(gridPos)) {
        final portInfo = _findPortAtCell(gridPos, preferredType: 'output');
        // 对 1x1 建筑（如分流器），_findPortAtCell 因端口坐标 round 后偏移
        // 可能返回 null 或 fallback 返回 input 类型的端口（非 null）。
        // 此时通过检查建筑是否有输出来判断是否应走"从输出端口创建"分支，
        // 避免回退到"从已有传送带创建"逻辑导致继承旧的 incomingDirection 使预览首格误判为转角。
        final hasOutputPort = _buildingAtCellHasOutputPort(gridPos);
        final isOutputPort =
            portInfo != null && portInfo.type == 'output';
        if (isOutputPort || (!isOutputPort && hasOutputPort)) {
          anchors.add(gridPos);
          _startingPortDirection = null;
          _startingPortAllowedDirections =
              _computeAllowedDirectionsForBuilding(gridPos);
          // 从设备的输出端口重新开始创建新传送带时，必须清空旧的 fullPath，
          // 否则 _updatePreview 会将已提交的旧路径作为 confirmedPath 拼入 fullPathContext，
          // 导致预览首格被误判为转弯（如左带向上+右预览向右时显示为转角）。
          fullPath = [];
          _incomingDirection = null;
          _updatePreview();
          notifyListeners();
          return true;
        }
      }
      if (belt.path.isNotEmpty) {
        final firstCell = belt.path.first;
        if (firstCell.dx.toInt() == gridPos.dx.toInt() &&
            firstCell.dy.toInt() == gridPos.dy.toInt()) {
          // 单格传送带：允许从该格开始创建，以其方向作为起始方向约束
          if (belt.path.length == 1) {
            final dir = belt.forcedDirection ?? 'right';
            anchors.add(gridPos);
            _startingPortDirection = dir;
            _incomingDirection = belt.incomingDirection;
            _updatePreview();
            notifyListeners();
            return true;
          }
          return false;
        }
      }
      fullPath = _traceBeltToCell(belt, gridPos);
      // 记录截断点之后的剩余格子，作为阻挡防止顺着原传送带方向重复创建
      final clickIdx = belt.path.indexWhere((c) =>
          c.dx.toInt() == gridPos.dx.toInt() &&
          c.dy.toInt() == gridPos.dy.toInt());
      _truncatedBeltTail = (clickIdx >= 0 && clickIdx + 1 < belt.path.length)
          ? belt.path.sublist(clickIdx + 1)
          : [];
      anchors.add(gridPos);
      _startingPortDirection = null;
      // 继承旧传送带首格的入方向，用于预览渲染转角
      _incomingDirection = belt.incomingDirection;
      _updatePreview();
      notifyListeners();
      return true;
    }
    if (_isCellInBuilding(gridPos)) {
      // 只允许从输出端口开始创建传送带
      // 不允许从输入端口开始（传送带单向），也不允许从设备内部非端口格子开始
      final portInfo = _findPortAtCell(gridPos, preferredType: 'output');
      // 对 1x1 建筑（如分流器），_findPortAtCell 可能因端口坐标 round 后偏移而返回 null。
      // 此时通过检查建筑是否有输出来判断是否允许创建。
      final hasOutputPort = _buildingAtCellHasOutputPort(gridPos);
      if ((portInfo == null || portInfo.type != 'output') && !hasOutputPort) {
        return false;
      }
      anchors.add(gridPos);
      // 计算建筑输出端口的允许方向集合，替代单一方向限制。
      // 如分流器允许 {up, left, right}，阻止往输入端（down）方向创建传送带。
      _startingPortDirection = null;
      _startingPortAllowedDirections =
          _computeAllowedDirectionsForBuilding(gridPos);
      _updatePreview();
      notifyListeners();
      return true;
    }
    _startingPortDirection = null;
    return false;
  }

  bool _handleSubsequentAnchor(Offset gridPos) {
    if (anchors.last == gridPos) return false;

    // 1x1建筑（如分流器）的输入/输出端口共享同一格子。
    // 当目标格子是建筑输入端口格时，跳过合并和截断检查，
    // 直接进入下方的输入端口终点逻辑。
    final isBuildingInputCell =
        _isCellInBuilding(gridPos) && _buildingAtCellHasInputPort(gridPos);

    // 若当前目标是建筑输出端口格（如从分流器创建新输出带），
    // 清空上一轮遗留的 incomingDirection，避免首格预览显示为转角。
    if (_isCellInBuilding(gridPos) && _buildingAtCellHasInputPort(gridPos)) {
      _incomingDirection = null;
    }
    if (!isBuildingInputCell) {
      // 检查是否点击了某条传送带的起点（合并候选）
      final mergeBelt = _findBeltStartCell(gridPos);
      if (mergeBelt != null) {
        // 不允许与路径中已包含的传送带合并（避免回环）
        final alreadyInPath =
            fullPath.any((c) => c.dx == gridPos.dx && c.dy == gridPos.dy);
        if (!alreadyInPath) {
          final blocked = _buildBlockedSet(excludeCell: gridPos);
          final verticalFirst = _isIncomingVertical();
          final segment = _findPath(anchors.last, gridPos, blocked,
              verticalFirst: verticalFirst);
          if (segment != null &&
              segment.length >= 2 &&
              _isDirectionCompatible(segment, mergeBelt)) {
            if (fullPath.isEmpty) {
              fullPath.addAll(segment);
            } else {
              if (segment.length > 1) {
                fullPath.addAll(segment.sublist(1));
              }
            }
            anchors.add(gridPos);
            _mergeTarget = mergeBelt;
            _finish(); // 合并时自动完成创建
            notifyListeners();
            return true;
          }
        }
        // 方向不兼容或路径不通，返回 false 让预览显示红色
        return false;
      }

      // 检查是否点击了某条传送带的中间格子（非起点），进行截断连接
      final midBelt = _findBeltAtCellExcluding(gridPos, _committedBeltId);
      if (midBelt != null) {
        // 排除首格（已由 mergeBelt 处理）和已在路径中的格子
        final isFirstCell = midBelt.path.isNotEmpty &&
            midBelt.path.first.dx == gridPos.dx &&
            midBelt.path.first.dy == gridPos.dy;
        final alreadyInPath =
            fullPath.any((c) => c.dx == gridPos.dx && c.dy == gridPos.dy);
        if (!isFirstCell && !alreadyInPath) {
          final blocked = _buildBlockedSet(excludeCell: gridPos);
          final verticalFirst = _isIncomingVertical();
          final segment = _findPath(anchors.last, gridPos, blocked,
              verticalFirst: verticalFirst);
          if (segment != null && segment.length >= 2) {
            if (fullPath.isEmpty) {
              fullPath.addAll(segment);
            } else {
              if (segment.length > 1) {
                fullPath.addAll(segment.sublist(1));
              }
            }
            anchors.add(gridPos);
            _finish(); // 截断连接时自动完成创建
            notifyListeners();
            return true;
          }
        }
        // 路径不通或格子不合法，返回 false 让预览显示红色
        return false;
      }
    } else {
    }

    // 允许设备输入端口的格子作为传送带终点
    // 注意：_isCellDeviceInputPort 对1x1建筑无效（端口坐标在格边缘而非格中心），
    // 需同时用 _isCellInBuilding + _buildingAtCellHasInputPort 补检。
    final isInputPort = _isCellDeviceInputPort(gridPos) ||
        (_isCellInBuilding(gridPos) && _buildingAtCellHasInputPort(gridPos));
    // 物流桥格子允许作为传送带路径的一部分
    final isBridgeCell = _findBeltBridgeAtCell(gridPos) != null;
    if (!isInputPort && !isBridgeCell && _isCellOccupied(gridPos)) {
      return false;
    }

    // 输入端口作为终点时，从 blocked 中排除该格
    final blocked = _buildBlockedSet(excludeCell: isInputPort ? gridPos : null);
    final verticalFirst = _isIncomingVertical();

    final segment =
        _findPath(anchors.last, gridPos, blocked, verticalFirst: verticalFirst);
    if (segment == null || segment.length < 2) {
      return false;
    }
    if (_isBlockedBridgeStartSegment(segment)) {
      return false;
    }

    // 点击输入端口时自动完成创建
    if (isInputPort) {
      // 计算预期的完整路径
      final prospectivePath = fullPath.isEmpty
          ? List<Offset>.from(segment)
          : [...fullPath, ...segment.sublist(1)];
      // 设备输入/输出端口之间必须预留至少一格给传送带显示
      if (!_hasIndependentBeltCell(prospectivePath)) {
        return false;
      }
      if (fullPath.isEmpty) {
        fullPath.addAll(segment);
      } else {
        if (segment.length > 1) {
          fullPath.addAll(segment.sublist(1));
        }
      }
      anchors.add(gridPos);
      _finish();
      notifyListeners();
      return true;
    }

    if (fullPath.isEmpty) {
      fullPath.addAll(segment);
    } else {
      if (segment.length > 1) {
        fullPath.addAll(segment.sublist(1));
      }
    }

    anchors.add(gridPos);

    // 转角吸附：点击位置相邻有兼容的传送带起点时，自动合并
    if (fullPath.length >= 2) {
      final lastCell = fullPath.last;
      final adjacent = _findAdjacentBeltStart(lastCell);
      if (adjacent != null) {
        final (adjBelt, adjCell) = adjacent;
        fullPath.add(adjCell);
        _mergeTarget = adjBelt;
        _finish();
        notifyListeners();
        return true;
      }
    }

    _finish(keepCreating: true);
    _updatePreview();
    notifyListeners();
    return true;
  }

  void _finish({bool keepCreating = false}) {
    if (!keepCreating &&
        _committedBeltId != null &&
        fullPath.length == _lastCommittedPathLength) {
      reset();
      return;
    }

    if (anchors.length >= 2 && fullPath.length >= 2) {
      // 合并：将合并目标的路径追加到 fullPath（跳过首格，因为已包含）
      // 记录新段长度，用于偏移合并目标的物品进度
      final newSegmentLength = fullPath.length;
      if (_mergeTarget != null && _mergeTarget!.path.length > 1) {
        fullPath.addAll(_mergeTarget!.path.sublist(1));
      }

      // 自动检测交叉并创建物流桥
      _autoCreateBridgesAtCrossings();

      // 使用 anchors.first（用户实际点击的位置）作为分叉点
      final startCell = anchors.first;
      final startsAtBridge = _findBeltBridgeAtCell(startCell) != null;
      // 1x1建筑（如分流器）输出端口与输入传送带终点共享同一格子
      // 从输出端口创建新传送带时，不应将输入传送带视为分叉源/源传送带/截断目标
      final startPortInfo = _isCellInBuilding(startCell)
          ? _findPortAtCell(startCell, preferredType: 'output')
          : null;
      final startIsDeviceOutputPort =
          startPortInfo != null && startPortInfo.type == 'output';
      final bridgeStartDirection = startsAtBridge && fullPath.length >= 2
          ? _directionBetween(fullPath[0], fullPath[1])
          : null;
      final bridgeSourceBelt = startsAtBridge
          ? _findBridgeContinuationSourceBelt(
              startCell,
              bridgeStartDirection,
            )
          : null;
      if (bridgeSourceBelt != null) {
        fullPath = [
          ...bridgeSourceBelt.path,
          ...fullPath.skip(1),
        ];
      }
      ConveyorBelt? forkSourceBelt;
      int forkSourceIndex = -1;
      if (!startsAtBridge && !startIsDeviceOutputPort) {
        for (final oldBelt in project.conveyors) {
          for (int i = 0; i < oldBelt.path.length; i++) {
            if (oldBelt.path[i].dx == startCell.dx &&
                oldBelt.path[i].dy == startCell.dy) {
              forkSourceBelt = oldBelt;
              forkSourceIndex = i;
              break;
            }
          }
          if (forkSourceBelt != null) break;
        }
      }

      // 检查新传送带的终点是否在某条旧传送带的中间格子上
      // 如果方向兼容，追加下游部分到 fullPath（类似合并目标）
      ConveyorBelt? endCellBelt;
      int endCellIdx = -1;
      {
        final endCell = fullPath.last;
        for (final oldBelt in project.conveyors) {
          if (_committedBeltId != null && oldBelt.id == _committedBeltId) {
            continue;
          }
          if (_mergeTarget != null && identical(oldBelt, _mergeTarget)) continue;
          if (startsAtBridge &&
              bridgeSourceBelt != null &&
              identical(oldBelt, bridgeSourceBelt)) {
            continue;
          }
          if (forkSourceBelt != null && identical(oldBelt, forkSourceBelt)) {
            continue;
          }
          for (int i = 1; i < oldBelt.path.length; i++) {
            if (oldBelt.path[i].dx == endCell.dx &&
                oldBelt.path[i].dy == endCell.dy) {
              endCellBelt = oldBelt;
              endCellIdx = i;
              break;
            }
          }
          if (endCellBelt != null) break;
        }
      }
      // 方向兼容时追加下游部分到 fullPath
      bool endCellDownstreamMerged = false;
      int endCellDownstreamOffset = 0;
      if (endCellBelt != null &&
          endCellIdx >= 0 &&
          endCellIdx + 1 < endCellBelt.path.length &&
          fullPath.length >= 2) {
        final newEndDir = _directionBetween(
            fullPath[fullPath.length - 2], fullPath.last);
        final oldOutDir = _directionBetween(endCellBelt.path[endCellIdx],
            endCellBelt.path[endCellIdx + 1]);
        if (newEndDir == oldOutDir) {
          endCellDownstreamOffset = fullPath.length;
          fullPath.addAll(endCellBelt.path.sublist(endCellIdx + 1));
          endCellDownstreamMerged = true;
        }
      }

      // 查找 fullPath 首格来源的旧传送带，继承其 incomingDirection
      String? newBeltIncomingDir;
      if (fullPath.isNotEmpty) {
        final firstCell = fullPath.first;
        for (final oldBelt in project.conveyors) {
          if (oldBelt.path.isNotEmpty &&
              oldBelt.path.first.dx == firstCell.dx &&
              oldBelt.path.first.dy == firstCell.dy) {
            newBeltIncomingDir = oldBelt.incomingDirection;
            break;
          }
        }
      }

      // 查找源传送带（用户从其终点开始创建新传送带的旧传送带）
      // 当 startCell 是某条旧传送带的终点时，继承其物品状态
      // 设备输出端口起点不继承输入传送带的物品状态（物品经过设备处理）
      ConveyorBelt? sourceBelt = bridgeSourceBelt;
      if (sourceBelt == null && !startIsDeviceOutputPort) {
        for (final oldBelt in project.conveyors) {
          if (oldBelt.path.isNotEmpty &&
              oldBelt.path.last.dx == startCell.dx &&
              oldBelt.path.last.dy == startCell.dy) {
            sourceBelt = oldBelt;
            break;
          }
        }
      }

      // 合并时保留目标传送带的物品状态
      String newItemId = '';
      String newLastItemId = '';
      int newItemFillCount = 0;
      int newItemDrainCount = 0;
      int newLastItemFillCount = 0;
      int newLastItemDrainCount = 0;
      double? newDeadEndFreezeProgress;
      double? newLastItemFreezeProgress;
      double newPhaseOffset = currentPhase();
      final newItemSegments = <ConveyorItemSegment>[];
      final committedSourceBelt = _committedBeltId == null
          ? null
          : project.conveyors
              .where((belt) => belt.id == _committedBeltId)
              .firstOrNull;

      // 继承源传送带的物品状态（加长断头传送带时）
      if (committedSourceBelt != null &&
          _isPathPrefix(committedSourceBelt.path, fullPath)) {
        newItemSegments.addAll(
          committedSourceBelt.shiftedItemSegments(
            0,
            clearFreezeProgress: true,
          ),
        );
        newItemId = committedSourceBelt.itemId;
        newItemFillCount = committedSourceBelt.itemFillCount;
        newItemDrainCount = committedSourceBelt.itemDrainCount;
        newPhaseOffset = committedSourceBelt.phaseOffset;
        if (committedSourceBelt.lastItemFillCount > 0) {
          newLastItemId = committedSourceBelt.lastItemId;
          newLastItemFillCount = committedSourceBelt.lastItemFillCount;
          newLastItemDrainCount = committedSourceBelt.lastItemDrainCount;
        }
      } else if (sourceBelt != null) {
        newItemSegments.addAll(
          sourceBelt.shiftedItemSegments(0, clearFreezeProgress: true),
        );
        newItemId = sourceBelt.itemId;
        newItemFillCount = sourceBelt.itemFillCount;
        newItemDrainCount = sourceBelt.itemDrainCount;
        newPhaseOffset = sourceBelt.phaseOffset;
        // 源传送带的残留物品也继承
        if (sourceBelt.lastItemFillCount > 0) {
          newLastItemId = sourceBelt.lastItemId;
          newLastItemFillCount = sourceBelt.lastItemFillCount;
          newLastItemDrainCount = sourceBelt.lastItemDrainCount;
        }
      } else if (forkSourceBelt != null && forkSourceIndex >= 0) {
        newItemSegments.addAll(
          forkSourceBelt.clippedItemSegments(
            0,
            forkSourceIndex + 1,
            clearFreezeProgress: true,
          ),
        );
        newItemId = forkSourceBelt.itemId;
        newItemFillCount =
            forkSourceBelt.itemFillCount.clamp(0, forkSourceIndex + 1).toInt();
        newItemDrainCount =
            forkSourceBelt.itemDrainCount.clamp(0, forkSourceIndex + 1).toInt();
        newPhaseOffset = forkSourceBelt.phaseOffset;
        if (forkSourceBelt.lastItemFillCount > 0) {
          newLastItemId = forkSourceBelt.lastItemId;
          newLastItemFillCount = forkSourceBelt.lastItemFillCount
              .clamp(0, forkSourceIndex + 1)
              .toInt();
          newLastItemDrainCount = forkSourceBelt.lastItemDrainCount
              .clamp(0, forkSourceIndex + 1)
              .toInt();
        }
      }

      if (_mergeTarget != null) {
        final mergeBelt = _mergeTarget!;
        final offset = newSegmentLength - 1; // 合并目标首格已包含在 fullPath 中
        newItemSegments.addAll(
          mergeBelt.shiftedItemSegments(offset, clearFreezeProgress: true),
        );

        if (mergeBelt.itemId.isNotEmpty) {
          if (mergeBelt.lastItemFillCount > 0) {
            // 保留已经形成的排队状态，避免当前物品覆盖更下游的残留物品。
            newItemId = mergeBelt.itemId;
            newItemFillCount = mergeBelt.itemFillCount + offset;
            newItemDrainCount = mergeBelt.itemDrainCount + offset;

            newLastItemId = mergeBelt.lastItemId;
            newLastItemFillCount = mergeBelt.lastItemFillCount + offset;
            newLastItemDrainCount = mergeBelt.lastItemDrainCount + offset;
          } else {
            // 合并目标有当前物品 -> 转为残留物品
            newLastItemId = mergeBelt.itemId;
            newLastItemFillCount = mergeBelt.itemFillCount + offset;
            newLastItemDrainCount = mergeBelt.itemDrainCount + offset;
          }
        } else if (mergeBelt.lastItemFillCount > 0) {
          // 合并目标已有残留物品 -> 继承
          newLastItemId = mergeBelt.lastItemId;
          newLastItemFillCount = mergeBelt.lastItemFillCount + offset;
          newLastItemDrainCount = mergeBelt.lastItemDrainCount + offset;
        }
      }

      // 终点截断下游合并时，继承下游部分的物品状态
      if (endCellDownstreamMerged && endCellBelt != null) {
        final eb = endCellBelt;
        final offset = endCellDownstreamOffset;
        newItemSegments.addAll(
          eb.clippedItemSegments(
            endCellIdx + 1,
            eb.path.length,
            clearFreezeProgress: true,
          ).map((seg) => seg.shifted(offset)),
        );
        if (eb.itemId.isNotEmpty) {
          final downstreamFill = eb.itemFillCount > endCellIdx + 1
              ? eb.itemFillCount - (endCellIdx + 1)
              : 0;
          final downstreamDrain = eb.itemDrainCount > endCellIdx + 1
              ? eb.itemDrainCount - (endCellIdx + 1)
              : 0;
          if (downstreamFill > 0) {
            if (newItemId.isNotEmpty || eb.lastItemFillCount > 0) {
              // 新传送带已有物品，下游物品转为残留
              newLastItemId = eb.itemId;
              newLastItemFillCount = downstreamFill + offset;
              newLastItemDrainCount = downstreamDrain + offset;
            } else {
              newItemId = eb.itemId;
              newItemFillCount = downstreamFill + offset;
              newItemDrainCount = downstreamDrain + offset;
            }
          }
        }
      }

      final belt = ConveyorBelt(
        id: 'belt_${DateTime.now().millisecondsSinceEpoch}',
        path: List<Offset>.from(fullPath),
        itemId: newItemId,
        lastItemId: newLastItemId.isNotEmpty ? newLastItemId : null,
        itemSegments: newItemSegments,
        isBlocked: false,
        incomingDirection: newBeltIncomingDir,
        phaseOffset: newPhaseOffset,
        itemFillCount: newItemFillCount,
        itemDrainCount: newItemDrainCount,
        lastItemFillCount: newLastItemFillCount,
        lastItemDrainCount: newLastItemDrainCount,
        deadEndFreezeProgress: newDeadEndFreezeProgress,
        lastItemFreezeProgress: newLastItemFreezeProgress,
      );

      // 检查新传送带的起点是否在某条旧传送带的节点上，进行截断与拆分
      final toRemove = <ConveyorBelt>[];
      final toAdd = <ConveyorBelt>[];

      for (final oldBelt in project.conveyors) {
        if (_committedBeltId != null && oldBelt.id == _committedBeltId) {
          toRemove.add(oldBelt);
          continue;
        }

        if (startsAtBridge) {
          if (bridgeSourceBelt != null &&
              identical(oldBelt, bridgeSourceBelt)) {
            toRemove.add(oldBelt);
          }
          continue;
        }

        // 跳过合并目标（会单独移除）
        if (_mergeTarget != null && identical(oldBelt, _mergeTarget)) continue;

        // 设备输出端口起点：不截断任何旧传送带
        // 1x1建筑输入/输出端口共享同一格子，输入传送带的终点在此，不应被移除
        if (startIsDeviceOutputPort) continue;

        int forkIdx = -1;
        for (int i = 0; i < oldBelt.path.length; i++) {
          if (oldBelt.path[i].dx == startCell.dx &&
              oldBelt.path[i].dy == startCell.dy) {
            forkIdx = i;
            break;
          }
        }

        if (forkIdx >= 0) {
          toRemove.add(oldBelt);
          // 保留分叉点之后的下游部分（不含分叉点，分叉点归属新传送带）
          if (forkIdx + 1 < oldBelt.path.length) {
            final downstream = oldBelt.path.sublist(forkIdx + 1);
            final isDanglingInputPortStub = downstream.length == 1 &&
                _isCellDeviceInputPort(downstream.single);
            if (downstream.isNotEmpty && !isDanglingInputPortStub) {
              // 单格下游无法从路径邻居推断方向，从旧传送带记录原始方向
              String? forcedDir;
              if (downstream.length == 1 && forkIdx + 1 < oldBelt.path.length) {
                final dx =
                    oldBelt.path[forkIdx + 1].dx - oldBelt.path[forkIdx].dx;
                final dy =
                    oldBelt.path[forkIdx + 1].dy - oldBelt.path[forkIdx].dy;
                if (dx > 0) {
                  forcedDir = 'right';
                } else if (dx < 0) {
                  forcedDir = 'left';
                } else if (dy > 0) {
                  forcedDir = 'down';
                } else if (dy < 0) {
                  forcedDir = 'up';
                }
              }
              // 下游首格的入方向：从分叉点指向下游首格
              String? incomingDir;
              if (forkIdx >= 0) {
                final dx =
                    oldBelt.path[forkIdx + 1].dx - oldBelt.path[forkIdx].dx;
                final dy =
                    oldBelt.path[forkIdx + 1].dy - oldBelt.path[forkIdx].dy;
                if (dx > 0) {
                  incomingDir = 'right';
                } else if (dx < 0) {
                  incomingDir = 'left';
                } else if (dy > 0) {
                  incomingDir = 'down';
                } else if (dy < 0) {
                  incomingDir = 'up';
                }
              }
              toAdd.add(ConveyorBelt(
                id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${oldBelt.id}',
                path: downstream,
                itemId: oldBelt.itemId,
                lastItemId: oldBelt.lastItemId,
                itemSegments: oldBelt.clippedItemSegments(
                  forkIdx + 1,
                  oldBelt.path.length,
                  clearFreezeProgress: true,
                ),
                isBlocked: oldBelt.isBlocked,
                forcedDirection: forcedDir,
                incomingDirection: incomingDir,
                phaseOffset: oldBelt.phaseOffset,
                itemFillCount:
                    _clampDownstreamCount(oldBelt.itemFillCount, forkIdx + 1),
                itemDrainCount:
                    _clampDownstreamCount(oldBelt.itemDrainCount, forkIdx + 1),
                lastItemFillCount: oldBelt.lastItemFillCount > 0
                    ? _clampDownstreamCount(
                        oldBelt.lastItemFillCount, forkIdx + 1)
                    : 0,
                lastItemDrainCount: oldBelt.lastItemFillCount > 0
                    ? _clampDownstreamCount(
                        oldBelt.lastItemDrainCount, forkIdx + 1)
                    : 0,
              ));
            }
          }
        }
      }

      // 移除合并目标
      if (_mergeTarget != null) {
        toRemove.add(_mergeTarget!);
      }

      // 截断终点所在的旧传送带：创建上游部分为独立传送带
      if (endCellBelt != null && endCellIdx >= 0) {
        final eb = endCellBelt;
        toRemove.add(eb);
        // 创建上游部分（0 到 endCellIdx-1，不含终点格子）
        if (endCellIdx > 0) {
          final upstream = eb.path.sublist(0, endCellIdx);
          final isDanglingInputPortStub = upstream.length == 1 &&
              _isCellDeviceInputPort(upstream.single);
          if (upstream.isNotEmpty && !isDanglingInputPortStub) {
            String? forcedDir;
            if (upstream.length == 1) {
              final dx = eb.path[endCellIdx].dx -
                  eb.path[endCellIdx - 1].dx;
              final dy = eb.path[endCellIdx].dy -
                  eb.path[endCellIdx - 1].dy;
              if (dx > 0) {
                forcedDir = 'right';
              } else if (dx < 0) {
                forcedDir = 'left';
              } else if (dy > 0) {
                forcedDir = 'down';
              } else if (dy < 0) {
                forcedDir = 'up';
              }
            }
            toAdd.add(ConveyorBelt(
              id:
                  'belt_${DateTime.now().millisecondsSinceEpoch}_upstream_${eb.id}',
              path: upstream,
              itemId: eb.itemId,
              lastItemId: eb.lastItemId,
              itemSegments: eb.clippedItemSegments(
                0,
                endCellIdx,
                clearFreezeProgress: true,
              ),
              isBlocked: eb.isBlocked,
              forcedDirection: forcedDir,
              incomingDirection: eb.incomingDirection,
              phaseOffset: eb.phaseOffset,
              itemFillCount:
                  eb.itemFillCount.clamp(0, endCellIdx).toInt(),
              itemDrainCount:
                  eb.itemDrainCount.clamp(0, endCellIdx).toInt(),
              lastItemFillCount: eb.lastItemFillCount > 0
                  ? eb.lastItemFillCount
                      .clamp(0, endCellIdx)
                      .toInt()
                  : 0,
              lastItemDrainCount: eb.lastItemFillCount > 0
                  ? eb.lastItemDrainCount
                      .clamp(0, endCellIdx)
                      .toInt()
                  : 0,
            ));
          }
        }
        // 下游部分未合并到 fullPath 时，创建为独立传送带
        if (!endCellDownstreamMerged &&
            endCellIdx + 1 < eb.path.length) {
          final downstream = eb.path.sublist(endCellIdx + 1);
          final isDanglingInputPortStub = downstream.length == 1 &&
              _isCellDeviceInputPort(downstream.single);
          if (downstream.isNotEmpty && !isDanglingInputPortStub) {
            String? forcedDir;
            if (downstream.length == 1) {
              final dx = eb.path[endCellIdx + 1].dx -
                  eb.path[endCellIdx].dx;
              final dy = eb.path[endCellIdx + 1].dy -
                  eb.path[endCellIdx].dy;
              if (dx > 0) {
                forcedDir = 'right';
              } else if (dx < 0) {
                forcedDir = 'left';
              } else if (dy > 0) {
                forcedDir = 'down';
              } else if (dy < 0) {
                forcedDir = 'up';
              }
            }
            String? incomingDir;
            final dx = eb.path[endCellIdx + 1].dx -
                eb.path[endCellIdx].dx;
            final dy = eb.path[endCellIdx + 1].dy -
                eb.path[endCellIdx].dy;
            if (dx > 0) {
              incomingDir = 'right';
            } else if (dx < 0) {
              incomingDir = 'left';
            } else if (dy > 0) {
              incomingDir = 'down';
            } else if (dy < 0) {
              incomingDir = 'up';
            }
            toAdd.add(ConveyorBelt(
              id:
                  'belt_${DateTime.now().millisecondsSinceEpoch}_enddown_${eb.id}',
              path: downstream,
              itemId: eb.itemId,
              lastItemId: eb.lastItemId,
              itemSegments: eb.clippedItemSegments(
                endCellIdx + 1,
                eb.path.length,
                clearFreezeProgress: true,
              ),
              isBlocked: eb.isBlocked,
              forcedDirection: forcedDir,
              incomingDirection: incomingDir,
              phaseOffset: eb.phaseOffset,
              itemFillCount: _clampDownstreamCount(
                  eb.itemFillCount, endCellIdx + 1),
              itemDrainCount: _clampDownstreamCount(
                  eb.itemDrainCount, endCellIdx + 1),
              lastItemFillCount: eb.lastItemFillCount > 0
                  ? _clampDownstreamCount(
                      eb.lastItemFillCount, endCellIdx + 1)
                  : 0,
              lastItemDrainCount: eb.lastItemFillCount > 0
                  ? _clampDownstreamCount(
                      eb.lastItemDrainCount, endCellIdx + 1)
                  : 0,
            ));
          }
        }
      }

      for (final old in toRemove) {
        project.conveyors.remove(old);
      }
      for (final newBelt in toAdd) {
        project.conveyors.add(newBelt);
      }

      // 传送带不再在物流桥处拆分，保持完整路径
      // 物品直接穿过物流桥格子，不需要通过物流桥库存中转
      // 这样断头时整条传送带自然停止，延长/截断时物品状态完整继承
      project.conveyors.add(belt);
      project.offsetX; // no-op to ensure project reference works
      onProjectChanged(project);
      onRebuildCache();

      if (keepCreating) {
        _committedBeltId = belt.id;
        _lastCommittedPathLength = fullPath.length;
        _mergeTarget = null;
        _truncatedBeltTail = [];
        if (fullPath.length >= 2) {
          _incomingDirection =
              _directionBetween(fullPath[fullPath.length - 2], fullPath.last);
        }
        return;
      }
    }

    reset();
  }

  // === 辅助方法 ===

  /// 查找以 gridPos 为起点的传送带（合并候选）
  ConveyorBelt? _findBeltStartCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (belt.path.isNotEmpty) {
        final start = belt.path.first;
        if (start.dx.toInt() == gx && start.dy.toInt() == gy) {
          return belt;
        }
      }
    }
    return null;
  }

  /// 查找与 fromCell 相邻且方向兼容的传送带起点（转角吸附）
  /// 返回 (传送带, 起点坐标) 或 null
  /// 只有当从 fromCell 到相邻起点的方向与传送带出方向一致时才吸附，
  /// 这样确保路径在连接点处与传送带方向吻合，不会产生 S 弯
  (ConveyorBelt, Offset)? _findAdjacentBeltStart(Offset fromCell) {
    final fx = fromCell.dx.toInt();
    final fy = fromCell.dy.toInt();
    // 检查四个方向
    const dirs = [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)];
    for (final d in dirs) {
      final nx = fx + d.dx.toInt();
      final ny = fy + d.dy.toInt();
      final neighbor = Offset(nx.toDouble(), ny.toDouble());
      final belt = _findBeltStartCell(neighbor);
      if (belt == null) continue;
      // 排除已在路径中的格子
      if (fullPath.any((c) => c.dx == neighbor.dx && c.dy == neighbor.dy)) {
        continue;
      }
      // 排除 anchors 中的格子（路径起点），防止转角吸附导致路径回环
      // 如从分流器向左创建传送带时，预览末尾检测到分流器格子上已有传送带起点，
      // 导致预览路径回环到起点形成 U 型弯
      if (anchors.any((a) => a.dx == neighbor.dx && a.dy == neighbor.dy)) {
        continue;
      }
      // 检查方向兼容性：从 fromCell 到 neighbor 的方向必须与传送带出方向一致
      final toDx = d.dx.toInt();
      final toDy = d.dy.toInt();
      if (_directionMatchesBeltOutgoing(toDx, toDy, belt)) {
        return (belt, neighbor);
      }
    }
    return null;
  }

  ConveyorBelt? _findBridgeContinuationSourceBelt(
      Offset bridgeCell, String? outgoingDirection) {
    if (outgoingDirection == null) return null;
    final bx = bridgeCell.dx.toInt();
    final by = bridgeCell.dy.toInt();
    for (final belt in project.conveyors) {
      for (int i = 0; i < belt.path.length; i++) {
        final cell = belt.path[i];
        if (cell.dx.toInt() != bx || cell.dy.toInt() != by) continue;
        if (i != belt.path.length - 1) continue;
        if (_getBeltDirectionAtCell(belt, i) == outgoingDirection) {
          return belt;
        }
      }
    }
    return null;
  }

  bool _isBlockedBridgeStartSegment(List<Offset> segment) {
    if (segment.length < 2) return false;
    if (_findBeltBridgeAtCell(segment.first) == null) return false;
    return _findBeltAtCell(segment[1]) != null;
  }

  /// 获取传送带的方向向量 (dx, dy)，如果无法确定则返回 null
  (int, int)? _getBeltDirectionVector(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      final beltStart = belt.path.first;
      final beltNext = belt.path[1];
      final beltDx = (beltNext.dx - beltStart.dx).toInt();
      final beltDy = (beltNext.dy - beltStart.dy).toInt();
      return (beltDx, beltDy);
    } else if (belt.forcedDirection != null) {
      final dir = belt.forcedDirection!;
      final beltDx = switch (dir) { 'right' => 1, 'left' => -1, _ => 0 };
      final beltDy = switch (dir) { 'down' => 1, 'up' => -1, _ => 0 };
      return (beltDx, beltDy);
    }
    return null;
  }

  /// 检查给定方向是否与传送带的出方向一致
  bool _directionMatchesBeltOutgoing(int dx, int dy, ConveyorBelt belt) {
    final direction = _getBeltDirectionVector(belt);
    if (direction == null) return false;
    final (beltDx, beltDy) = direction;
    return dx == beltDx && dy == beltDy;
  }

  int _clampDownstreamCount(int count, int removedPrefixLength) {
    final shifted = count - removedPrefixLength;
    return shifted > 0 ? shifted : 0;
  }

  bool _isPathPrefix(List<Offset> prefix, List<Offset> path) {
    if (prefix.length > path.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (prefix[i].dx.toInt() != path[i].dx.toInt() ||
          prefix[i].dy.toInt() != path[i].dy.toInt()) {
        return false;
      }
    }
    return true;
  }

  String? _directionBetween(Offset from, Offset to) {
    final dx = (to.dx - from.dx).toInt();
    final dy = (to.dy - from.dy).toInt();
    if (dx > 0) return 'right';
    if (dx < 0) return 'left';
    if (dy > 0) return 'down';
    if (dy < 0) return 'up';
    return null;
  }

  /// 验证路径在物流桥格子处是否保持直线（不能在物流桥内转弯）
  bool _isPathValidAtBridges(List<Offset> path) {
    for (int i = 0; i < path.length; i++) {
      if (_findBeltBridgeAtCell(path[i]) == null) continue;
      // 物流桥格子：前后方向必须一致
      final dirIn = i > 0 ? _directionBetween(path[i - 1], path[i]) : null;
      final dirOut =
          i < path.length - 1 ? _directionBetween(path[i], path[i + 1]) : null;
      if (dirIn != null && dirOut != null && dirIn != dirOut) {
        return false; // 在物流桥处转弯，路径无效
      }
    }
    return true;
  }

  /// 检查新路径在连接点处的方向是否与目标传送带起始方向一致
  bool _isDirectionCompatible(List<Offset> newPath, ConveyorBelt targetBelt) {
    if (newPath.length < 2) return false;

    // 新路径在连接点处的方向（倒数第二格 -> 最后一格）
    final lastCell = newPath.last;
    final prevCell = newPath[newPath.length - 2];
    final newDx = lastCell.dx - prevCell.dx;
    final newDy = lastCell.dy - prevCell.dy;

    // 目标传送带在起点处的方向
    final direction = _getBeltDirectionVector(targetBelt);
    if (direction == null) return false;
    final (beltDx, beltDy) = direction;

    // 方向兼容：不允许反方向合并（新路径到达方向与目标传送带出方向相反）
    // 直线合并和转角合并都允许
    return !(newDx == -beltDx && newDy == -beltDy);
  }

  ConveyorBelt? _findBeltAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return belt;
      }
    }
    return null;
  }

  /// 查找包含指定格子的传送带，排除指定 ID 的传送带
  ConveyorBelt? _findBeltAtCellExcluding(Offset gridPos, String? excludeId) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (excludeId != null && belt.id == excludeId) continue;
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return belt;
      }
    }
    return null;
  }

  List<Offset> _traceBeltToCell(ConveyorBelt belt, Offset cell) {
    final result = <Offset>[];
    final cx = cell.dx.toInt();
    final cy = cell.dy.toInt();
    for (final c in belt.path) {
      result.add(c);
      if (c.dx.toInt() == cx && c.dy.toInt() == cy) break;
    }
    return result;
  }

  bool _isCellInBuilding(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 查找指定格子上的物流桥建筑
  PlacedBuilding? _findBeltBridgeAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (!pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return pb;
      }
    }

    return null;
  }

  /// 查找指定格子上的传送带方向向量（排除物流桥、已提交传送带、合并目标）。
  /// 用于检测路径是否与现有传送带平行重叠或在交叉点转弯。
  /// 返回 (dx, dy) 方向向量，如果格子不在任何传送带上则返回 null。
  (int, int)? _getCrossingBeltDirectionAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      for (int j = 0; j < belt.path.length; j++) {
        if (belt.path[j].dx.toInt() == gx &&
            belt.path[j].dy.toInt() == gy) {
          final dir = _getBeltDirectionAtCell(belt, j);
          if (dir == null) return null;
          final dx = switch (dir) { 'right' => 1, 'left' => -1, _ => 0 };
          final dy = switch (dir) { 'down' => 1, 'up' => -1, _ => 0 };
          return (dx, dy);
        }
      }
    }
    return null;
  }

  /// 验证路径不与现有传送带平行重叠，且在交叉点处保持直线（不能转弯）。
  /// 跳过起点（分叉/延长点）。
  /// 终点格子若为合并候选（传送带起点）则允许平行方向（合并连接）。
  bool _isPathValidAtBeltCrossings(List<Offset> path) {
    for (int i = 1; i < path.length; i++) {
      final cell = path[i];
      // 物流桥格子由 _isPathValidAtBridges 处理
      if (_findBeltBridgeAtCell(cell) != null) continue;

      final beltDir = _getCrossingBeltDirectionAtCell(cell);
      if (beltDir == null) continue; // 不在任何传送带上

      // 物流桥不能在转角传送带格子上创建：穿过转角格子则路径无效
      if (_isCrossingBeltCellTurn(cell)) return false;

      final (beltDx, _) = beltDir;
      final dirIn = _directionBetween(path[i - 1], path[i]);
      final dirOut = i + 1 < path.length
          ? _directionBetween(path[i], path[i + 1])
          : null;
      if (dirIn == null) continue;

      final pathDx = switch (dirIn) { 'right' => 1, 'left' => -1, _ => 0 };
      final isPathDirVertical = pathDx == 0;
      final isBeltDirVertical = beltDx == 0;

      // 平行重叠检查
      if (isPathDirVertical == isBeltDirVertical) {
        // 终点格子若为合并候选（传送带起点）则允许
        if (i == path.length - 1 && _isMergeCandidateCell(cell)) {
          // 允许合并连接
        } else {
          return false;
        }
      }

      // 交叉点处必须直线通过（不能转弯）
      if (dirOut != null && dirIn != dirOut) {
        return false;
      }
    }
    return true;
  }

  /// 检查格子是否为合并候选（传送带起点，排除已提交传送带和合并目标）
  bool _isMergeCandidateCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      if (belt.path.isNotEmpty &&
          belt.path.first.dx.toInt() == gx &&
          belt.path.first.dy.toInt() == gy) {
        return true;
      }
    }
    return false;
  }

  /// 判断两个方向是否垂直交叉（一个水平一个垂直）
  bool _isPerpendicularCrossing(String? dir1, String? dir2) {
    if (dir1 == null || dir2 == null) return false;
    final isVertical1 = dir1 == 'up' || dir1 == 'down';
    final isVertical2 = dir2 == 'up' || dir2 == 'down';
    return isVertical1 != isVertical2;
  }

  /// 获取传送带在指定格子处的移动方向
  String? _getBeltDirectionAtCell(ConveyorBelt belt, int cellIndex) {
    if (belt.path.length < 2) return belt.forcedDirection;
    if (cellIndex > 0 && cellIndex < belt.path.length) {
      return _directionBetween(belt.path[cellIndex - 1], belt.path[cellIndex]);
    }
    if (cellIndex == 0 && belt.path.length >= 2) {
      return _directionBetween(belt.path[0], belt.path[1]);
    }
    return null;
  }

  /// 判断已有传送带的指定格子是否是转角（与 canvas_editor 中 _isStraightBeltCell 相反）
  /// 物流桥不能在转角传送带格子上创建
  bool _isBeltCellTurn(ConveyorBelt belt, int cellIndex) {
    final path = belt.path;
    if (path.isEmpty || cellIndex < 0 || cellIndex >= path.length) {
      return false;
    }

    // 单格路径：仅当入方向与强制方向都存在且不同时为转角
    if (path.length == 1) {
      final incoming = belt.incomingDirection;
      final forced = belt.forcedDirection;
      return incoming != null && forced != null && incoming != forced;
    }

    // 首格：需要 incomingDirection 与出方向比较
    if (cellIndex == 0) {
      final incoming = belt.incomingDirection;
      if (incoming == null) return false;
      final outgoing = _directionBetween(path[0], path[1]);
      if (outgoing == null) return false;
      return incoming != outgoing;
    }

    // 末格：与 _isStraightBeltCell 一致，末格不算转角
    if (cellIndex == path.length - 1) return false;

    // 中间格：入方向与出方向不同则为转角
    final dirIn = _directionBetween(path[cellIndex - 1], path[cellIndex]);
    final dirOut = _directionBetween(path[cellIndex], path[cellIndex + 1]);
    if (dirIn == null || dirOut == null) return false;
    return dirIn != dirOut;
  }

  /// 检查指定格子处的已有传送带格子是否是转角（排除已提交传送带和合并目标）
  bool _isCrossingBeltCellTurn(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      for (int j = 0; j < belt.path.length; j++) {
        if (belt.path[j].dx.toInt() == gx &&
            belt.path[j].dy.toInt() == gy) {
          return _isBeltCellTurn(belt, j);
        }
      }
    }
    return false;
  }

  /// 获取路径在指定索引处的移动方向
  String? _getPathDirectionAtIndex(List<Offset> path, int index) {
    if (path.length < 2) return null;
    if (index > 0) {
      return _directionBetween(path[index - 1], path[index]);
    }
    if (index == 0 && path.length >= 2) {
      return _directionBetween(path[0], path[1]);
    }
    return null;
  }

  /// 检测 fullPath 与已有传送带的垂直交叉，自动放置物流桥建筑
  /// 不再拆分被交叉的传送带——传送带保持完整路径，物品直接穿过物流桥格子
  void _autoCreateBridgesAtCrossings() {
    // 1. 收集所有交叉点
    final crossings = <Offset>[];

    for (int i = 0; i < fullPath.length; i++) {
      final cell = fullPath[i];
      final newDir = _getPathDirectionAtIndex(fullPath, i);

      for (final belt in project.conveyors) {
        // Skip committed belt and merge target
        if (_committedBeltId != null && belt.id == _committedBeltId) continue;
        if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;

        for (int j = 0; j < belt.path.length; j++) {
          if (belt.path[j].dx.toInt() == cell.dx.toInt() &&
              belt.path[j].dy.toInt() == cell.dy.toInt()) {
            final beltDir = _getBeltDirectionAtCell(belt, j);
            if (_isPerpendicularCrossing(newDir, beltDir)) {
              // Check if there's already a bridge at this cell
              if (_findBeltBridgeAtCell(cell) != null) continue;
              // 交叉点已有建筑（如分流器、汇流器等）时不创建物流桥
              if (_isCellOccupied(cell)) continue;
              // 物流桥不能在转角传送带格子上创建
              if (_isBeltCellTurn(belt, j)) continue;
              crossings.add(cell);
            }
          }
        }
      }
    }

    if (crossings.isEmpty) return;

    // 2. 放置所有物流桥建筑
    for (final cell in crossings) {
      // 再次检查是否已有物流桥（前面的交叉可能已经放置了）
      if (_findBeltBridgeAtCell(cell) != null) continue;
      final building = getBuilding?.call(_beltBridgeId);
      if (building == null) continue;

      final newBridge = PlacedBuilding(
        id: 'building_${DateTime.now().millisecondsSinceEpoch}',
        building: building,
        gridX: cell.dx - (building.gridWidth ~/ 2).toDouble(),
        gridY: cell.dy - (building.gridHeight ~/ 2).toDouble(),
        rotation: 0,
      );
      project.buildings.add(newBridge);
    }

    // 不再拆分被交叉的传送带——传送带保持完整路径穿过物流桥
  }

  /// 计算预览路径上需要放置物流桥的交叉点（仅用于预览渲染，不实际创建建筑）
  List<Offset> _computePreviewBridgeCells() {
    if (pathInvalid) return [];
    // 构建完整预览路径（已确认段 + 实时段）
    final fullPreviewPath = <Offset>[...confirmedPath];
    if (previewPath != null) {
      // 去重：已确认段末尾和实时段开头可能重叠
      if (fullPreviewPath.isNotEmpty && previewPath!.isNotEmpty &&
          fullPreviewPath.last.dx == previewPath!.first.dx &&
          fullPreviewPath.last.dy == previewPath!.first.dy) {
        fullPreviewPath.addAll(previewPath!.skip(1));
      } else {
        fullPreviewPath.addAll(previewPath!);
      }
    }
    if (fullPreviewPath.length < 2) return [];

    final crossings = <Offset>[];
    for (int i = 0; i < fullPreviewPath.length; i++) {
      final cell = fullPreviewPath[i];
      final newDir = _getPathDirectionAtIndex(fullPreviewPath, i);
      for (final belt in project.conveyors) {
        if (_committedBeltId != null && belt.id == _committedBeltId) continue;
        if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
        for (int j = 0; j < belt.path.length; j++) {
          if (belt.path[j].dx.toInt() == cell.dx.toInt() &&
              belt.path[j].dy.toInt() == cell.dy.toInt()) {
            final beltDir = _getBeltDirectionAtCell(belt, j);
            if (_isPerpendicularCrossing(newDir, beltDir)) {
              if (_findBeltBridgeAtCell(cell) != null) continue;
              // 交叉点已有建筑（如分流器、汇流器等）时不创建物流桥
              if (_isCellOccupied(cell)) continue;
              // 物流桥不能在转角传送带格子上创建
              if (_isBeltCellTurn(belt, j)) continue;
              if (crossings.any((c) =>
                  c.dx.toInt() == cell.dx.toInt() &&
                  c.dy.toInt() == cell.dy.toInt())) {
                continue;
              }
              crossings.add(cell);
            }
          }
        }
      }
    }
    return crossings;
  }

  bool _isCellOccupied(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    // Belt cells are not considered occupied (belts can cross each other)
    for (final pb in project.buildings) {
      // 物流桥格子不视为已占用（传送带可穿过）
      if (pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  Set<String> _getOccupiedCellSet() {
    final cells = <String>{};
    // Do NOT add belt cells - belts can cross each other perpendicularly
    for (final pb in project.buildings) {
      // 物流桥格子不视为已占用（传送带可穿过）
      if (pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      for (int dx = 0; dx < pb.effectiveWidth; dx++) {
        for (int dy = 0; dy < pb.effectiveHeight; dy++) {
          cells.add('${bx + dx}_${by + dy}');
        }
      }
    }
    return cells;
  }

  Set<String> _buildBlockedSet({Offset? excludeCell}) {
    final blocked = _getOccupiedCellSet();

    for (final cell in fullPath) {
      blocked.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
    }

    // 截断创建时，原传送带截断点之后的剩余格子视为阻挡
    for (final cell in _truncatedBeltTail) {
      blocked.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
    }

    if (anchors.isNotEmpty) {
      blocked.remove('${anchors.last.dx.toInt()}_${anchors.last.dy.toInt()}');
    }
    if (excludeCell != null) {
      blocked.remove('${excludeCell.dx.toInt()}_${excludeCell.dy.toInt()}');
    }
    return blocked;
  }

  bool _isIncomingVertical() {
    if (anchors.length < 2) return false;
    final prev = anchors[anchors.length - 2];
    final last = anchors.last;
    return (last.dy - prev.dy).abs() > (last.dx - prev.dx).abs();
  }

  // === 设备端口检测 ===

  /// 在 gridPos 处查找设备端口，返回 (设备, 端口定义, 'input'/'output', 旋转后的世界方向)
  ({
    PlacedBuilding building,
    PortDefinition definition,
    String type,
    String worldDirection
  })? _findPortAtCell(Offset gridPos, {String? preferredType}) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();

    ({
      PlacedBuilding building,
      PortDefinition definition,
      String type,
      String worldDirection
    })? findPortOfType(PlacedBuilding pb, String type) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      final ports = type == 'input' ? pb.inputPorts : pb.outputPorts;
      for (final port in ports) {
        final portGrid =
            port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        final px = portGrid.dx.round();
        final py = portGrid.dy.round();
        if (px == gx && py == gy) {
          return (
            building: pb,
            definition: port.definition,
            type: type,
            worldDirection: _rotateDirection(port.definition.direction, rot),
          );
        }
      }
      return null;
    }

    for (final pb in project.buildings) {
      if (preferredType != null) {
        final preferred = findPortOfType(pb, preferredType);
        if (preferred != null) return preferred;
        final fallback =
            findPortOfType(pb, preferredType == 'input' ? 'output' : 'input');
        if (fallback != null) return fallback;
      } else {
        final input = findPortOfType(pb, 'input');
        if (input != null) return input;
        final output = findPortOfType(pb, 'output');
        if (output != null) return output;
      }
    }
    return null;
  }

  String _rotateDirection(String original, int rotation) {
    const directions = ['up', 'right', 'down', 'left'];
    final idx = directions.indexOf(original);
    if (idx == -1) return original;
    return directions[(idx + rotation) % 4];
  }

  /// 检查路径中是否至少有一个不在任何设备内部的格子（独立传送带格子）
  /// 设备输入/输出端口之间必须预留至少一格给传送带显示
  /// 物流桥格子视为可穿过，不算作设备内部
  bool _hasIndependentBeltCell(List<Offset> path) {
    for (final cell in path) {
      if (!_isCellInBuilding(cell)) {
        return true;
      }
      // 物流桥格子视为独立格子（传送带可穿过）
      if (_findBeltBridgeAtCell(cell) != null) {
        return true;
      }
    }
    return false;
  }

  /// 检查 gridPos 是否为设备的输入端口格子
  bool _isCellDeviceInputPort(Offset gridPos) {
    final portInfo = _findPortAtCell(gridPos, preferredType: 'input');
    return portInfo != null && portInfo.type == 'input';
  }

  /// 检查 gridPos 是否在某个有输入端口的建筑内（如1x1分流器）。
  /// _isCellDeviceInputPort 对1x1建筑无效（端口在格边缘），此函数补检。
  bool _buildingAtCellHasInputPort(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (pb.inputPorts.isEmpty) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 检查目标格子是否被有输出端口的建筑占据（不依赖端口坐标，解决 1x1 建筑坐标偏差问题）
  bool _buildingAtCellHasOutputPort(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (pb.outputPorts.isEmpty) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 计算建筑在 gridPos 处的所有输出端口旋转后的世界方向集合。
  /// 用于限制传送带首段只能沿这些方向创建，阻止往输入端方向创建。
  Set<String>? _computeAllowedDirectionsForBuilding(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    final dirs = <String>{};
    for (final pb in project.buildings) {
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx < bx || gx >= bx + pb.effectiveWidth ||
          gy < by || gy >= by + pb.effectiveHeight) {
        continue;
      }
      final rot = pb.rotation;
      for (final port in pb.outputPorts) {
        final worldDir = _rotateDirection(port.definition.direction, rot);
        if (worldDir.isNotEmpty) dirs.add(worldDir);
      }
    }
    return dirs.isNotEmpty ? dirs : null;
  }

  // === 预览 ===

  void _updatePreview() {
    if (anchors.isEmpty || mouseGridPos == null) {
      previewPath = null;
      previewOccupied = null;
      confirmedPath = [];
      pathInvalid = false;
      previewBridgeCells = [];
      return;
    }
    final lastAnchor = anchors.last;

    // 检查鼠标是否悬停在某条传送带的起点（合并候选）
    final mergeBelt = _findBeltStartCell(mouseGridPos!);
    // 检查鼠标是否悬停在设备输入端口
    final isInputPort = _isCellDeviceInputPort(mouseGridPos!);

    Offset? excludeCell;
    if (mergeBelt != null) {
      final alreadyInPath = fullPath
          .any((c) => c.dx == mouseGridPos!.dx && c.dy == mouseGridPos!.dy);
      if (!alreadyInPath) {
        excludeCell = mouseGridPos!;
      }
    } else if (isInputPort) {
      excludeCell = mouseGridPos!;
    }

    final blocked = _buildBlockedSet(excludeCell: excludeCell);
    final verticalFirst = _isIncomingVertical();

    final livePath = _findPath(lastAnchor, mouseGridPos!, blocked,
        verticalFirst: verticalFirst);
    if (livePath == null) {
      confirmedPath = fullPath.length > 1
          ? fullPath.sublist(0, fullPath.length - 1)
          : <Offset>[];
      previewPath = _calculateStraightPath(lastAnchor, mouseGridPos!);
      previewOccupied = null;
      pathInvalid = true;
    } else {
      confirmedPath = fullPath.length > 1
          ? fullPath.sublist(0, fullPath.length - 1)
          : <Offset>[];
      previewPath = livePath;
      previewOccupied = null;
      if (_isBlockedBridgeStartSegment(livePath)) {
        pathInvalid = true;
        previewContextExtension = null;
        return;
      }

      // 悬停在传送带起点时，检查方向兼容性
      if (mergeBelt != null && excludeCell != null) {
        if (!_isDirectionCompatible(livePath, mergeBelt)) {
          pathInvalid = true;
          previewContextExtension = null;
        } else {
          pathInvalid = false;
          // 将合并目标的路径作为转角上下文扩展（仅用于转角检测，不渲染为蓝色预览）
          if (mergeBelt.path.length > 1) {
            previewContextExtension = mergeBelt.path.sublist(1);
          } else {
            previewContextExtension = null;
          }
        }
      } else if (livePath.length >= 2) {
        // 转角吸附：预览路径末尾检测相邻的传送带起点
        final lastCell = livePath.last;
        final adjacent = _findAdjacentBeltStart(lastCell);
        if (adjacent != null) {
          // 将相邻传送带起点追加到预览路径（只有1格，可以显示为蓝色预览）
          previewPath = [...livePath, adjacent.$2];
          // 如果相邻传送带有多格，将其余格子作为转角上下文扩展
          if (adjacent.$1.path.length > 1) {
            previewContextExtension = adjacent.$1.path.sublist(1);
          } else {
            previewContextExtension = null;
          }
        } else {
          previewContextExtension = null;
        }
        pathInvalid = false;
      } else {
        pathInvalid = false;
        previewContextExtension = null;
      }

      // 设备输入/输出端口之间必须预留至少一格给传送带显示
      if (!pathInvalid && isInputPort) {
        final prospectivePath = <Offset>[
          ...confirmedPath,
          ...previewPath!,
        ];
        if (!_hasIndependentBeltCell(prospectivePath)) {
          pathInvalid = true;
        }
      }
    }

    // 计算预览路径上的物流桥交叉点（用于渲染物流桥预览）
    previewBridgeCells = _computePreviewBridgeCells();
  }

  List<Offset> _deduplicatePath(List<Offset> path) {
    if (path.length < 2) return path;
    final result = <Offset>[path.first];
    for (int i = 1; i < path.length; i++) {
      if (path[i] != path[i - 1]) {
        result.add(path[i]);
      }
    }
    return result;
  }

  // === 寻路 ===

  List<Offset>? _findPath(Offset start, Offset end, Set<String> blocked,
      {bool verticalFirst = false}) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    // 检查终点是否为设备的输入端口
    final portInfo = _findPortAtCell(end, preferredType: 'input');
    if (portInfo != null &&
        portInfo.type == 'input' &&
        portInfo.building.building.id != _beltBridgeId) {
      final D = portInfo.worldDirection;
      final dirOffset = switch (D) {
        'up' => const Offset(0, -1),
        'down' => const Offset(0, 1),
        'left' => const Offset(-1, 0),
        'right' => const Offset(1, 0),
        _ => const Offset(0, 0),
      };

      if (dirOffset != const Offset(0, 0)) {
        final penultimate = end + dirOffset;
        final penultimateKey =
            '${penultimate.dx.toInt()}_${penultimate.dy.toInt()}';

        // 前驱格子如果被阻挡且不是起点，则寻路失败
        if (blocked.contains(penultimateKey) && penultimateKey != startKey) {
          return null;
        }

        // 暂时在寻路至前驱格子时将终点(输入端口)设为阻挡，预防擦过或斜插
        final tempBlocked = Set<String>.from(blocked)..add(endKey);
        final subPath = _findPath(start, penultimate, tempBlocked,
            verticalFirst: verticalFirst);
        if (subPath == null) return null;

        return _deduplicatePath([...subPath, end]);
      }
    }

    // 仅在创建第一段时（即 anchors.length <= 1），才施加起始端口物理方向的约束，之后的中继锚点寻路自由
    final activeDirection =
        (anchors.length <= 1) ? _startingPortDirection : null;
    final allowedDirections =
        (anchors.length <= 1) ? _startingPortAllowedDirections : null;

    // 如果有端口方向约束，优先尝试按端口方向走
    final momentumPath = _calculateMomentumPath(start, end,
        verticalFirst: verticalFirst, startingDirection: activeDirection);
    bool momentumValid = true;
    for (final cell in momentumPath) {
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      if (blocked.contains(key) && key != startKey) {
        momentumValid = false;
        break;
      }
    }
    // 验证首段方向是否在允许集合内（如分流器禁止往输入端down方向）
    if (momentumValid && allowedDirections != null && momentumPath.length >= 2) {
      final firstStepDir = _directionBetween(momentumPath[0], momentumPath[1]);
      if (firstStepDir != null && !allowedDirections.contains(firstStepDir)) {
        momentumValid = false;
      }
    }
    // 验证 momentum path 在物流桥格子处是否保持直线
    if (momentumValid && !_isPathValidAtBridges(momentumPath)) {
      momentumValid = false;
    }
    // 验证 momentum path 不与现有传送带平行重叠，且在交叉点处保持直线
    if (momentumValid && !_isPathValidAtBeltCrossings(momentumPath)) {
      momentumValid = false;
    }
    if (momentumValid) return _deduplicatePath(momentumPath);

    final bfsPath = _findPathBFS(start, end, blocked,
        firstStepDirection: activeDirection,
        allowedDirections: allowedDirections);
    return bfsPath != null ? _deduplicatePath(bfsPath) : null;
  }

  List<Offset> _calculateMomentumPath(Offset start, Offset end,
      {bool verticalFirst = false, String? startingDirection}) {
    final sx = start.dx.toInt();
    final sy = start.dy.toInt();
    final ex = end.dx.toInt();
    final ey = end.dy.toInt();

    if (sx == ex && sy == ey) return [start];

    final path = <Offset>[];
    int cx = sx;
    int cy = sy;

    if (startingDirection != null && (cx != ex || cy != ey)) {
      path.add(Offset(cx.toDouble(), cy.toDouble()));
      switch (startingDirection) {
        case 'up':
          cy -= 1;
          break;
        case 'down':
          cy += 1;
          break;
        case 'left':
          cx -= 1;
          break;
        case 'right':
          cx += 1;
          break;
      }
      if (cx == ex && cy == ey) {
        path.add(Offset(ex.toDouble(), ey.toDouble()));
        return path;
      }
      path.add(Offset(cx.toDouble(), cy.toDouble()));
      // 继续从新位置开始走剩余路径
    }

    // 从当前位置用原有逻辑走到终点
    if (verticalFirst) {
      if (cy != ey) {
        final dy = ey > cy ? 1 : -1;
        for (int y = cy; y != ey; y += dy) {
          if (path.isEmpty ||
              path.last.dx != cx.toDouble() ||
              path.last.dy != y.toDouble()) {
            path.add(Offset(cx.toDouble(), y.toDouble()));
          }
        }
      }
      if (cx != ex) {
        final dx = ex > cx ? 1 : -1;
        for (int x = cx; x != ex; x += dx) {
          if (path.isEmpty ||
              path.last.dx != x.toDouble() ||
              path.last.dy != ey.toDouble()) {
            path.add(Offset(x.toDouble(), ey.toDouble()));
          }
        }
      }
    } else {
      if (cx != ex) {
        final dx = ex > cx ? 1 : -1;
        for (int x = cx; x != ex; x += dx) {
          if (path.isEmpty ||
              path.last.dx != x.toDouble() ||
              path.last.dy != cy.toDouble()) {
            path.add(Offset(x.toDouble(), cy.toDouble()));
          }
        }
      }
      if (cy != ey) {
        final dy = ey > cy ? 1 : -1;
        for (int y = cy; y != ey; y += dy) {
          if (path.isEmpty ||
              path.last.dx != ex.toDouble() ||
              path.last.dy != y.toDouble()) {
            path.add(Offset(ex.toDouble(), y.toDouble()));
          }
        }
      }
    }

    path.add(Offset(ex.toDouble(), ey.toDouble()));
    return path;
  }

  List<Offset>? _findPathBFS(Offset start, Offset end, Set<String> blocked,
      {String? firstStepDirection, Set<String>? allowedDirections}) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    // 0=up [0,-1], 1=right [1,0], 2=down [0,1], 3=left [-1,0]
    const dirOffsets = [
      [0, -1], // 0: up
      [1, 0], // 1: right
      [0, 1], // 2: down
      [-1, 0], // 3: left
    ];

    int? dirNameToIndex(String? name) => switch (name) {
          'up' => 0,
          'right' => 1,
          'down' => 2,
          'left' => 3,
          _ => null,
        };

    final queue = <_BFSNode>[];
    // 在物流桥格子处，key 包含方向信息以允许不同方向到达同一格子
    final visited = <String, (String?, Offset?)>{};
    final startVisitKey = startKey;
    visited[startVisitKey] = (null, null);
    queue.add(_BFSNode(start.dx.toInt(), start.dy.toInt(), -1));

    int searched = 0;
    while (queue.isNotEmpty && searched < 5000) {
      final node = queue.removeAt(0);
      final nodeKey = '${node.x}_${node.y}';
      searched++;

      if (nodeKey == endKey) {
        // 回溯路径
        final path = <Offset>[];
        final endCellPos = Offset(node.x.toDouble(), node.y.toDouble());
        final endIsBridge = _findBeltBridgeAtCell(endCellPos) != null;
        final endBeltDir = endIsBridge
            ? null
            : _getCrossingBeltDirectionAtCell(endCellPos);
        final endUseDirKey = node.incomingDir >= 0 &&
            (endIsBridge || endBeltDir != null);
        String? vKey = endUseDirKey
            ? '${node.x}_${node.y}_${node.incomingDir}'
            : nodeKey;
        while (vKey != null) {
          final entry = visited[vKey];
          if (entry == null) break;
          final parts = vKey.split('_');
          path.add(Offset(double.parse(parts[0]), double.parse(parts[1])));
          final parentKey = entry.$1;
          vKey = parentKey;
        }
        return path.reversed.toList();
      }

      List<int> allowedDirIndices;
      if (nodeKey == startKey && allowedDirections != null) {
        // 优先使用多方向允许集合（如分流器允许 up/left/right，禁止 down）
        allowedDirIndices = allowedDirections
            .map((d) => dirNameToIndex(d))
            .whereType<int>()
            .toList();
        if (allowedDirIndices.isEmpty) allowedDirIndices = [0, 1, 2, 3];
      } else if (nodeKey == startKey && firstStepDirection != null) {
        final idx = dirNameToIndex(firstStepDirection);
        allowedDirIndices = idx != null ? [idx] : [0, 1, 2, 3];
      } else if (node.incomingDir >= 0) {
        final cellPos = Offset(node.x.toDouble(), node.y.toDouble());
        final isBridge = _findBeltBridgeAtCell(cellPos) != null;
        if (isBridge) {
          // 物流桥格子：只允许沿入方向直线通过
          allowedDirIndices = [node.incomingDir];
        } else {
          final beltDir = _getCrossingBeltDirectionAtCell(cellPos);
          if (beltDir != null) {
            // 传送带交叉点：只允许沿入方向直线通过（不能转弯）
            allowedDirIndices = [node.incomingDir];
          } else {
            allowedDirIndices = [0, 1, 2, 3];
          }
        }
      } else {
        allowedDirIndices = [0, 1, 2, 3];
      }

      for (final dirIdx in allowedDirIndices) {
        final d = dirOffsets[dirIdx];
        final nx = node.x + d[0];
        final ny = node.y + d[1];
        final nKey = '${nx}_$ny';
        if (blocked.contains(nKey) && nKey != startKey) continue;

        final neighborPos = Offset(nx.toDouble(), ny.toDouble());
        final isNeighborBridge = _findBeltBridgeAtCell(neighborPos) != null;

        // 检查是否与现有传送带平行重叠
        // 终点格子若为合并候选（传送带起点）则允许平行方向（合并连接）
        final isEndCell = nKey == endKey;
        if (!isNeighborBridge) {
          final neighborBeltDir =
              _getCrossingBeltDirectionAtCell(neighborPos);
          if (neighborBeltDir != null) {
            final (beltDx, _) = neighborBeltDir;
            final isNewDirVertical = d[0] == 0;
            final isBeltDirVertical = beltDx == 0;
            if (isNewDirVertical == isBeltDirVertical) {
              // 平行重叠
              if (isEndCell && _isMergeCandidateCell(neighborPos)) {
                // 终点是合并候选（传送带起点）：允许
              } else {
                continue; // 阻止
              }
            }
          }
        }

        // 物流桥或传送带交叉点：visited key 包含方向信息
        final neighborBeltDirForVisit = isNeighborBridge
            ? null
            : _getCrossingBeltDirectionAtCell(neighborPos);
        final useDirVisitKey =
            isNeighborBridge || neighborBeltDirForVisit != null;
        final visitKey =
            useDirVisitKey ? '${nx}_${ny}_$dirIdx' : nKey;

        if (visited.containsKey(visitKey)) continue;

        // 父节点的 visit key
        final parentCellPos =
            Offset(node.x.toDouble(), node.y.toDouble());
        final parentIsBridge =
            _findBeltBridgeAtCell(parentCellPos) != null;
        final parentBeltDir = parentIsBridge
            ? null
            : _getCrossingBeltDirectionAtCell(parentCellPos);
        final parentUseDirKey =
            node.incomingDir >= 0 &&
                (parentIsBridge || parentBeltDir != null);
        final parentVisitKey = parentUseDirKey
            ? '${node.x}_${node.y}_${node.incomingDir}'
            : nodeKey;

        visited[visitKey] =
            (parentVisitKey, Offset(node.x.toDouble(), node.y.toDouble()));
        queue.add(_BFSNode(nx, ny, dirIdx));
      }
    }

    return null;
  }

  List<Offset> _calculateStraightPath(Offset startGrid, Offset endGrid) {
    final sx = startGrid.dx.toInt();
    final sy = startGrid.dy.toInt();
    final ex = endGrid.dx.toInt();
    final ey = endGrid.dy.toInt();

    if (sx == ex && sy == ey) return [startGrid];

    final path = <Offset>[];

    if (sx != ex) {
      final dx = ex > sx ? 1 : -1;
      for (int x = sx; x != ex; x += dx) {
        path.add(Offset(x.toDouble(), sy.toDouble()));
      }
    }

    if (sy != ey) {
      final dy = ey > sy ? 1 : -1;
      for (int y = sy; y != ey; y += dy) {
        path.add(Offset(ex.toDouble(), y.toDouble()));
      }
    }

    path.add(Offset(ex.toDouble(), ey.toDouble()));
    return path;
  }
}

class _BFSNode {
  final int x, y;

  final int incomingDir;
  _BFSNode(this.x, this.y, this.incomingDir);
}
