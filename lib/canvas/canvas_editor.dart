import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/building.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../state/project_notifier.dart';
import '../constants/app_constants.dart';
import '../AIC/equipment.dart';
import 'conveyor_create_mode_hud.dart';
import 'canvas_painter.dart';
import 'canvas_utils.dart';
import 'simulation_engine.dart';
import '../widgets/conveyor_belt_dialog.dart';
import 'belt_simulation_logic.dart';

class CanvasEditor extends StatefulWidget {
  final Building? placingBuilding;
  final VoidCallback? onBuildingPlaced;
  final ValueChanged<PlacedBuilding?>? onBuildingSelected;
  final bool conveyorMode;
  final ValueChanged<String>? onErrorToast;

  const CanvasEditor({
    super.key,
    this.placingBuilding,
    this.onBuildingPlaced,
    this.onBuildingSelected,
    this.conveyorMode = false,
    this.onErrorToast,
  });

  @override
  State<CanvasEditor> createState() => CanvasEditorState();
}

class CanvasEditorState extends State<CanvasEditor>
    with TickerProviderStateMixin, BeltSimulationLogic {
  Offset? _lastFocalPoint;
  bool _isPanning = false;
  Offset? _mouseGridPos;

  late final TransportBeltController beltCtrl;

  int? _middleDragPointerId;
  Offset? _lastMiddlePos;
  bool _isMiddleDragging = false;

  late Ticker _ticker;
  late AnimationController _beltArrowController;

  double _displayScale = 1.0;
  double _displayOffsetX = 0;
  double _displayOffsetY = 0;
  double _targetScale = 1.0;
  double _targetOffsetX = 0;
  double _targetOffsetY = 0;
  bool _animating = false;
  double _gestureStartScale = 1.0;

  double _displayAngle = 0.0; // 当前显示角度（弧度）
  double _targetAngle = 0.0; // 目标角度（弧度）

  static const double cellSize = AppConstants.cellSize;
  static const double _minScale = UiConstants.minScale;
  static const double _maxScale = UiConstants.maxScale;

  // 功能1: 悬停高亮
  PlacedBuilding? _hoveredBuilding;

  // 功能2: 放置时旋转
  int _placingRotation = 0;

  // 功能3: 长按移动设备
  bool _isLongPressing = false;
  DateTime? _longPressStartTime;
  Offset? _longPressScreenPos;
  PlacedBuilding? _longPressTargetBuilding;
  double _longPressProgress = 0.0;
  static const Duration _longPressDuration = Duration(milliseconds: 800);

  // 移动模式
  PlacedBuilding? _movingBuilding;
  int _movingRotation = 0;
  double _movingOriginalGridX = 0;
  double _movingOriginalGridY = 0;

  // 物流桥移动时需要隐藏背景的传送带格子
  Offset? _bridgeMoveHiddenCell;

  // 移动模式下：端口传送带快照（用于取消移动时恢复）

  // 端口连接缓存：building id -> port key -> 是否连接
  Map<String, Map<String, bool>> portConnectionsCache = {};

  /// 端口连接缓存对应的 [ProjectNotifier.version]。
  /// 不匹配时在绘制前自动重建（TD-006：替代多处手动触发）。
  int _portConnectionsCacheVersion = -1;

  // 记录最近一次 onPointerDown 是否为左键
  bool _lastPointerWasPrimary = false;

  // 重绘触发计数器，确保图片缓存清理后，即使其他属性不变，也能正常强制触发 CustomPainter 完成重绘
  int _repaintTrigger = 0;

  void _forceRepaint() {
    EditorPainter.clearPictureCache();
    _repaintTrigger++;
    if (mounted) {
      setState(() {});
    }
  }

  ProjectNotifier get _pn => context.read<ProjectNotifier>();
  ProjectState get _project => _pn.project;
  DataLoader get _dataLoader => context.read<DataLoader>();

  /// 检测项目结构性变更（[ProjectNotifier.version] 变化），
  /// 必要时重建端口连接缓存。在 build() 绘制前调用，避免缓存过期。
  void _ensurePortConnectionsCacheFresh() {
    if (_portConnectionsCacheVersion == _pn.version) return;
    portConnectionsCache = {};
    for (final pb in _project.buildings) {
      portConnectionsCache[pb.id] = pb.conveyorPortConnections(
        _project.conveyors,
        cellSize: cellSize,
      );
    }
    _portConnectionsCacheVersion = _pn.version;
  }

  @override
  void initState() {
    super.initState();
    _displayScale = _project.scale;
    _displayOffsetX = _project.offsetX;
    _displayOffsetY = _project.offsetY;
    _targetScale = _project.scale;
    _targetOffsetX = _project.offsetX;
    _targetOffsetY = _project.offsetY;
    _ticker = createTicker(_onTick);
    beltCtrl = TransportBeltController(
      project: _project,
      onProjectChanged: (_) => _pn.notifyChanged(),
      // 端口连接缓存现按 ProjectNotifier.version 自动失效（TD-006），
      // 此回调保留为 no-op 以兼容控制器签名。
      onRebuildCache: () {},
      notifyListeners: () => setState(() {}),
      currentPhase: () => _beltArrowController.value,
      getBuilding: _dataLoader.getBuilding,
    );
    _beltArrowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // 监听 animation value 变化，检测跨零（完成一格传输）来触发传送带填充时钟滴答
    _beltArrowController.addListener(() {
      onBeltAnimationFrame(_beltArrowController.value);
      // 跨零检测：从 >0.5 跳到 <0.5（即从 ~1.0 重置到 ~0.0）
    });
    // 端口连接缓存在 build() 时按版本自动重建，无需在此手动初始化。
    TransportBeltRenderer.init();
    ConveyorCreateModeHudPainter.init(onReady: _forceRepaint);
    TransportBeltRenderer.onItemImageReady = _forceRepaint;
    RefiningUnitRenderer.init(onReady: () {
      _forceRepaint();
    });
    DepotAccessRenderer.init(onReady: () {
      _forceRepaint();
    });
    LogisticsUnitRenderer.init(onReady: () {
      _forceRepaint();
    });
  }

  @override
  void didUpdateWidget(covariant CanvasEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ProjectState 实例在 app 生命周期内稳定（导入是原地 clear+addAll），
    // 故不再需要实例变更/偏移回退分支。端口连接缓存在各变更点显式重建。
    if (!identical(oldWidget.placingBuilding, widget.placingBuilding) &&
        widget.placingBuilding != null &&
        oldWidget.placingBuilding == null) {
      _placingRotation = 0;
    }
    if (widget.conveyorMode != oldWidget.conveyorMode) {
      _forceRepaint();
      if (oldWidget.conveyorMode && !widget.conveyorMode) {
        beltCtrl.reset();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _beltArrowController.dispose();
    TransportBeltRenderer.onItemImageReady = null;
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // 长按进度计算
    if (_isLongPressing && _longPressStartTime != null) {
      _longPressProgress =
          (DateTime.now().difference(_longPressStartTime!).inMilliseconds /
                  _longPressDuration.inMilliseconds)
              .clamp(0.0, 1.0);
      if (_longPressProgress >= 1.0) {
        _enterMoveMode();
      }
    }

    const lerpFactor = 0.2;
    final newScale =
        _displayScale + (_targetScale - _displayScale) * lerpFactor;
    final newOffsetX =
        _displayOffsetX + (_targetOffsetX - _displayOffsetX) * lerpFactor;
    final newOffsetY =
        _displayOffsetY + (_targetOffsetY - _displayOffsetY) * lerpFactor;

    final scaleDone = (newScale - _targetScale).abs() < 0.001;
    final offsetXDone = (newOffsetX - _targetOffsetX).abs() < 0.5;
    final offsetYDone = (newOffsetY - _targetOffsetY).abs() < 0.5;

    _displayScale = scaleDone ? _targetScale : newScale;
    _displayOffsetX = offsetXDone ? _targetOffsetX : newOffsetX;
    _displayOffsetY = offsetYDone ? _targetOffsetY : newOffsetY;

    // 连续角度插值
    final angleDiff = _targetAngle - _displayAngle;
    final rotationDone = angleDiff.abs() < 0.005;
    _displayAngle =
        rotationDone ? _targetAngle : _displayAngle + angleDiff * lerpFactor;

    final hasRunningAnimation =
        !scaleDone || !offsetXDone || !offsetYDone || !rotationDone;
    if (!hasRunningAnimation && !_isLongPressing && _movingBuilding == null) {
      _animating = false;
      _ticker.stop();
      _project.offsetX = _targetOffsetX;
      _project.offsetY = _targetOffsetY;
      _project.scale = _targetScale;
    }

    setState(() {});
  }

  void _startAnimation() {
    if (!_animating) {
      _animating = true;
      _ticker.start();
    }
  }

  void rotateCanvas90() {
    _targetAngle += math.pi / 2;
    _startAnimation();
  }

  void rotatePlacement() {
    if (_movingBuilding != null) {
      setState(() {
        _movingRotation = (_movingRotation + 1) % 4;
      });
    } else if (widget.placingBuilding != null) {
      setState(() {
        _placingRotation = (_placingRotation + 1) % 4;
      });
    }
  }

  void startMoveFromDialog(PlacedBuilding pb) {
    _movingBuilding = pb;
    _movingRotation = pb.rotation;
    _movingOriginalGridX = pb.gridX;
    _movingOriginalGridY = pb.gridY;

    // 物流桥移动时，记录其网格位置以隐藏下方传送带背景
    if (pb.isBeltBridge) {
      _bridgeMoveHiddenCell = Offset(
        pb.gridX.toDouble(),
        pb.gridY.toDouble(),
      );
    }

    _pn.notifyChanged();
    setState(() {});
  }

  /// 从工程中删除设备，同时移除其端口上的传送带格子
  void deleteBuilding(PlacedBuilding pb) {
    _project.buildings.remove(pb);
    _removePortBeltCells(pb);
    _pn.notifyChanged();
    setState(() {});
  }

  Offset _screenToWorld(Offset screenPos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cosA = math.cos(_displayAngle);
    final sinA = math.sin(_displayAngle);

    var pos = screenPos;
    // 逆变换：按正向变换的逆序执行
    // 正向: scale → translate(-offset) → translate(-center) → rotate → translate(center)
    // 逆向: translate(-center) → inverse-rotate → translate(center) → translate(+offset) → unscale

    // 1. 撤销 translate(center)
    pos = Offset(pos.dx - center.dx, pos.dy - center.dy);
    // 2. 撤销 rotate(θ) — 逆旋转
    pos = _inverseRotate(pos, cosA, sinA);
    // 3. 撤销 translate(-center)
    pos = Offset(pos.dx + center.dx, pos.dy + center.dy);
    // 4. 撤销 translate(-offset)
    pos = Offset(pos.dx + _displayOffsetX, pos.dy + _displayOffsetY);
    // 5. 撤销 scale
    pos = Offset(pos.dx / _displayScale, pos.dy / _displayScale);
    return pos;
  }

  Offset _screenToGrid(Offset screenPos, Size size) {
    final world = _screenToWorld(screenPos, size);
    return Offset(
      (world.dx / cellSize).floorToDouble(),
      (world.dy / cellSize).floorToDouble(),
    );
  }

  PlacedBuilding? _getBuildingAt(Offset gridPos) {
    for (final pb in _project.buildings.reversed) {
      final bounds = pb.getBounds(cellSize);
      if (bounds.contains(gridPos * cellSize)) {
        return pb;
      }
    }
    return null;
  }

  void _handleScroll(PointerScrollEvent event, Offset localPos) {
    if (_isMiddleDragging) return;

    final oldScale = _targetScale;
    final newScale = (_targetScale * (1 - event.scrollDelta.dy / 200))
        .clamp(_minScale, _maxScale);

    if ((newScale - oldScale).abs() < 0.0001) return;

    // 将屏幕坐标转换到旋转前的空间（offset所在的空间）
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final center = Offset(size.width / 2, size.height / 2);
    final cosA = math.cos(_displayAngle);
    final sinA = math.sin(_displayAngle);
    var preRotationPos =
        Offset(localPos.dx - center.dx, localPos.dy - center.dy);
    preRotationPos = _inverseRotate(preRotationPos, cosA, sinA);
    preRotationPos =
        Offset(preRotationPos.dx + center.dx, preRotationPos.dy + center.dy);

    _targetOffsetX =
        (preRotationPos.dx + _targetOffsetX) * newScale / oldScale -
            preRotationPos.dx;
    _targetOffsetY =
        (preRotationPos.dy + _targetOffsetY) * newScale / oldScale -
            preRotationPos.dy;
    _targetScale = newScale;

    _startAnimation();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_isMiddleDragging) return;
    _lastFocalPoint = details.localFocalPoint;
    _isPanning = true;
    _gestureStartScale = _targetScale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size size) {
    if (_isMiddleDragging) return;

    final newScale =
        (_gestureStartScale * details.scale).clamp(_minScale, _maxScale);

    if (details.pointerCount >= 2 || _isPanning) {
      final focalPoint = details.localFocalPoint;
      if (_lastFocalPoint != null) {
        final delta = focalPoint - _lastFocalPoint!;
        final rotatedDelta = _screenDeltaToWorldDelta(delta);
        _targetOffsetX -= rotatedDelta.dx;
        _targetOffsetY -= rotatedDelta.dy;
        _displayOffsetX = _targetOffsetX;
        _displayOffsetY = _targetOffsetY;
      }
      _lastFocalPoint = focalPoint;
    }

    if ((newScale - _targetScale).abs() > 0.001) {
      _targetScale = newScale;
      _startAnimation();
    }

    setState(() {});
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_isMiddleDragging) return;
    _lastFocalPoint = null;
    _isPanning = false;
  }

  /// 对坐标点进行逆旋转变换（绕原点旋转 -θ）
  Offset _inverseRotate(Offset pos, double cosA, double sinA) {
    return Offset(
      pos.dx * cosA + pos.dy * sinA,
      -pos.dx * sinA + pos.dy * cosA,
    );
  }

  /// 将屏幕空间的拖拽delta转换到offset坐标系（反向旋转）
  Offset _screenDeltaToWorldDelta(Offset screenDelta) {
    final cosA = math.cos(_displayAngle);
    final sinA = math.sin(_displayAngle);
    return _inverseRotate(screenDelta, cosA, sinA);
  }

  void _handleTap(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final building = widget.placingBuilding;

    if (building != null) {
      _placeBuilding(building, gridPos, rotation: _placingRotation);
      return;
    }

    if (widget.conveyorMode) {
      final hadNoAnchors = beltCtrl.anchors.isEmpty;
      final wasPathInvalid = beltCtrl.pathInvalid;
      if (beltCtrl.handleTap(gridPos)) return;
      // 创建失败时触发 HUD 错误动画和文字提示
      if (hadNoAnchors) {
        // 首次点击空白网格（未从设备输出端开始）
        ConveyorCreateModeHudPainter.triggerError();
        widget.onErrorToast?.call('请从设备输出端口进行创建');
      } else if (wasPathInvalid) {
        // 预览为红色时点击创建
        ConveyorCreateModeHudPainter.triggerError();
        widget.onErrorToast?.call('设备重叠');
      }
    }
  }

  ConveyorBelt? _findBeltAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in _project.conveyors) {
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return belt;
      }
    }
    return null;
  }

  /// 检查格子是否位于设备的输入/输出端口上
  bool _isCellOnBuildingPort(Offset gridPos) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();
    for (final pb in _project.buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
        final portGrid =
            port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portGrid.dx.round() == gx && portGrid.dy.round() == gy) {
          return true;
        }
      }
    }
    return false;
  }

  List<ConveyorBelt> _findConnectedBelts(ConveyorBelt startBelt) {
    final connected = <ConveyorBelt>[startBelt];
    final visited = <String>{startBelt.id};

    void traverseFrom(ConveyorBelt belt) {
      if (belt.path.isEmpty) return;

      final firstCell = belt.path.first;
      final lastCell = belt.path.last;

      for (final other in _project.conveyors) {
        if (visited.contains(other.id)) continue;
        if (other.path.isEmpty) continue;

        final otherFirst = other.path.first;
        final otherLast = other.path.last;

        // 检查 firstCell 与 otherLast 是否在同一格
        final startToEnd = firstCell.dx == otherLast.dx &&
            firstCell.dy == otherLast.dy;
        // 检查 lastCell 与 otherFirst 是否在同一格
        final endToStart = lastCell.dx == otherFirst.dx &&
            lastCell.dy == otherFirst.dy;

        if (startToEnd || endToStart) {
          // 确定共享的格子坐标
          final sharedCell = startToEnd ? firstCell : lastCell;
          // 如果共享格子上有建筑（如分流器），则不跨越建筑连接产线
          if (_getBuildingAt(sharedCell) != null) continue;

          visited.add(other.id);
          connected.add(other);
          traverseFrom(other);
        }
      }
    }

    traverseFrom(startBelt);
    return connected;
  }

  void _showConveyorBeltDialog(ConveyorBelt belt, Offset clickedCell) {
    final allLineBelts = _findConnectedBelts(belt);
    final targetBeltId = belt.id;
    final lineIds = allLineBelts.map((b) => b.id).toSet();

    ConveyorBeltDialog.show(
      context,
      belt: belt,
      allBelts: allLineBelts,
      dataLoader: _dataLoader,
      onStoreSingle: () => _removeBeltCell(targetBeltId, clickedCell),
      onStoreLine: () => _storeBeltLineByIds(lineIds),
      onCollectAll: () => _collectAllFromLine(allLineBelts),
      onCollectItem: (itemId) => _collectItemFromLine(allLineBelts, itemId),
    );
  }

  /// 从传送带路径中移除点击的那一格，必要时拆分为两条传送带
  void _removeBeltCell(String beltId, Offset cell) {
    final belt = _project.conveyors.where((b) => b.id == beltId).firstOrNull;
    if (belt == null) return;

    final gx = cell.dx.toInt();
    final gy = cell.dy.toInt();

    // 找到点击格在路径中的索引
    int cellIndex = -1;
    for (int i = 0; i < belt.path.length; i++) {
      if (belt.path[i].dx.toInt() == gx && belt.path[i].dy.toInt() == gy) {
        cellIndex = i;
        break;
      }
    }

    if (cellIndex < 0) return;

    setState(() {
      // 移除原传送带
      _project.conveyors.removeWhere((b) => b.id == beltId);

      // 移除格之前的路径段 (0 ~ cellIndex-1)
      if (cellIndex > 0) {
        final beforePath = belt.path.sublist(0, cellIndex);
        // 计算末格的出方向（从末格指向被删格），以保留转角形状
        String? beforeForcedDir;
        final fdx = belt.path[cellIndex].dx - belt.path[cellIndex - 1].dx;
        final fdy = belt.path[cellIndex].dy - belt.path[cellIndex - 1].dy;
        if (fdx > 0) {
          beforeForcedDir = 'right';
        } else if (fdx < 0) {
          beforeForcedDir = 'left';
        } else if (fdy > 0) {
          beforeForcedDir = 'down';
        } else if (fdy < 0) {
          beforeForcedDir = 'up';
        }
        _project.conveyors.add(ConveyorBelt(
          id: 'belt_${DateTime.now().millisecondsSinceEpoch}_a',
          path: beforePath,
          itemId: belt.itemId,
          lastItemId: belt.lastItemId,
          itemSegments: belt.clippedItemSegments(0, cellIndex),
          isBlocked: belt.isBlocked,
          incomingDirection: belt.incomingDirection,
          forcedDirection: beforeForcedDir,
          phaseOffset: belt.phaseOffset,
          itemFillCount: math.min(belt.itemFillCount, beforePath.length),
          itemDrainCount: math.min(belt.itemDrainCount, beforePath.length),
          lastItemFillCount:
              math.min(belt.lastItemFillCount, beforePath.length),
          lastItemDrainCount:
              math.min(belt.lastItemDrainCount, beforePath.length),
          deadEndFreezeProgress: belt.deadEndFreezeProgress,
          lastItemFreezeProgress: belt.lastItemFreezeProgress,
        ));
      }

      // 移除格之后的路径段 (cellIndex+1 ~ end)
      if (cellIndex < belt.path.length - 1) {
        final afterPath = belt.path.sublist(cellIndex + 1);
        // 计算下游首格的入方向
        String? incomingDir;
        if (cellIndex + 1 < belt.path.length) {
          final dx = belt.path[cellIndex + 1].dx - belt.path[cellIndex].dx;
          final dy = belt.path[cellIndex + 1].dy - belt.path[cellIndex].dy;
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
        String? forcedDir;
        if (afterPath.length == 1) forcedDir = incomingDir;
        _project.conveyors.add(ConveyorBelt(
          id: 'belt_${DateTime.now().millisecondsSinceEpoch}_b',
          path: afterPath,
          itemId: belt.itemId,
          lastItemId: belt.lastItemId,
          itemSegments:
              belt.clippedItemSegments(cellIndex + 1, belt.path.length),
          isBlocked: belt.isBlocked,
          forcedDirection: forcedDir,
          incomingDirection: incomingDir,
          phaseOffset: belt.phaseOffset,
          itemFillCount: math.max(0, belt.itemFillCount - (cellIndex + 1)),
          itemDrainCount: math.max(0, belt.itemDrainCount - (cellIndex + 1)),
          lastItemFillCount: belt.lastItemFillCount > 0
              ? math.max(0, belt.lastItemFillCount - (cellIndex + 1))
              : 0,
          lastItemDrainCount: belt.lastItemFillCount > 0
              ? math.max(0, belt.lastItemDrainCount - (cellIndex + 1))
              : 0,
          deadEndFreezeProgress: belt.deadEndFreezeProgress,
          lastItemFreezeProgress: belt.lastItemFreezeProgress,
        ));
      }

      _pn.notifyChanged();
    });
  }

  void _storeBeltLineByIds(Set<String> beltIds) {
    setState(() {
      _project.conveyors.removeWhere((b) => beltIds.contains(b.id));
      _pn.notifyChanged();
    });
  }

  void _collectAllFromLine(List<ConveyorBelt> belts) {
    for (final belt in belts) {
      if (belt.itemId.isNotEmpty || belt.itemSegments.isNotEmpty) {
        setState(() {
          belt.itemSegments.clear();
          belt.syncLegacyFromSegments();
        });
      }
    }
    _pn.notifyChanged();
  }

  /// 收取产线上指定 itemId 的所有物品段
  void _collectItemFromLine(List<ConveyorBelt> belts, String itemId) {
    for (final belt in belts) {
      final hasTarget =
          belt.itemSegments.any((s) => s.itemId == itemId && s.hasItems);
      if (hasTarget) {
        setState(() {
          belt.itemSegments.removeWhere((s) => s.itemId == itemId);
          belt.syncLegacyFromSegments();
        });
      }
    }
    _pn.notifyChanged();
  }

  /// 检查建筑在指定位置是否会发生碰撞（建筑重叠或传送带重叠）
  bool _checkBuildingCollision(
      Building building, double cx, double cy, int rotation) {
    final tempBuilding = PlacedBuilding(
      id: 'temp',
      building: building,
      gridX: cx,
      gridY: cy,
      rotation: rotation,
    );
    final bounds = tempBuilding.getBounds(cellSize);
    final buildingOverlaps = _project.buildings.any(
      (b) => b != _movingBuilding && b.overlaps(bounds, cellSize),
    );
    if (buildingOverlaps) return true;

    // 检测传送带碰撞（使用旋转后的有效占地）
    int effW, effH;
    double effX, effY;
    if (rotation % 2 == 1) {
      effW = building.gridHeight;
      effH = building.gridWidth;
    } else {
      effW = building.gridWidth;
      effH = building.gridHeight;
    }
    effX = cx + (building.gridWidth - effW) / 2.0;
    effY = cy + (building.gridHeight - effH) / 2.0;
    final cells = <String>{};
    for (int dx = 0; dx < effW; dx++) {
      for (int dy = 0; dy < effH; dy++) {
        cells.add('${(effX + dx).round()}_${(effY + dy).round()}');
      }
    }
    for (final belt in _project.conveyors) {
      for (int i = 0; i < belt.path.length; i++) {
        if (!cells.contains(gridCellKey(belt.path[i]))) continue;
        if (!canBuildingOverlapBeltCell(building, belt, i)) {
          return true;
        }
      }
    }
    return false;
  }

  void _placeBuilding(Building building, Offset gridPos, {int rotation = 0}) {
    final cx = gridPos.dx - (building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (building.gridHeight ~/ 2).toDouble();

    if (_checkBuildingCollision(building, cx, cy, rotation)) {
      widget.onErrorToast?.call('设备重叠');
      return;
    }

    final newBuilding = PlacedBuilding(
      id: 'building_${DateTime.now().millisecondsSinceEpoch}',
      building: building,
      gridX: cx,
      gridY: cy,
      rotation: rotation,
    );

    _project.buildings.add(newBuilding);
    _project.offsetX = _targetOffsetX;
    _project.offsetY = _targetOffsetY;
    _project.scale = _targetScale;
    _pn.notifyChanged();
    widget.onBuildingPlaced?.call();
  }

  // ─── 长按与移动模式 ────────────────────────────────────────────

  void _startLongPress(Offset screenPos, PlacedBuilding building) {
    _isLongPressing = true;
    _longPressStartTime = DateTime.now();
    _longPressScreenPos = screenPos;
    _longPressTargetBuilding = building;
    _longPressProgress = 0.0;
    _ticker.start();
  }

  void _cancelLongPress() {
    _isLongPressing = false;
    _longPressStartTime = null;
    _longPressScreenPos = null;
    _longPressTargetBuilding = null;
    _longPressProgress = 0.0;
  }

  void _enterMoveMode() {
    if (_longPressTargetBuilding == null) return;
    _isLongPressing = false;
    _longPressProgress = 0.0;

    _movingBuilding = _longPressTargetBuilding;
    _movingRotation = _longPressTargetBuilding!.rotation;
    _movingOriginalGridX = _longPressTargetBuilding!.gridX;
    _movingOriginalGridY = _longPressTargetBuilding!.gridY;

    // 物流桥移动时，记录其网格位置以隐藏下方传送带背景
    if (_movingBuilding!.isBeltBridge) {
      _bridgeMoveHiddenCell = Offset(
        _movingBuilding!.gridX.toDouble(),
        _movingBuilding!.gridY.toDouble(),
      );
    }

    _longPressTargetBuilding = null;
    _longPressStartTime = null;
    _longPressScreenPos = null;

    _pn.notifyChanged();
  }

  /// 移除设备输入/输出端口上的传送带格子
  void _removePortBeltCells(PlacedBuilding pb) {
    final portCells = <Offset>[];
    // 记录哪些端口格子是输出端口（物品来源）
    final outputPortCells = <String>{};
    final rot = pb.rotation;
    final gw = pb.building.gridWidth;
    final gh = pb.building.gridHeight;
    for (final port in pb.outputPorts) {
      final cell = port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
      portCells.add(cell);
      outputPortCells.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
    }
    for (final port in pb.inputPorts) {
      portCells
          .add(port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot));
    }

    final toRemove = <ConveyorBelt>[];
    final toAdd = <ConveyorBelt>[];

    for (final belt in _project.conveyors) {
      // 找到该传送带路径中所有位于端口上的格子索引
      final portIndices = <int>[];
      for (int i = 0; i < belt.path.length; i++) {
        for (final portCell in portCells) {
          if (belt.path[i].dx.toInt() == portCell.dx.toInt() &&
              belt.path[i].dy.toInt() == portCell.dy.toInt()) {
            portIndices.add(i);
            break;
          }
        }
      }

      if (portIndices.isEmpty) continue;

      toRemove.add(belt);

      // 将路径按端口格子拆分为多段
      int start = 0;
      for (final portIdx in portIndices) {
        if (portIdx > start) {
          final segment = belt.path.sublist(start, portIdx);
          String? incomingDir = belt.incomingDirection;
          // 非首段：从前一个格子到本段首格推断入方向
          if (start > 0) {
            final dx = belt.path[start].dx - belt.path[start - 1].dx;
            final dy = belt.path[start].dy - belt.path[start - 1].dy;
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
          // 计算末格的出方向（从末格指向被移除的端口格），以保留转角形状
          String? forcedDir;
          final fdx = belt.path[portIdx].dx - belt.path[portIdx - 1].dx;
          final fdy = belt.path[portIdx].dy - belt.path[portIdx - 1].dy;
          if (fdx > 0) {
            forcedDir = 'right';
          } else if (fdx < 0) {
            forcedDir = 'left';
          } else if (fdy > 0) {
            forcedDir = 'down';
          } else if (fdy < 0) {
            forcedDir = 'up';
          }

          // 判断该段是否因输出端口断开而失去源
          // 如果该段前面紧挨着一个输出端口格子（被移除的），则该段失去了源
          final lostSource = start > 0 &&
              outputPortCells.contains(
                  '${belt.path[start - 1].dx.toInt()}_${belt.path[start - 1].dy.toInt()}');

          // 计算该段内的 itemFillCount（相对于段起始位置）
          final segFillCount = start == 0
              ? belt.itemFillCount
              : math.max(0, belt.itemFillCount - start);
          final segDrainCount = start == 0
              ? belt.itemDrainCount
              : math.max(0, belt.itemDrainCount - start);
          final segLastFillCount = start == 0
              ? belt.lastItemFillCount
              : math.max(0, belt.lastItemFillCount - start);
          final segLastDrainCount = start == 0
              ? belt.lastItemFillCount > 0
                  ? math.max(0, belt.lastItemDrainCount - start)
                  : 0
              : 0;
          final segDeadEndFreezeProgress = (segFillCount >= segment.length)
              ? belt.deadEndFreezeProgress
              : null;
          final segLastItemFreezeProgress = (segLastFillCount >= segment.length)
              ? belt.lastItemFreezeProgress
              : null;
          final segmentItemSegments = belt.clippedItemSegments(start, portIdx);

          if (lostSource && belt.itemId.isNotEmpty) {
            // 源断开：将当前物品状态转移到残留物品，清空当前物品
            toAdd.add(ConveyorBelt(
              id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
              path: segment,
              itemId: belt.itemId,
              lastItemId: belt.lastItemId,
              itemSegments: segmentItemSegments,
              itemFillCount: segFillCount,
              itemDrainCount: segDrainCount,
              isBlocked: belt.isBlocked,
              forcedDirection: forcedDir,
              incomingDirection: incomingDir,
              phaseOffset: belt.phaseOffset,
              lastItemFillCount: segLastFillCount,
              lastItemDrainCount: segLastDrainCount,
              deadEndFreezeProgress: segDeadEndFreezeProgress,
              lastItemFreezeProgress: segLastItemFreezeProgress,
            ));
          } else {
            toAdd.add(ConveyorBelt(
              id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
              path: segment,
              itemId: belt.itemId,
              lastItemId: belt.lastItemId,
              itemSegments: segmentItemSegments,
              itemFillCount: segFillCount,
              itemDrainCount: segDrainCount,
              isBlocked: belt.isBlocked,
              forcedDirection: forcedDir,
              incomingDirection: incomingDir,
              phaseOffset: belt.phaseOffset,
              lastItemFillCount: segLastFillCount,
              lastItemDrainCount: segLastDrainCount,
              deadEndFreezeProgress: segDeadEndFreezeProgress,
              lastItemFreezeProgress: segLastItemFreezeProgress,
            ));
          }
        }
        start = portIdx + 1;
      }
      // 最后一段
      if (start < belt.path.length) {
        final segment = belt.path.sublist(start);
        String? incomingDir;
        if (start > 0) {
          final dx = belt.path[start].dx - belt.path[start - 1].dx;
          final dy = belt.path[start].dy - belt.path[start - 1].dy;
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
        // 最后一段继承原传送带的 forcedDirection
        String? forcedDir = belt.forcedDirection;
        if (segment.length == 1 && forcedDir == null) forcedDir = incomingDir;

        // 判断最后一段是否因输出端口断开而失去源
        final lostSource = start > 0 &&
            outputPortCells.contains(
                '${belt.path[start - 1].dx.toInt()}_${belt.path[start - 1].dy.toInt()}');

        final segFillCount = math.max(0, belt.itemFillCount - start);
        final segDrainCount = math.max(0, belt.itemDrainCount - start);
        final segLastFillCount = belt.lastItemFillCount > 0
            ? math.max(0, belt.lastItemFillCount - start)
            : 0;
        final segLastDrainCount = belt.lastItemFillCount > 0
            ? math.max(0, belt.lastItemDrainCount - start)
            : 0;
        final segDeadEndFreezeProgress = (segFillCount >= segment.length)
            ? belt.deadEndFreezeProgress
            : null;
        final segLastItemFreezeProgress = (segLastFillCount >= segment.length)
            ? belt.lastItemFreezeProgress
            : null;
        final segmentItemSegments =
            belt.clippedItemSegments(start, belt.path.length);

        if (lostSource && belt.itemId.isNotEmpty) {
          // 源断开：将当前物品状态转移到残留物品，清空当前物品
          toAdd.add(ConveyorBelt(
            id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
            path: segment,
            itemId: belt.itemId,
            lastItemId: belt.lastItemId,
            itemSegments: segmentItemSegments,
            itemFillCount: segFillCount,
            itemDrainCount: segDrainCount,
            isBlocked: belt.isBlocked,
            forcedDirection: forcedDir,
            incomingDirection: incomingDir,
            phaseOffset: belt.phaseOffset,
            lastItemFillCount: segLastFillCount,
            lastItemDrainCount: segLastDrainCount,
            deadEndFreezeProgress: segDeadEndFreezeProgress,
            lastItemFreezeProgress: segLastItemFreezeProgress,
          ));
        } else {
          toAdd.add(ConveyorBelt(
            id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
            path: segment,
            itemId: belt.itemId,
            lastItemId: belt.lastItemId,
            itemSegments: segmentItemSegments,
            itemFillCount: segFillCount,
            itemDrainCount: segDrainCount,
            isBlocked: belt.isBlocked,
            forcedDirection: forcedDir,
            incomingDirection: incomingDir,
            phaseOffset: belt.phaseOffset,
            lastItemFillCount: segLastFillCount,
            lastItemDrainCount: segLastDrainCount,
            deadEndFreezeProgress: segDeadEndFreezeProgress,
            lastItemFreezeProgress: segLastItemFreezeProgress,
          ));
        }
      }
    }

    for (final old in toRemove) {
      _project.conveyors.remove(old);
    }
    for (final newBelt in toAdd) {
      _project.conveyors.add(newBelt);
    }
  }

  /// 是否正在创建传送带（已有锚点）
  bool get isCreatingConveyorBelt => beltCtrl.anchors.isNotEmpty;

  /// 完成传送带创建（ESC 按下且有锚点时调用）
  void finishConveyorBeltCreation() {
    beltCtrl.handleKeyEscape();
  }

  bool cancelMoveMode() {
    if (_movingBuilding == null) return false;
    _movingBuilding = null;
    _movingRotation = 0;
    _bridgeMoveHiddenCell = null;

    setState(() {});
    return true;
  }

  void _placeMovingBuilding(Offset gridPos) {
    if (_movingBuilding == null) return;
    final cx =
        gridPos.dx - (_movingBuilding!.building.gridWidth ~/ 2).toDouble();
    final cy =
        gridPos.dy - (_movingBuilding!.building.gridHeight ~/ 2).toDouble();

    // It was never removed from _project.buildings, but we temporarily updated it for collision checking.
    // Let's create a temporary clone for collision checking.
    final tempBuilding = PlacedBuilding(
      id: _movingBuilding!.id,
      building: _movingBuilding!.building,
      gridX: cx,
      gridY: cy,
      rotation: _movingRotation,
    );

    if (_checkBuildingCollision(
        tempBuilding.building, cx, cy, _movingRotation)) {
      return;
    }

    // Since we are confirming the move, NOW we execute port removal from the OLD location before updating coordinates
    _removePortBeltCells(_movingBuilding!);

    _movingBuilding!.gridX = cx;
    _movingBuilding!.gridY = cy;
    _movingBuilding!.rotation = _movingRotation;

    _movingBuilding = null;
    _movingRotation = 0;
    _bridgeMoveHiddenCell = null;

    _project.offsetX = _targetOffsetX;
    _project.offsetY = _targetOffsetY;
    _project.scale = _targetScale;
    _pn.notifyChanged();
  }

  void _handleSingleClick(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final pb = _getBuildingAt(gridPos);
    widget.onBuildingSelected?.call(pb);
  }

  void _handleRightClick(Offset screenPos, Size size) {
    beltCtrl.handleRightClick();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_movingBuilding != null) {
          cancelMoveMode();
          return KeyEventResult.handled;
        }
        if (widget.conveyorMode && beltCtrl.handleKeyEscape()) {
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        if (_movingBuilding != null) {
          setState(() {
            _movingRotation = (_movingRotation + 1) % 4;
          });
          return KeyEventResult.handled;
        }
        if (widget.placingBuilding != null) {
          setState(() {
            _placingRotation = (_placingRotation + 1) % 4;
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleHover(PointerHoverEvent event) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(event.position);
    final gridPos = _screenToGrid(localPos, renderBox.size);
    // 只在网格位置变化时才触发重绘
    if (_mouseGridPos == gridPos) return;
    setState(() {
      _mouseGridPos = gridPos;
      // 检测悬停的建筑
      _hoveredBuilding =
          widget.placingBuilding == null && _movingBuilding == null
              ? _getBuildingAt(gridPos)
              : null;
      if (widget.conveyorMode) {
        beltCtrl.handleHover(gridPos);
      } else {
        beltCtrl.reset();
      }
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPointerWasPrimary = event.buttons & kPrimaryMouseButton != 0;
    // 中键拖拽
    if (event.buttons & kMiddleMouseButton != 0 &&
        _middleDragPointerId == null) {
      _middleDragPointerId = event.pointer;
      _lastMiddlePos = event.localPosition;
      _isMiddleDragging = true;
      return;
    }
    // 左键
    if (event.buttons & kPrimaryMouseButton != 0) {
      final renderBox = context.findRenderObject() as RenderBox;
      final localPos = event.localPosition;
      final gridPos = _screenToGrid(localPos, renderBox.size);

      // 移动模式：点击放置
      if (_movingBuilding != null) {
        _placeMovingBuilding(gridPos);
        setState(() {});
        return;
      }

      // 放置模式：立即放置
      if (widget.placingBuilding != null) {
        _handleTap(localPos, renderBox.size);
        setState(() {});
        return;
      }

      // 传送带模式：立即处理
      if (widget.conveyorMode) {
        _handleTap(localPos, renderBox.size);
        setState(() {});
        return;
      }

      // 普通模式：检测是否点击了建筑（用于长按）
      final pb = _getBuildingAt(gridPos);
      if (pb != null) {
        _startLongPress(localPos, pb);
      }
      setState(() {});
    }
    // 右键：移动模式下取消
    if (event.buttons & kSecondaryMouseButton != 0 &&
        _movingBuilding != null) {
      cancelMoveMode();
      setState(() {});
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _middleDragPointerId &&
        _lastMiddlePos != null) {
      final delta = event.localPosition - _lastMiddlePos!;
      final rotatedDelta = _screenDeltaToWorldDelta(delta);
      _targetOffsetX -= rotatedDelta.dx;
      _targetOffsetY -= rotatedDelta.dy;
      _displayOffsetX = _targetOffsetX;
      _displayOffsetY = _targetOffsetY;
      _lastMiddlePos = event.localPosition;
      setState(() {});
    }
    // 长按时移动过远则取消
    if (_isLongPressing && _longPressScreenPos != null) {
      const cancelDist = 30.0;
      if ((event.localPosition - _longPressScreenPos!).distance >
          cancelDist) {
        _cancelLongPress();
        setState(() {});
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == _middleDragPointerId) {
      _middleDragPointerId = null;
      _lastMiddlePos = null;
      _isMiddleDragging = false;
      return;
    }

    // 仅左键释放时处理传送带弹窗和建筑选中
    final isPrimaryButton = _lastPointerWasPrimary;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = event.localPosition;
    final gridPos = _screenToGrid(localPos, renderBox.size);

    if (_isLongPressing && _longPressProgress < 1.0) {
      _cancelLongPress();
      if (isPrimaryButton &&
          !widget.conveyorMode &&
          widget.placingBuilding == null) {
        final clickedBelt = _findBeltAtCell(gridPos);
        if (clickedBelt != null && !_isCellOnBuildingPort(gridPos)) {
          _showConveyorBeltDialog(clickedBelt, gridPos);
          setState(() {});
          return;
        }
      }
      _handleSingleClick(localPos, renderBox.size);
      setState(() {});
    } else if (isPrimaryButton &&
        !_isLongPressing &&
        !widget.conveyorMode &&
        widget.placingBuilding == null &&
        _movingBuilding == null) {
      final clickedBelt = _findBeltAtCell(gridPos);
      if (clickedBelt != null && !_isCellOnBuildingPort(gridPos)) {
        _showConveyorBeltDialog(clickedBelt, gridPos);
        setState(() {});
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _middleDragPointerId) {
      _middleDragPointerId = null;
      _lastMiddlePos = null;
      _isMiddleDragging = false;
    }
    if (_isLongPressing) {
      _cancelLongPress();
      setState(() {});
    }
  }

  void _handleScaleUpdateWithSize(ScaleUpdateDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    _handleScaleUpdate(details, renderBox.size);
  }

  void _handleSecondaryTapUp(TapUpDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    _handleRightClick(details.localPosition, renderBox.size);
  }

  @override
  Widget build(BuildContext context) {
    // 订阅两个状态源，驱动 CustomPaint 重绘：
    // 1. 仿真引擎 tick（生产进度 / 传送带 flowProgress / isBlocked）
    // 2. 项目结构性变更（放置 / 删除 / 传送带 / 导入 / 库存）
    context.watch<SimulationEngine>();
    context.watch<ProjectNotifier>();
    // 端口连接缓存按版本自动失效（TD-006）：结构性变更触发 notifyChanged
    // → version 自增 → 此处在绘制前重建过期缓存。
    _ensurePortConnectionsCacheFresh();
    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: MouseRegion(
        onHover: _handleHover,
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final renderBox = context.findRenderObject() as RenderBox;
              final localPos = renderBox.globalToLocal(event.position);
              _handleScroll(event, localPos);
            }
          },
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: GestureDetector(
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdateWithSize,
            onScaleEnd: _handleScaleEnd,
            onSecondaryTapUp: _handleSecondaryTapUp,
            child: CustomPaint(
              painter: EditorPainter(
                repaintTrigger: _repaintTrigger,
                project: _project,
                dataLoader: _dataLoader,
                cellSize: cellSize,
                placingBuilding: widget.placingBuilding,
                placingRotation: _placingRotation,
                mouseGridPos: _mouseGridPos,
                hoveredBuilding: _hoveredBuilding,
                conveyorMode: widget.conveyorMode,
                conveyorConfirmedPath: beltCtrl.confirmedPath,
                conveyorPreviewPath: beltCtrl.previewPath,
                conveyorPreviewOccupied: beltCtrl.previewOccupied,
                conveyorPathInvalid: beltCtrl.pathInvalid,
                conveyorForkCell: beltCtrl.anchors.isNotEmpty
                    ? beltCtrl.anchors.first
                    : null,
                conveyorHasCommittedPath: beltCtrl.hasCommittedPath,
                conveyorIncomingDirection: beltCtrl.incomingDirection,
                previewContextExtension: beltCtrl.previewContextExtension,
                previewBridgeCells: beltCtrl.previewBridgeCells,
                displayScale: _displayScale,
                displayOffsetX: _displayOffsetX,
                displayOffsetY: _displayOffsetY,
                displayAngle: _displayAngle,
                portConnectionsCache: portConnectionsCache,
                isLongPressing: _isLongPressing,
                longPressScreenPos: _longPressScreenPos,
                longPressProgress: _longPressProgress,
                movingBuilding: _movingBuilding,
                movingRotation: _movingRotation,
                bridgeMoveHiddenCell: _bridgeMoveHiddenCell,
                beltArrowController: _beltArrowController,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}
