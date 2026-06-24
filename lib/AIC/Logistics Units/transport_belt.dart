import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/building.dart';

part 'belt_cell_detection.dart';
part 'belt_path_validation.dart';
part 'belt_bridge_logic.dart';
part 'belt_direction_utils.dart';

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
    // 早退：连续点击同一锚点且路径未变化时取消创建
    if (!keepCreating &&
        _committedBeltId != null &&
        fullPath.length == _lastCommittedPathLength) {
      reset();
      return;
    }

    if (anchors.length < 2 || fullPath.length < 2) {
      reset();
      return;
    }

    // 1. 合并目标路径追加 + 物流桥自动创建
    final newSegmentLength = _appendMergeTargetPath();
    _autoCreateBridgesAtCrossings();

    // 2. 解析起点上下文（物流桥/设备输出端口/普通格子）
    final startCell = anchors.first;
    final startsAtBridge = _findBeltBridgeAtCell(startCell) != null;
    final startPortInfo = _isCellInBuilding(startCell)
        ? _findPortAtCell(startCell, preferredType: 'output')
        : null;
    final startIsDeviceOutputPort =
        startPortInfo != null && startPortInfo.type == 'output';
    final bridgeStartDirection = startsAtBridge && fullPath.length >= 2
        ? _directionBetween(fullPath[0], fullPath[1])
        : null;
    final bridgeSourceBelt = startsAtBridge
        ? _findBridgeContinuationSourceBelt(startCell, bridgeStartDirection)
        : null;
    if (bridgeSourceBelt != null) {
      fullPath = [
        ...bridgeSourceBelt.path,
        ...fullPath.skip(1),
      ];
    }

    // 3. 查找分叉源传送带（起点落在某条旧传送带中间时）
    final forkResult = _findForkSource(
        startCell, startsAtBridge, startIsDeviceOutputPort);
    final forkSourceBelt = forkResult.$1;
    final forkSourceIndex = forkResult.$2;

    // 4. 查找终点上下文（终点落在某条旧传送带中间时，可能合并下游）
    final endResult = _findEndCellContext(
        startsAtBridge, bridgeSourceBelt, forkSourceBelt);
    final endCellBelt = endResult.$1;
    final endCellIdx = endResult.$2;
    final endCellDownstreamMerged = endResult.$3;
    final endCellDownstreamOffset = endResult.$4;

    // 5. 继承新传送带首格入方向
    final newBeltIncomingDir = _inheritIncomingDirection();

    // 6. 查找源传送带（用户从其终点开始延长的情况）
    final sourceBelt = _findSourceBelt(
        startCell, bridgeSourceBelt, startIsDeviceOutputPort);

    // 7. 继承物品状态（committed/source/fork/merge/downstream）
    final itemState = _inheritItemState(
      newSegmentLength: newSegmentLength,
      forkSourceBelt: forkSourceBelt,
      forkSourceIndex: forkSourceIndex,
      endCellBelt: endCellBelt,
      endCellIdx: endCellIdx,
      endCellDownstreamMerged: endCellDownstreamMerged,
      endCellDownstreamOffset: endCellDownstreamOffset,
      sourceBelt: sourceBelt,
    );

    // 8. 创建新传送带
    final belt = _createNewBelt(newBeltIncomingDir, itemState);

    // 9. 截断旧传送带（分叉截断 + 终点截断）
    final changes = _truncateOldBelts(
      startCell: startCell,
      startsAtBridge: startsAtBridge,
      bridgeSourceBelt: bridgeSourceBelt,
      startIsDeviceOutputPort: startIsDeviceOutputPort,
      endCellBelt: endCellBelt,
      endCellIdx: endCellIdx,
      endCellDownstreamMerged: endCellDownstreamMerged,
    );
    for (final old in changes.$1) {
      project.conveyors.remove(old);
    }
    for (final newBelt in changes.$2) {
      project.conveyors.add(newBelt);
    }

    // 传送带不再在物流桥处拆分，保持完整路径
    // 物品直接穿过物流桥格子，不需要通过物流桥库存中转
    // 这样断头时整条传送带自然停止，延长/截断时物品状态完整继承
    project.conveyors.add(belt);
    project.offsetX; // no-op to ensure project reference works
    onProjectChanged(project);
    onRebuildCache();

    // 10. 连续创建模式收尾
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
    reset();
  }

  /// 合并目标路径追加到 fullPath，返回追加前的新段长度（用于偏移合并目标物品进度）
  int _appendMergeTargetPath() {
    final newSegmentLength = fullPath.length;
    if (_mergeTarget != null && _mergeTarget!.path.length > 1) {
      fullPath.addAll(_mergeTarget!.path.sublist(1));
    }
    return newSegmentLength;
  }

  /// 查找分叉源传送带：起点落在某条旧传送带中间时，返回 (传送带, 索引)
  (ConveyorBelt?, int) _findForkSource(
      Offset startCell, bool startsAtBridge, bool startIsDeviceOutputPort) {
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
    return (forkSourceBelt, forkSourceIndex);
  }

  /// 查找终点上下文：终点落在某条旧传送带中间时，返回 (传送带, 索引, 是否合并下游, 下游偏移)
  (ConveyorBelt?, int, bool, int) _findEndCellContext(
      bool startsAtBridge,
      ConveyorBelt? bridgeSourceBelt,
      ConveyorBelt? forkSourceBelt) {
    ConveyorBelt? endCellBelt;
    int endCellIdx = -1;
    {
      final endCell = fullPath.last;
      // 如果终点是建筑输入端口，多条传送带可以终点在同一个输入端口格子（如汇流器有3个输入端口在同一格子）
      // 此时不应截断其他也终点在此的传送带
      final isEndCellInputPort = _isCellDeviceInputPort(endCell) ||
          (_isCellInBuilding(endCell) && _buildingAtCellHasInputPort(endCell));
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
            // 终点是建筑输入端口且匹配的是旧传送带的终点（最后一格）时，不截断
            // 这允许多条传送带终点在同一个输入端口（如汇流器的3个输入端口）
            if (isEndCellInputPort && i == oldBelt.path.length - 1) {
              continue;
            }
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
    return (endCellBelt, endCellIdx, endCellDownstreamMerged, endCellDownstreamOffset);
  }

  /// 继承新传送带首格的入方向（查找 fullPath 首格来源的旧传送带）
  String? _inheritIncomingDirection() {
    if (fullPath.isEmpty) return null;
    final firstCell = fullPath.first;
    for (final oldBelt in project.conveyors) {
      if (oldBelt.path.isNotEmpty &&
          oldBelt.path.first.dx == firstCell.dx &&
          oldBelt.path.first.dy == firstCell.dy) {
        return oldBelt.incomingDirection;
      }
    }
    return null;
  }

  /// 查找源传送带（用户从其终点开始创建新传送带的旧传送带）
  /// 设备输出端口起点不继承输入传送带的物品状态（物品经过设备处理）
  ConveyorBelt? _findSourceBelt(
      Offset startCell, ConveyorBelt? bridgeSourceBelt, bool startIsDeviceOutputPort) {
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
    return sourceBelt;
  }

  /// 继承物品状态：按优先级 committed > source > fork，再叠加 merge 和 downstream
  _BeltItemState _inheritItemState({
    required int newSegmentLength,
    required ConveyorBelt? forkSourceBelt,
    required int forkSourceIndex,
    required ConveyorBelt? endCellBelt,
    required int endCellIdx,
    required bool endCellDownstreamMerged,
    required int endCellDownstreamOffset,
    required ConveyorBelt? sourceBelt,
  }) {
    final state = _BeltItemState();
    state.phaseOffset = currentPhase();
    final committedSourceBelt = _committedBeltId == null
        ? null
        : project.conveyors
            .where((belt) => belt.id == _committedBeltId)
            .firstOrNull;

    // 继承源传送带的物品状态（加长断头传送带时）
    if (committedSourceBelt != null &&
        _isPathPrefix(committedSourceBelt.path, fullPath)) {
      state.itemSegments.addAll(
        committedSourceBelt.shiftedItemSegments(0, clearFreezeProgress: false),
      );
      state.itemId = committedSourceBelt.itemId;
      state.itemFillCount = committedSourceBelt.itemFillCount;
      state.itemDrainCount = committedSourceBelt.itemDrainCount;
      state.phaseOffset = committedSourceBelt.phaseOffset;
      state.deadEndFreezeProgress = committedSourceBelt.deadEndFreezeProgress;
      if (committedSourceBelt.lastItemFillCount > 0) {
        state.lastItemId = committedSourceBelt.lastItemId;
        state.lastItemFillCount = committedSourceBelt.lastItemFillCount;
        state.lastItemDrainCount = committedSourceBelt.lastItemDrainCount;
        state.lastItemFreezeProgress = committedSourceBelt.lastItemFreezeProgress;
      }
    } else if (sourceBelt != null) {
      state.itemSegments.addAll(
        sourceBelt.shiftedItemSegments(0, clearFreezeProgress: false),
      );
      state.itemId = sourceBelt.itemId;
      state.itemFillCount = sourceBelt.itemFillCount;
      state.itemDrainCount = sourceBelt.itemDrainCount;
      state.phaseOffset = sourceBelt.phaseOffset;
      state.deadEndFreezeProgress = sourceBelt.deadEndFreezeProgress;
      // 源传送带的残留物品也继承
      if (sourceBelt.lastItemFillCount > 0) {
        state.lastItemId = sourceBelt.lastItemId;
        state.lastItemFillCount = sourceBelt.lastItemFillCount;
        state.lastItemDrainCount = sourceBelt.lastItemDrainCount;
        state.lastItemFreezeProgress = sourceBelt.lastItemFreezeProgress;
      }
    } else if (forkSourceBelt != null && forkSourceIndex >= 0) {
      state.itemSegments.addAll(
        forkSourceBelt.clippedItemSegments(0, forkSourceIndex + 1, clearFreezeProgress: true),
      );
      state.itemId = forkSourceBelt.itemId;
      state.itemFillCount =
          forkSourceBelt.itemFillCount.clamp(0, forkSourceIndex + 1).toInt();
      state.itemDrainCount =
          forkSourceBelt.itemDrainCount.clamp(0, forkSourceIndex + 1).toInt();
      state.phaseOffset = forkSourceBelt.phaseOffset;
      if (forkSourceBelt.lastItemFillCount > 0) {
        state.lastItemId = forkSourceBelt.lastItemId;
        state.lastItemFillCount = forkSourceBelt.lastItemFillCount
            .clamp(0, forkSourceIndex + 1)
            .toInt();
        state.lastItemDrainCount = forkSourceBelt.lastItemDrainCount
            .clamp(0, forkSourceIndex + 1)
            .toInt();
      }
    }

    // 合并时保留目标传送带的物品状态
    if (_mergeTarget != null) {
      final mergeBelt = _mergeTarget!;
      final offset = newSegmentLength - 1; // 合并目标首格已包含在 fullPath 中
      state.itemSegments.addAll(
        mergeBelt.shiftedItemSegments(offset, clearFreezeProgress: true),
      );

      if (mergeBelt.itemId.isNotEmpty) {
        if (mergeBelt.lastItemFillCount > 0) {
          // 保留已经形成的排队状态，避免当前物品覆盖更下游的残留物品。
          state.itemId = mergeBelt.itemId;
          state.itemFillCount = mergeBelt.itemFillCount + offset;
          state.itemDrainCount = mergeBelt.itemDrainCount + offset;

          state.lastItemId = mergeBelt.lastItemId;
          state.lastItemFillCount = mergeBelt.lastItemFillCount + offset;
          state.lastItemDrainCount = mergeBelt.lastItemDrainCount + offset;
        } else {
          // 合并目标有当前物品 -> 转为残留物品
          state.lastItemId = mergeBelt.itemId;
          state.lastItemFillCount = mergeBelt.itemFillCount + offset;
          state.lastItemDrainCount = mergeBelt.itemDrainCount + offset;
        }
      } else if (mergeBelt.lastItemFillCount > 0) {
        // 合并目标已有残留物品 -> 继承
        state.lastItemId = mergeBelt.lastItemId;
        state.lastItemFillCount = mergeBelt.lastItemFillCount + offset;
        state.lastItemDrainCount = mergeBelt.lastItemDrainCount + offset;
      }
    }

    // 终点截断下游合并时，继承下游部分的物品状态
    if (endCellDownstreamMerged && endCellBelt != null) {
      final eb = endCellBelt;
      final offset = endCellDownstreamOffset;
      state.itemSegments.addAll(
        eb.clippedItemSegments(endCellIdx + 1, eb.path.length, clearFreezeProgress: true)
            .map((seg) => seg.shifted(offset)),
      );
      if (eb.itemId.isNotEmpty) {
        final downstreamFill = eb.itemFillCount > endCellIdx + 1
            ? eb.itemFillCount - (endCellIdx + 1)
            : 0;
        final downstreamDrain = eb.itemDrainCount > endCellIdx + 1
            ? eb.itemDrainCount - (endCellIdx + 1)
            : 0;
        if (downstreamFill > 0) {
          if (state.itemId.isNotEmpty || eb.lastItemFillCount > 0) {
            // 新传送带已有物品，下游物品转为残留
            state.lastItemId = eb.itemId;
            state.lastItemFillCount = downstreamFill + offset;
            state.lastItemDrainCount = downstreamDrain + offset;
          } else {
            state.itemId = eb.itemId;
            state.itemFillCount = downstreamFill + offset;
            state.itemDrainCount = downstreamDrain + offset;
          }
        }
      }
    }

    return state;
  }

  /// 创建新的 ConveyorBelt
  ConveyorBelt _createNewBelt(String? newBeltIncomingDir, _BeltItemState state) {
    return ConveyorBelt(
      id: 'belt_${DateTime.now().millisecondsSinceEpoch}',
      path: List<Offset>.from(fullPath),
      itemId: state.itemId,
      lastItemId: state.lastItemId.isNotEmpty ? state.lastItemId : null,
      itemSegments: state.itemSegments,
      isBlocked: false,
      incomingDirection: newBeltIncomingDir,
      phaseOffset: state.phaseOffset,
      itemFillCount: state.itemFillCount,
      itemDrainCount: state.itemDrainCount,
      lastItemFillCount: state.lastItemFillCount,
      lastItemDrainCount: state.lastItemDrainCount,
      deadEndFreezeProgress: state.deadEndFreezeProgress,
      lastItemFreezeProgress: state.lastItemFreezeProgress,
    );
  }

  /// 截断旧传送带：分叉截断（起点落在旧传送带中间）+ 终点截断（终点落在旧传送带中间）
  /// 返回 (待移除列表, 待添加列表)
  (List<ConveyorBelt>, List<ConveyorBelt>) _truncateOldBelts({
    required Offset startCell,
    required bool startsAtBridge,
    required ConveyorBelt? bridgeSourceBelt,
    required bool startIsDeviceOutputPort,
    required ConveyorBelt? endCellBelt,
    required int endCellIdx,
    required bool endCellDownstreamMerged,
  }) {
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

    return (toRemove, toAdd);
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
}

/// _finish 期间传递继承的物品状态
///
/// 拆分 _finish 时用于在多个子方法之间传递物品继承状态，
/// 避免在协调方法中维护一长串局部变量。
class _BeltItemState {
  String itemId = '';
  String lastItemId = '';
  int itemFillCount = 0;
  int itemDrainCount = 0;
  int lastItemFillCount = 0;
  int lastItemDrainCount = 0;
  double? deadEndFreezeProgress;
  double? lastItemFreezeProgress;
  double phaseOffset = 0;
  final List<ConveyorItemSegment> itemSegments = [];
}
