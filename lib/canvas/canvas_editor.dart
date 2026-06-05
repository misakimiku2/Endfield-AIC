import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/recipe.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../AIC/Production I/refining_unit.dart';
import '../AIC/Depot Access/depot_access.dart';
import 'grid_painter.dart';
import 'building_renderer.dart';
import '../AIC/Logistics Units/transport_belt.dart';
import '../AIC/Logistics Units/transport_belt_renderer.dart';
import '../widgets/conveyor_belt_dialog.dart';

class CanvasEditor extends StatefulWidget {
  final DataLoader dataLoader;
  final ProjectState project;
  final ValueChanged<ProjectState> onProjectChanged;
  final Building? placingBuilding;
  final VoidCallback? onBuildingPlaced;
  final ValueChanged<PlacedBuilding?>? onBuildingSelected;
  final bool conveyorMode;

  const CanvasEditor({
    super.key,
    required this.dataLoader,
    required this.project,
    required this.onProjectChanged,
    this.placingBuilding,
    this.onBuildingPlaced,
    this.onBuildingSelected,
    this.conveyorMode = false,
  });

  @override
  State<CanvasEditor> createState() => CanvasEditorState();
}

class CanvasEditorState extends State<CanvasEditor>
    with TickerProviderStateMixin {
  Offset? _lastFocalPoint;
  bool _isPanning = false;
  Offset? _mouseGridPos;

  late final TransportBeltController _beltCtrl;

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
  double _targetAngle = 0.0;  // 目标角度（弧度）

  static const double _cellSize = 48.0;
  static const double _minScale = 0.25;
  static const double _maxScale = 5.0;

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

  // 移动模式下：端口传送带快照（用于取消移动时恢复）
  List<ConveyorBelt>? _portBeltsSnapshot;

  // 端口连接缓存：building id -> port key -> 是否连接
  Map<String, Map<String, bool>> _portConnectionsCache = {};

  // 记录最近一次 onPointerDown 是否为左键
  bool _lastPointerWasPrimary = false;

  // 重绘触发计数器，确保图片缓存清理后，即使其他属性不变，也能正常强制触发 CustomPainter 完成重绘
  int _repaintTrigger = 0;

  void _forceRepaint() {
    _EditorPainter.clearPictureCache();
    _repaintTrigger++;
    if (mounted) {
      setState(() {});
    }
  }

  ProjectState get _project => widget.project;

  /// 重新计算所有端口连接关系（仅在数据变更时调用）
  void _rebuildPortConnectionsCache() {
    _portConnectionsCache = {};
    for (final pb in _project.buildings) {
      final connections = <String, bool>{};
      for (final belt in _project.conveyors) {
        for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
          final portWorld = port.worldPosition(
              pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
          final distStart = (belt.start - portWorld).distance;
          final distEnd = (belt.end - portWorld).distance;
          if (distStart < 30 || distEnd < 30) {
            connections['${port.type}_${port.index}'] = true;
          }
        }
      }
      _portConnectionsCache[pb.id] = connections;
    }
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
    _beltCtrl = TransportBeltController(
      project: _project,
      onProjectChanged: widget.onProjectChanged,
      onRebuildCache: _rebuildPortConnectionsCache,
      notifyListeners: () => setState(() {}),
    );
    _beltArrowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _rebuildPortConnectionsCache();
    TransportBeltRenderer.init();
    RefiningUnitRenderer.init(onReady: () {
      _forceRepaint();
    });
    DepotAccessRenderer.init(onReady: () {
      _forceRepaint();
    });
  }

  @override
  void didUpdateWidget(covariant CanvasEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.project, oldWidget.project)) {
      if ((widget.project.offsetX - _targetOffsetX).abs() > 1 ||
          (widget.project.offsetY - _targetOffsetY).abs() > 1 ||
          (widget.project.scale - _targetScale).abs() > 0.01) {
        _displayScale = widget.project.scale;
        _displayOffsetX = widget.project.offsetX;
        _displayOffsetY = widget.project.offsetY;
        _targetScale = widget.project.scale;
        _targetOffsetX = widget.project.offsetX;
        _targetOffsetY = widget.project.offsetY;
      }
      // project 引用变化时重建端口连接缓存
      _rebuildPortConnectionsCache();
    }
    if (!identical(oldWidget.placingBuilding, widget.placingBuilding) &&
        widget.placingBuilding != null &&
        oldWidget.placingBuilding == null) {
      _placingRotation = 0;
    }
    if (widget.conveyorMode != oldWidget.conveyorMode) {
      _forceRepaint();
      if (oldWidget.conveyorMode && !widget.conveyorMode) {
        _beltCtrl.reset();
      }
    }
    if (!identical(widget.project, oldWidget.project)) {
      _beltCtrl.project = widget.project;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _beltArrowController.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // 长按进度计算
    if (_isLongPressing && _longPressStartTime != null) {
      _longPressProgress = (DateTime.now()
              .difference(_longPressStartTime!)
              .inMilliseconds /
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
    _displayAngle = rotationDone ? _targetAngle : _displayAngle + angleDiff * lerpFactor;

    final hasRunningAnimation = !scaleDone || !offsetXDone || !offsetYDone || !rotationDone;
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

    // 保存所有传送带的完整快照（用于取消移动时恢复）
    _portBeltsSnapshot = _project.conveyors.map((b) => ConveyorBelt(
      id: b.id,
      path: List<Offset>.from(b.path),
      itemId: b.itemId,
      isBlocked: b.isBlocked,
      forcedDirection: b.forcedDirection,
      incomingDirection: b.incomingDirection,
    )).toList();

    // 从工程中移除建筑
    _project.buildings.remove(pb);

    // 移除设备端口上的传送带格子（视觉隐藏）
    _removePortBeltCells(pb);

    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
    setState(() {});
  }

  /// 从工程中删除设备，同时移除其端口上的传送带格子
  void deleteBuilding(PlacedBuilding pb) {
    _project.buildings.remove(pb);
    _removePortBeltCells(pb);
    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
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
    pos = Offset(
      pos.dx * cosA + pos.dy * sinA,
      -pos.dx * sinA + pos.dy * cosA,
    );
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
      (world.dx / _cellSize).floorToDouble(),
      (world.dy / _cellSize).floorToDouble(),
    );
  }

  PlacedBuilding? _getBuildingAt(Offset gridPos) {
    for (final pb in _project.buildings.reversed) {
      final bounds = pb.getBounds(_cellSize);
      if (bounds.contains(gridPos * _cellSize)) {
        return pb;
      }
    }
    return null;
  }

  void _handleScroll(PointerScrollEvent event, Offset localPos) {
    if (_isMiddleDragging) return;

    final oldScale = _targetScale;
    final newScale =
        (_targetScale * (1 - event.scrollDelta.dy / 200)).clamp(_minScale, _maxScale);

    if ((newScale - oldScale).abs() < 0.0001) return;

    // 将屏幕坐标转换到旋转前的空间（offset所在的空间）
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final center = Offset(size.width / 2, size.height / 2);
    final cosA = math.cos(_displayAngle);
    final sinA = math.sin(_displayAngle);
    var preRotationPos = Offset(localPos.dx - center.dx, localPos.dy - center.dy);
    preRotationPos = Offset(
      preRotationPos.dx * cosA + preRotationPos.dy * sinA,
      -preRotationPos.dx * sinA + preRotationPos.dy * cosA,
    );
    preRotationPos = Offset(preRotationPos.dx + center.dx, preRotationPos.dy + center.dy);

    _targetOffsetX =
        (preRotationPos.dx + _targetOffsetX) * newScale / oldScale - preRotationPos.dx;
    _targetOffsetY =
        (preRotationPos.dy + _targetOffsetY) * newScale / oldScale - preRotationPos.dy;
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

  /// 将屏幕空间的拖拽delta转换到offset坐标系（反向旋转）
  Offset _screenDeltaToWorldDelta(Offset screenDelta) {
    final cosA = math.cos(_displayAngle);
    final sinA = math.sin(_displayAngle);
    return Offset(
      screenDelta.dx * cosA + screenDelta.dy * sinA,
      -screenDelta.dx * sinA + screenDelta.dy * cosA,
    );
  }

  void _handleTap(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final building = widget.placingBuilding;

    if (building != null) {
      _placeBuilding(building, gridPos, rotation: _placingRotation);
      return;
    }

    if (widget.conveyorMode) {
      if (_beltCtrl.handleTap(gridPos)) return;
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
        final portGrid = port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
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

        final connectsAtStart = (firstCell.dx == otherLast.dx && firstCell.dy == otherLast.dy) ||
            (lastCell.dx == otherFirst.dx && lastCell.dy == otherFirst.dy);

        if (connectsAtStart) {
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
      dataLoader: widget.dataLoader,
      onStoreSingle: () => _removeBeltCell(targetBeltId, clickedCell),
      onStoreLine: () => _storeBeltLineByIds(lineIds),
      onCollectAll: () => _collectAllFromLine(allLineBelts),
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
        _project.conveyors.add(ConveyorBelt(
          id: 'belt_${DateTime.now().millisecondsSinceEpoch}_a',
          path: beforePath,
          itemId: belt.itemId,
          isBlocked: belt.isBlocked,
          incomingDirection: belt.incomingDirection,
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
          isBlocked: belt.isBlocked,
          forcedDirection: forcedDir,
          incomingDirection: incomingDir,
        ));
      }

      _rebuildPortConnectionsCache();
      widget.onProjectChanged(_project);
    });
  }

  void _storeBeltLineByIds(Set<String> beltIds) {
    setState(() {
      _project.conveyors.removeWhere((b) => beltIds.contains(b.id));
      _rebuildPortConnectionsCache();
      widget.onProjectChanged(_project);
    });
  }

  void _collectAllFromLine(List<ConveyorBelt> belts) {
    for (final belt in belts) {
      if (belt.itemId.isNotEmpty) {
        setState(() {
          belt.itemId = '';
        });
      }
    }
    widget.onProjectChanged(_project);
  }

  /// 检查建筑在指定位置是否会发生碰撞（建筑重叠或传送带重叠）
  bool _checkBuildingCollision(Building building, double cx, double cy, int rotation) {
    final tempBuilding = PlacedBuilding(
      id: 'temp',
      building: building,
      gridX: cx,
      gridY: cy,
      rotation: rotation,
    );
    final bounds = tempBuilding.getBounds(_cellSize);
    final buildingOverlaps = _project.buildings.any(
      (b) => b.overlaps(bounds, _cellSize),
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
        cells.add('${(effX + dx).toInt()}_${(effY + dy).toInt()}');
      }
    }
    return _project.conveyors.any((b) =>
        b.path.any((c) => cells.contains('${c.dx.toInt()}_${c.dy.toInt()}')));
  }

  void _placeBuilding(Building building, Offset gridPos, {int rotation = 0}) {
    final cx = gridPos.dx - (building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (building.gridHeight ~/ 2).toDouble();

    if (_checkBuildingCollision(building, cx, cy, rotation)) return;

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
    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
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

    // 保存所有传送带的完整快照（用于取消移动时恢复）
    _portBeltsSnapshot = _project.conveyors.map((b) => ConveyorBelt(
      id: b.id,
      path: List<Offset>.from(b.path),
      itemId: b.itemId,
      isBlocked: b.isBlocked,
      forcedDirection: b.forcedDirection,
      incomingDirection: b.incomingDirection,
    )).toList();

    // 从工程中移除建筑
    _project.buildings.remove(_longPressTargetBuilding);
    _longPressTargetBuilding = null;
    _longPressStartTime = null;
    _longPressScreenPos = null;

    // 移除设备端口上的传送带格子（视觉隐藏）
    _removePortBeltCells(_movingBuilding!);

    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
  }

  /// 移除设备输入/输出端口上的传送带格子
  void _removePortBeltCells(PlacedBuilding pb) {
    final portCells = <Offset>[];
    final rot = pb.rotation;
    final gw = pb.building.gridWidth;
    final gh = pb.building.gridHeight;
    for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
      portCells.add(port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot));
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
          String? forcedDir;
          if (segment.length == 1) forcedDir = incomingDir;
          toAdd.add(ConveyorBelt(
            id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
            path: segment,
            itemId: belt.itemId,
            isBlocked: belt.isBlocked,
            forcedDirection: forcedDir,
            incomingDirection: incomingDir,
          ));
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
        String? forcedDir;
        if (segment.length == 1) forcedDir = incomingDir;
        toAdd.add(ConveyorBelt(
          id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
          path: segment,
          itemId: belt.itemId,
          isBlocked: belt.isBlocked,
          forcedDirection: forcedDir,
          incomingDirection: incomingDir,
        ));
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
  bool get isCreatingConveyorBelt => _beltCtrl.anchors.isNotEmpty;

  /// 完成传送带创建（ESC 按下且有锚点时调用）
  void finishConveyorBeltCreation() {
    _beltCtrl.handleKeyEscape();
  }

  bool cancelMoveMode() {
    if (_movingBuilding == null) return false;
    // 恢复到原始位置
    _movingBuilding!.gridX = _movingOriginalGridX;
    _movingBuilding!.gridY = _movingOriginalGridY;
    _project.buildings.add(_movingBuilding!);
    _movingBuilding = null;
    _movingRotation = 0;

    // 恢复传送带快照（撤销端口格子的移除）
    if (_portBeltsSnapshot != null) {
      _project.conveyors
        ..clear()
        ..addAll(_portBeltsSnapshot!);
      _portBeltsSnapshot = null;
    }

    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
    setState(() {});
    return true;
  }

  void _placeMovingBuilding(Offset gridPos) {
    if (_movingBuilding == null) return;
    final cx = gridPos.dx - (_movingBuilding!.building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (_movingBuilding!.building.gridHeight ~/ 2).toDouble();

    _movingBuilding!.gridX = cx;
    _movingBuilding!.gridY = cy;
    _movingBuilding!.rotation = _movingRotation;

    if (_checkBuildingCollision(_movingBuilding!.building, cx, cy, _movingRotation)) return;

    _project.buildings.add(_movingBuilding!);
    _movingBuilding = null;
    _movingRotation = 0;
    // 放置成功：丢弃快照，端口格子保持移除状态
    _portBeltsSnapshot = null;
    _project.offsetX = _targetOffsetX;
    _project.offsetY = _targetOffsetY;
    _project.scale = _targetScale;
    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
  }

  void _handleSingleClick(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final pb = _getBuildingAt(gridPos);
    widget.onBuildingSelected?.call(pb);
  }

  void _handleRightClick(Offset screenPos, Size size) {
    _beltCtrl.handleRightClick();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_movingBuilding != null) {
          cancelMoveMode();
          return KeyEventResult.handled;
        }
        if (widget.conveyorMode && _beltCtrl.handleKeyEscape()) {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: MouseRegion(
      onHover: (event) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localPos = renderBox.globalToLocal(event.position);
        final gridPos = _screenToGrid(localPos, renderBox.size);
        // 只在网格位置变化时才触发重绘
        if (_mouseGridPos == gridPos) return;
        setState(() {
          _mouseGridPos = gridPos;
          // 检测悬停的建筑
          _hoveredBuilding = widget.placingBuilding == null &&
                  _movingBuilding == null
              ? _getBuildingAt(gridPos)
              : null;
          if (widget.conveyorMode) {
            _beltCtrl.handleHover(gridPos);
          } else {
            _beltCtrl.reset();
          }
        });
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final renderBox = context.findRenderObject() as RenderBox;
            final localPos = renderBox.globalToLocal(event.position);
            _handleScroll(event, localPos);
          }
        },
        onPointerDown: (event) {
          _lastPointerWasPrimary = event.buttons & kPrimaryMouseButton != 0;
          // 中键拖拽
          if (event.buttons & kMiddleMouseButton != 0 && _middleDragPointerId == null) {
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
          if (event.buttons & kSecondaryMouseButton != 0 && _movingBuilding != null) {
            cancelMoveMode();
            setState(() {});
          }
        },
        onPointerMove: (event) {
          if (event.pointer == _middleDragPointerId && _lastMiddlePos != null) {
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
            if ((event.localPosition - _longPressScreenPos!).distance > cancelDist) {
              _cancelLongPress();
              setState(() {});
            }
          }
        },
        onPointerUp: (event) {
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
            if (isPrimaryButton && !widget.conveyorMode && widget.placingBuilding == null) {
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
        },
        onPointerCancel: (event) {
          if (event.pointer == _middleDragPointerId) {
            _middleDragPointerId = null;
            _lastMiddlePos = null;
            _isMiddleDragging = false;
          }
          if (_isLongPressing) {
            _cancelLongPress();
            setState(() {});
          }
        },
        child: GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            _handleScaleUpdate(details, renderBox.size);
          },
          onScaleEnd: _handleScaleEnd,
          onSecondaryTapUp: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            _handleRightClick(details.localPosition, renderBox.size);
          },
          child: CustomPaint(
            painter: _EditorPainter(
              repaintTrigger: _repaintTrigger,
              project: _project,
              dataLoader: widget.dataLoader,
              cellSize: _cellSize,
              placingBuilding: widget.placingBuilding,
              placingRotation: _placingRotation,
              mouseGridPos: _mouseGridPos,
              hoveredBuilding: _hoveredBuilding,
              conveyorMode: widget.conveyorMode,
              conveyorConfirmedPath: _beltCtrl.confirmedPath,
              conveyorPreviewPath: _beltCtrl.previewPath,
              conveyorPreviewOccupied: _beltCtrl.previewOccupied,
              conveyorPathInvalid: _beltCtrl.pathInvalid,
              conveyorForkCell: _beltCtrl.anchors.isNotEmpty ? _beltCtrl.anchors.first : null,
              conveyorIncomingDirection: _beltCtrl.incomingDirection,
              previewContextExtension: _beltCtrl.previewContextExtension,
              displayScale: _displayScale,
              displayOffsetX: _displayOffsetX,
              displayOffsetY: _displayOffsetY,
              displayAngle: _displayAngle,
              portConnectionsCache: _portConnectionsCache,
              isLongPressing: _isLongPressing,
              longPressScreenPos: _longPressScreenPos,
              longPressProgress: _longPressProgress,
              movingBuilding: _movingBuilding,
              movingRotation: _movingRotation,
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

class _EditorPainter extends CustomPainter {
  final int repaintTrigger;
  final ProjectState project;
  final DataLoader dataLoader;
  final double cellSize;
  final Building? placingBuilding;
  final int placingRotation;
  final Offset? mouseGridPos;
  final PlacedBuilding? hoveredBuilding;
  final bool conveyorMode;
  final List<Offset> conveyorConfirmedPath;
  final List<Offset>? conveyorPreviewPath;
  final Set<String>? conveyorPreviewOccupied;
  final bool conveyorPathInvalid;
  final Offset? conveyorForkCell;
  final String? conveyorIncomingDirection;
  final List<Offset>? previewContextExtension;
  final double displayScale;
  final double displayOffsetX;
  final double displayOffsetY;
  final double displayAngle;
  final Map<String, Map<String, bool>> portConnectionsCache;
  final bool isLongPressing;
  final Offset? longPressScreenPos;
  final double longPressProgress;
  final PlacedBuilding? movingBuilding;
  final int movingRotation;
  final AnimationController beltArrowController;

  // 预渲染缓存: key = "buildingId_rotation_detailLevel_portsHash" -> Picture
  static final Map<String, ui.Picture> _pictureCache = {};
  static const int _maxCacheSize = 200;

/// 清除所有静态渲染缓存
  static void clearPictureCache() {
    _pictureCache.clear();
  }

  _EditorPainter({
    required this.repaintTrigger,
    required this.project,
    required this.dataLoader,
    required this.cellSize,
    this.placingBuilding,
    this.placingRotation = 0,
    this.mouseGridPos,
    this.hoveredBuilding,
    this.conveyorMode = false,
    this.conveyorConfirmedPath = const [],
    this.conveyorPreviewPath,
    this.conveyorPreviewOccupied,
    this.conveyorPathInvalid = false,
    this.conveyorForkCell,
    this.conveyorIncomingDirection,
    this.previewContextExtension,
    required this.displayScale,
    required this.displayOffsetX,
    required this.displayOffsetY,
    required this.displayAngle,
    required this.portConnectionsCache,
    this.isLongPressing = false,
    this.longPressScreenPos,
    this.longPressProgress = 0.0,
    this.movingBuilding,
    this.movingRotation = 0,
    required this.beltArrowController,
  }) : super(repaint: Listenable.merge([beltArrowController]));

  @override
  void paint(Canvas canvas, Size size) {
    // 计算可见世界区域（视口裁剪用）
    final viewport = _computeViewport(size);

    final gridPainter = GridPainter(
      offsetX: displayOffsetX,
      offsetY: displayOffsetY,
      scale: displayScale,
      cellSize: cellSize,
      rotation: displayAngle,
    );
    gridPainter.paint(canvas, size);

    canvas.save();
    if (displayAngle != 0) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(displayAngle);
      canvas.translate(-center.dx, -center.dy);
    }
    canvas.translate(-displayOffsetX, -displayOffsetY);
    canvas.scale(displayScale);

    // LOD: 根据缩放级别决定渲染细节
    final detailLevel = displayScale < 0.35 ? 0 : (displayScale < 0.5 ? 1 : 2);

    // 获取当前正在绘制的新传送带的分叉点（用于旧道动态裁剪）
    // 使用 anchors.first（用户实际点击的位置），而非路径的 first
    // 如果当前路径有效，才需要对原传送带进行裁剪来建立连接。
    // 如果新传送带路径无效，不应对旧传送带进行裁剪，以保持已有样式的完整性。
    final Offset? startCell = conveyorPathInvalid ? null : conveyorForkCell;

    // 构建 fullPathContext（已确认段 + 实时段的完整路径）
    // 不论路径有效还是无效都构建上下文，这样即使渲染红色错误预览时，转角处的纹理也能计算正确
    List<Offset>? fullPathContext;
    int confirmedStartIndex = 0;
    int previewStartIndex = conveyorConfirmedPath.length;

    if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
      if (conveyorConfirmedPath.isNotEmpty) {
        fullPathContext = [...conveyorConfirmedPath, ...conveyorPreviewPath!];
        // 去重：已确认段末尾和实时段开头可能重叠
        if (fullPathContext.length >= 2 &&
            fullPathContext[conveyorConfirmedPath.length - 1].dx == fullPathContext[conveyorConfirmedPath.length].dx &&
            fullPathContext[conveyorConfirmedPath.length - 1].dy == fullPathContext[conveyorConfirmedPath.length].dy) {
          fullPathContext.removeAt(conveyorConfirmedPath.length);
          previewStartIndex = conveyorConfirmedPath.length - 1;
        }
      } else {
        // 第一段创建时 confirmedPath 为空，仅用 previewPath 构建上下文
        fullPathContext = [...conveyorPreviewPath!];
        previewStartIndex = 0;
      }
    }

    // 追加转角上下文扩展（合并目标的路径，仅用于转角检测，不渲染为蓝色预览）
    if (previewContextExtension != null && previewContextExtension!.isNotEmpty && fullPathContext != null) {
      fullPathContext.addAll(previewContextExtension!);
    }

    // 调试：视口与裁剪统计（有裁剪时才输出，且每2秒最多一次）
    for (final belt in project.conveyors) {
      // 动态裁剪：如果当前正在绘制且起点在旧传送带上，裁剪分叉点之前的部分
      List<Offset> renderPath = belt.path;
      int forkIdx = -1;
      if (startCell != null) {
        for (int i = 0; i < belt.path.length; i++) {
          if (belt.path[i].dx == startCell.dx && belt.path[i].dy == startCell.dy) {
            forkIdx = i;
            break;
          }
        }
        if (forkIdx >= 0 && forkIdx < belt.path.length - 1) {
          renderPath = belt.path.sublist(forkIdx + 1);
        } else if (forkIdx >= 0) {
          // 分叉点在末尾或之后，整条旧道被替代，不渲染
          continue;
        }
      }

      final visible = _isPathVisible(renderPath, viewport);
      if (!visible) {
        continue;
      }
      final item = dataLoader.getItem(belt.itemId);
      // 如果路径被裁剪，创建临时 ConveyorBelt 用于渲染
      if (!identical(renderPath, belt.path)) {
        // 单格下游：从旧传送带推断原始方向
        String? forcedDir;
        // 下游首格的入方向：从分叉点指向下游首格
        String? incomingDir;
        if (forkIdx >= 0 && forkIdx + 1 < belt.path.length) {
          final dx = belt.path[forkIdx + 1].dx - belt.path[forkIdx].dx;
          final dy = belt.path[forkIdx + 1].dy - belt.path[forkIdx].dy;
          if (dx > 0) { incomingDir = 'right'; }
          else if (dx < 0) { incomingDir = 'left'; }
          else if (dy > 0) { incomingDir = 'down'; }
          else if (dy < 0) { incomingDir = 'up'; }
          if (renderPath.length == 1) { 
            // 如果仅剩最后一格，且原传送带定义了 forcedDirection，则保留原转向
            forcedDir = belt.forcedDirection ?? incomingDir; 
          }
        }
        final clippedBelt = ConveyorBelt(
          id: belt.id,
          path: renderPath,
          itemId: belt.itemId,
          isBlocked: belt.isBlocked,
          forcedDirection: forcedDir,
          incomingDirection: incomingDir,
        );
        TransportBeltRenderer.renderConveyorPath(canvas, clippedBelt, item, cellSize, project.buildings, detailLevel: detailLevel, arrowProgress: beltArrowController.value);
      } else {
        TransportBeltRenderer.renderConveyorPath(canvas, belt, item, cellSize, project.buildings, detailLevel: detailLevel, arrowProgress: beltArrowController.value);
      }
    }

    // Build previewSet for checking which ports are currently covered by preview path
    final Set<Offset> previewSet = {};
    if (conveyorMode) {
      if (conveyorConfirmedPath.isNotEmpty) {
        previewSet.addAll(conveyorConfirmedPath);
      }
      if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
        previewSet.addAll(conveyorPreviewPath!);
      }
    }

    // 已确认段始终使用传送带本色渲染（不论有效还是无效） - (放到建筑下方渲染)
    if (conveyorConfirmedPath.isNotEmpty) {
      TransportBeltRenderer.renderConfirmedPreviewPath(
        canvas, conveyorConfirmedPath, cellSize,
        project.buildings,
        fullPathContext: fullPathContext,
        contextStartIndex: confirmedStartIndex,
        incomingDirection: conveyorIncomingDirection,
      );
    }

    // 实时段根据有效/无效状态分别渲染 - (放到建筑下方渲染)
    if (conveyorPathInvalid) {
      // 无效状态：仅实时段标红，但是同样传入 fullPathContext 使得转弯样式能与已确认段进行平滑衔接
      if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
        TransportBeltRenderer.renderPreviewPath(
          canvas,
          conveyorPreviewPath!,
          cellSize,
          <String>{},
          project.buildings,
          isInvalid: true,
          fullPathContext: fullPathContext,
          contextStartIndex: previewStartIndex,
          incomingDirection: conveyorIncomingDirection,
        );
      }
    } else {
      // 有效状态：实时段为蓝色预览
      if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
        TransportBeltRenderer.renderPreviewPath(
          canvas,
          conveyorPreviewPath!,
          cellSize,
          <String>{},
          project.buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: previewStartIndex,
          incomingDirection: conveyorIncomingDirection,
        );
      } else if (conveyorMode && mouseGridPos != null && conveyorConfirmedPath.isEmpty) {
        // 传送带处于尚未锚定的预备状态且当前空节点鼠标浮动时，高亮选中指示格
        TransportBeltRenderer.renderHoverHighlight(canvas, mouseGridPos!, cellSize);
      }
    }

    for (final pb in project.buildings) {
      if (!_isBuildingVisible(pb, viewport)) continue;

      // Compute combined port states (actual + preview connections)
      final combinedPorts = <String, int>{};
      final actualConns = portConnectionsCache[pb.id] ?? <String, bool>{};
      actualConns.forEach((key, isConnected) {
        if (isConnected) {
          combinedPorts[key] = 1; // 1 = connected yellow
        }
      });

      if (conveyorMode) {
        bool containsGrid(Offset portGrid) {
          final px = portGrid.dx.round();
          final py = portGrid.dy.round();
          for (final cell in previewSet) {
            if (cell.dx.round() == px && cell.dy.round() == py) {
              return true;
            }
          }
          return false;
        }

        for (int i = 0; i < pb.inputPorts.length; i++) {
          final port = pb.inputPorts[i];
          final portGrid = port.gridPosition(
            pb.gridX, pb.gridY, pb.building.gridWidth, pb.building.gridHeight,
            rotation: pb.rotation,
          );
          if (containsGrid(portGrid)) {
            combinedPorts['input_$i'] = 2; // 2 = preview blue
          }
        }
        for (int i = 0; i < pb.outputPorts.length; i++) {
          final port = pb.outputPorts[i];
          final portGrid = port.gridPosition(
            pb.gridX, pb.gridY, pb.building.gridWidth, pb.building.gridHeight,
            rotation: pb.rotation,
          );
          if (containsGrid(portGrid)) {
            combinedPorts['output_$i'] = 2; // 2 = preview blue
          }
        }
      }

      // 预渲染缓存 key
      final sortedEntries = combinedPorts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      final portsHash = sortedEntries.map((e) => '${e.key}:${e.value}').join(',');
      final cacheKey = '${pb.building.id}_${pb.rotation}_${detailLevel}_$portsHash';

      final x = pb.gridX * cellSize;
      final y = pb.gridY * cellSize;
      final w = pb.building.gridWidth * cellSize;
      final h = pb.building.gridHeight * cellSize;

      ui.Picture? cachedPicture = _pictureCache[cacheKey];
      if (cachedPicture == null) {
        final recorder = ui.PictureRecorder();
        final recordCanvas = Canvas(recorder);
        recordCanvas.translate(w / 2, h / 2);
        recordCanvas.rotate(pb.rotation * math.pi / 2);
        recordCanvas.translate(-w / 2, -h / 2);

        _renderBuildingStatic(recordCanvas, pb, cellSize, detailLevel, combinedPorts);

        cachedPicture = recorder.endRecording();
        if (_pictureCache.length >= _maxCacheSize) {
          _pictureCache.remove(_pictureCache.keys.first);
        }
        _pictureCache[cacheKey] = cachedPicture;
      }

      canvas.save();
      canvas.translate(x, y);
      canvas.drawPicture(cachedPicture);
      canvas.restore();

      // Logo 单独绘制（不缓存），始终不随设备/画布旋转
      if (pb.building.id == RefiningUnitConfig.id && RefiningUnitRenderer.isReady) {
        RefiningUnitRenderer.renderLogo(
          canvas, x, y, w, h, pb.rotation, displayAngle,
        );
      } else if ((pb.building.id == DepotLoaderConfig.id || pb.building.id == DepotUnloaderConfig.id) && DepotAccessRenderer.isReady) {
        DepotAccessRenderer.renderLogo(
          canvas, x, y, w, h, pb.building.id, pb.rotation, displayAngle,
        );
      }

      // 动态部分：进度条（每帧绘制，不缓存）
      if (detailLevel >= 1 && pb.productionProgress > 0 && pb.productionProgress < 1.0) {
        canvas.save();
        canvas.translate(x + w / 2, y + h / 2);
        canvas.rotate(pb.rotation * math.pi / 2);
        canvas.translate(-w / 2, -h / 2);
        _drawProgressBar(canvas, w, h, pb.productionProgress, pb.building);
        canvas.restore();
      }
    }

    if (placingBuilding != null && mouseGridPos != null) {
      final cx = mouseGridPos!.dx - (placingBuilding!.gridWidth ~/ 2).toDouble();
      final cy = mouseGridPos!.dy - (placingBuilding!.gridHeight ~/ 2).toDouble();
      final isBlocked = _isPreviewBlocked(placingBuilding!, cx, cy, placingRotation);

      if (placingBuilding!.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation, isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (placingBuilding!.id == DepotLoaderConfig.id ||
          placingBuilding!.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation, isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation, isBlocked: isBlocked,
        );
      }

      // 碰撞时绘制阻拦对象红色叠加
      if (isBlocked) {
        _drawBlockedOverlays(canvas, placingBuilding!, cx, cy, placingRotation);
      }
    }

    // 移动中的建筑预览
    if (movingBuilding != null && mouseGridPos != null) {
      final mb = movingBuilding!;
      final cx = mouseGridPos!.dx - (mb.building.gridWidth ~/ 2).toDouble();
      final cy = mouseGridPos!.dy - (mb.building.gridHeight ~/ 2).toDouble();
      final isBlocked = _isPreviewBlocked(mb.building, cx, cy, movingRotation);

      if (mb.building.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation, isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (mb.building.id == DepotLoaderConfig.id ||
          mb.building.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation, isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation, isBlocked: isBlocked,
        );
      }

      // 碰撞时绘制阻拦对象红色叠加
      if (isBlocked) {
        _drawBlockedOverlays(canvas, mb.building, cx, cy, movingRotation);
      }
    }

    // 悬停高亮白框
    if (hoveredBuilding != null && placingBuilding == null && movingBuilding == null) {
      final hb = hoveredBuilding!;
      final hx = hb.gridX * cellSize;
      final hy = hb.gridY * cellSize;
      final hw = hb.building.gridWidth * cellSize;
      final hh = hb.building.gridHeight * cellSize;

      canvas.save();
      canvas.translate(hx + hw / 2, hy + hh / 2);
      canvas.rotate(hb.rotation * math.pi / 2);
      canvas.translate(-hw / 2, -hh / 2);

      final highlightPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(0, 0, hw, hh), highlightPaint);

      canvas.restore();
    }

    canvas.restore();

    // 长按圆形进度条（屏幕空间绘制，进度超过阈值才显示，避免快速点击闪烁）
    if (isLongPressing && longPressScreenPos != null && longPressProgress > 0.15) {
      final center = longPressScreenPos!;
      const radius = 24.0;
      const strokeW = 4.0;

      // 背景圆环
      final bgPaint = Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;
      canvas.drawCircle(center, radius, bgPaint);

      // 蓝色填充弧（顺时针，从顶部开始）
      final progressPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // 12点方向
      final sweepAngle = 2 * math.pi * longPressProgress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  /// 计算可见世界坐标区域（考虑旋转的轴对齐包围盒）
  _Viewport _computeViewport(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cosA = math.cos(displayAngle);
    final sinA = math.sin(displayAngle);

    // 屏幕四角逆变换到世界坐标
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final corner in corners) {
      var pos = corner;
      // 逆变换: translate(-center) → inverse-rotate → translate(center) → translate(+offset) → unscale
      pos = Offset(pos.dx - center.dx, pos.dy - center.dy);
      pos = Offset(
        pos.dx * cosA + pos.dy * sinA,
        -pos.dx * sinA + pos.dy * cosA,
      );
      pos = Offset(pos.dx + center.dx, pos.dy + center.dy);
      pos = Offset(pos.dx + displayOffsetX, pos.dy + displayOffsetY);
      pos = Offset(pos.dx / displayScale, pos.dy / displayScale);

      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    return _Viewport(minX, minY, maxX, maxY);
  }

  /// 判断预览建筑是否与现有建筑或传送带碰撞
  bool _isPreviewBlocked(Building building, double gridX, double gridY, int rotation) {
    final tempPb = PlacedBuilding(
      id: '_preview',
      building: building,
      gridX: gridX,
      gridY: gridY,
      rotation: rotation,
    );
    final bounds = tempPb.getBounds(cellSize);

    // 检测与现有建筑的碰撞
    for (final pb in project.buildings) {
      if (pb.overlaps(bounds, cellSize)) return true;
    }

    // 检测与传送带的碰撞
    final previewCells = _getGridCells(building, gridX, gridY, rotation);
    for (final belt in project.conveyors) {
      for (final cell in belt.path) {
        if (previewCells.contains(Offset(cell.dx.roundToDouble(), cell.dy.roundToDouble()))) {
          return true;
        }
      }
    }
    return false;
  }

  /// 获取建筑占用的网格坐标集合
  Set<Offset> _getGridCells(Building building, double gridX, double gridY, int rotation) {
    final cells = <Offset>{};
    // 考虑旋转后的有效尺寸
    int effW, effH;
    double effX, effY;
    if (rotation % 2 == 1) {
      effW = building.gridHeight;
      effH = building.gridWidth;
    } else {
      effW = building.gridWidth;
      effH = building.gridHeight;
    }
    effX = gridX + (building.gridWidth - effW) / 2.0;
    effY = gridY + (building.gridHeight - effH) / 2.0;

    for (int dx = 0; dx < effW; dx++) {
      for (int dy = 0; dy < effH; dy++) {
        cells.add(Offset((effX + dx).roundToDouble(), (effY + dy).roundToDouble()));
      }
    }
    return cells;
  }

  /// 绘制碰撞对象的红色叠加层
  void _drawBlockedOverlays(Canvas canvas, Building building, double gridX, double gridY, int rotation) {
    final previewCells = _getGridCells(building, gridX, gridY, rotation);
    final previewSet = previewCells.map((c) => '${c.dx.toInt()}_${c.dy.toInt()}').toSet();

    // 阻拦的建筑：整体变红
    for (final pb in project.buildings) {
      final tempPb = PlacedBuilding(
        id: '_temp', building: pb.building,
        gridX: pb.gridX, gridY: pb.gridY, rotation: pb.rotation,
      );
      final bounds = tempPb.getBounds(cellSize);
      final testPb = PlacedBuilding(
        id: '_preview', building: building,
        gridX: gridX, gridY: gridY, rotation: rotation,
      );
      if (!testPb.overlaps(bounds, cellSize)) continue;

      final x = pb.gridX * cellSize;
      final y = pb.gridY * cellSize;
      final w = pb.building.gridWidth * cellSize;
      final h = pb.building.gridHeight * cellSize;

      canvas.save();
      canvas.translate(x + w / 2, y + h / 2);
      canvas.rotate(pb.rotation * math.pi / 2);
      canvas.translate(-w / 2, -h / 2);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0x55FF4444),
      );
      canvas.restore();
    }

    // 阻拦的传送带：使用红色传送带预览渲染
    for (final belt in project.conveyors) {
      final blockedKeys = <String>{};
      for (final cell in belt.path) {
        final key = '${cell.dx.round()}_${cell.dy.round()}';
        if (previewSet.contains(key)) {
          blockedKeys.add(key);
        }
      }
      if (blockedKeys.isNotEmpty) {
        TransportBeltRenderer.renderBlockedBeltCells(
          canvas, belt.path, cellSize, blockedKeys, project.buildings,
          incomingDirection: belt.incomingDirection,
        );
      }
    }
  }

  /// 判断设备是否在视口内
  bool _isBuildingVisible(PlacedBuilding pb, _Viewport vp) {
    final x = pb.gridX * cellSize;
    final y = pb.gridY * cellSize;
    final w = pb.building.gridWidth * cellSize;
    final h = pb.building.gridHeight * cellSize;
    // AABB 碰撞检测
    return x + w > vp.minX && x < vp.maxX && y + h > vp.minY && y < vp.maxY;
  }

  /// 判断路径是否在视口内
  bool _isPathVisible(List<Offset> path, _Viewport vp) {
    if (path.isEmpty) return false;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final cell in path) {
      final x = cell.dx * cellSize;
      final y = cell.dy * cellSize;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x + cellSize > maxX) maxX = x + cellSize;
      if (y + cellSize > maxY) maxY = y + cellSize;
    }

    return maxX > vp.minX && minX < vp.maxX && maxY > vp.minY && minY < vp.maxY;
  }

  /// 渲染设备的静态部分到指定 Canvas（用于预渲染缓存）
  void _renderBuildingStatic(Canvas canvas, PlacedBuilding pb, double cellSize, int detailLevel, Map<String, int> portConnections) {
    Recipe? recipe;
    if (pb.activeRecipeId != null && detailLevel >= 1) {
      recipe = dataLoader.getRecipe(pb.activeRecipeId!);
    }

    if (pb.building.id == RefiningUnitConfig.id) {
      RefiningUnitRenderer.render(
        canvas, pb.building, 0, 0, cellSize, 0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0, // 静态部分不含进度条
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    } else if (pb.building.id == DepotLoaderConfig.id || pb.building.id == DepotUnloaderConfig.id) {
      DepotAccessRenderer.render(
        canvas, pb.building, 0, 0, cellSize, 0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0,
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    } else {
      BuildingRenderer.renderBuilding(
        canvas, pb.building, 0, 0, cellSize, 0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0,
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    }
  }

  /// 绘制进度条（动态部分，不缓存）
  void _drawProgressBar(Canvas canvas, double w, double h, double progress, Building building) {
    const barHeight = 4.0;
    final barY = h - barHeight - 2;
    canvas.drawRect(
      Rect.fromLTWH(2, barY, w - 4, barHeight),
      Paint()..color = const Color(0x40000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(2, barY, (w - 4) * progress, barHeight),
      Paint()..color = const Color(0xFF00FF66),
    );
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) {
    return repaintTrigger != oldDelegate.repaintTrigger ||
        project != oldDelegate.project ||
        dataLoader != oldDelegate.dataLoader ||
        cellSize != oldDelegate.cellSize ||
        placingBuilding != oldDelegate.placingBuilding ||
        placingRotation != oldDelegate.placingRotation ||
        mouseGridPos != oldDelegate.mouseGridPos ||
        hoveredBuilding != oldDelegate.hoveredBuilding ||
        conveyorMode != oldDelegate.conveyorMode ||
        conveyorPathInvalid != oldDelegate.conveyorPathInvalid ||
        conveyorForkCell != oldDelegate.conveyorForkCell ||
        conveyorIncomingDirection != oldDelegate.conveyorIncomingDirection ||
        previewContextExtension != oldDelegate.previewContextExtension ||
        !_listEquals(conveyorConfirmedPath, oldDelegate.conveyorConfirmedPath) ||
        !_listEquals(conveyorPreviewPath, oldDelegate.conveyorPreviewPath) ||
        !_setEquals(conveyorPreviewOccupied, oldDelegate.conveyorPreviewOccupied) ||
        displayScale != oldDelegate.displayScale ||
        displayOffsetX != oldDelegate.displayOffsetX ||
        displayOffsetY != oldDelegate.displayOffsetY ||
        displayAngle != oldDelegate.displayAngle ||
        isLongPressing != oldDelegate.isLongPressing ||
        longPressScreenPos != oldDelegate.longPressScreenPos ||
        longPressProgress != oldDelegate.longPressProgress ||
        movingBuilding != oldDelegate.movingBuilding ||
        movingRotation != oldDelegate.movingRotation;
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _setEquals<T>(Set<T>? a, Set<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

/// 视口区域（世界坐标）
class _Viewport {
  final double minX, minY, maxX, maxY;
  const _Viewport(this.minX, this.minY, this.maxX, this.maxY);
}
