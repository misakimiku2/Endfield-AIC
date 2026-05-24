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
import '../AIC/Production I/Depot Access/depot_access.dart';
import 'grid_painter.dart';
import 'building_renderer.dart';
import '../AIC/Logistics Units/transport_belt.dart';
import '../AIC/Logistics Units/transport_belt_renderer.dart';

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

  // 手动双击检测，避免 GestureDetector 的 300ms 等待
  DateTime? _lastTapTime;
  Offset? _lastTapPos;
  static const int _doubleTapMs = 400;
  static const double _doubleTapDistance = 20.0;

  late Ticker _ticker;
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

  // 端口连接缓存：building id -> port key -> 是否连接
  Map<String, Map<String, bool>> _portConnectionsCache = {};

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
    _rebuildPortConnectionsCache();
    TransportBeltRenderer.init();
    RefiningUnitRenderer.init(onReady: () {
      // SVG 加载完成后，清除静态缓存并触发重绘
      _EditorPainter.clearPictureCache();
      if (mounted) setState(() {});
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
    if (oldWidget.conveyorMode && !widget.conveyorMode) {
      _beltCtrl.reset();
    }
    if (!identical(widget.project, oldWidget.project)) {
      _beltCtrl.project = widget.project;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
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

    _targetOffsetX =
        (localPos.dx + _targetOffsetX) * newScale / oldScale - localPos.dx;
    _targetOffsetY =
        (localPos.dy + _targetOffsetY) * newScale / oldScale - localPos.dy;
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

  void _placeBuilding(Building building, Offset gridPos, {int rotation = 0}) {
    final cx = gridPos.dx - (building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (building.gridHeight ~/ 2).toDouble();
    final newBuilding = PlacedBuilding(
      id: 'building_${DateTime.now().millisecondsSinceEpoch}',
      building: building,
      gridX: cx,
      gridY: cy,
      rotation: rotation,
    );

    final bounds = newBuilding.getBounds(_cellSize);
    final overlaps = _project.buildings.any(
      (b) => b.overlaps(bounds, _cellSize),
    );

    if (!overlaps) {
      _project.buildings.add(newBuilding);
      _project.offsetX = _targetOffsetX;
      _project.offsetY = _targetOffsetY;
      _project.scale = _targetScale;
      _rebuildPortConnectionsCache();
      widget.onProjectChanged(_project);
      widget.onBuildingPlaced?.call();
    }
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

    // 从工程中移除建筑
    _project.buildings.remove(_longPressTargetBuilding);
    _longPressTargetBuilding = null;
    _longPressStartTime = null;
    _longPressScreenPos = null;

    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
  }

  void _cancelMoveMode() {
    if (_movingBuilding == null) return;
    // 恢复到原始位置
    _movingBuilding!.gridX = _movingOriginalGridX;
    _movingBuilding!.gridY = _movingOriginalGridY;
    _project.buildings.add(_movingBuilding!);
    _movingBuilding = null;
    _movingRotation = 0;

    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
    setState(() {});
  }

  void _placeMovingBuilding(Offset gridPos) {
    if (_movingBuilding == null) return;
    final cx = gridPos.dx - (_movingBuilding!.building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (_movingBuilding!.building.gridHeight ~/ 2).toDouble();

    _movingBuilding!.gridX = cx;
    _movingBuilding!.gridY = cy;
    _movingBuilding!.rotation = _movingRotation;

    final bounds = _movingBuilding!.getBounds(_cellSize);
    final overlaps = _project.buildings.any(
      (b) => b.overlaps(bounds, _cellSize),
    );

    if (!overlaps) {
      _project.buildings.add(_movingBuilding!);
      _movingBuilding = null;
      _movingRotation = 0;
      _project.offsetX = _targetOffsetX;
      _project.offsetY = _targetOffsetY;
      _project.scale = _targetScale;
      _rebuildPortConnectionsCache();
      widget.onProjectChanged(_project);
    }
  }

  void _handleDoubleTap(Offset screenPos, Size size) {
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
          _cancelMoveMode();
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
          // 长按未完成：视为点击
          if (_isLongPressing && _longPressProgress < 1.0) {
            _cancelLongPress();
            final renderBox = context.findRenderObject() as RenderBox;
            final localPos = event.localPosition;
            final now = DateTime.now();

            if (_lastTapTime != null &&
                now.difference(_lastTapTime!).inMilliseconds < _doubleTapMs &&
                _lastTapPos != null &&
                (localPos - _lastTapPos!).distance < _doubleTapDistance) {
              // 双击
              _handleDoubleTap(localPos, renderBox.size);
              _lastTapTime = null;
              _lastTapPos = null;
            } else {
              // 单击
              _handleTap(localPos, renderBox.size);
              _lastTapTime = now;
              _lastTapPos = localPos;
            }
            setState(() {});
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

  // 预渲染缓存: key = "buildingId_rotation_detailLevel_portsHash" -> Picture
  static final Map<String, ui.Picture> _pictureCache = {};
  static const int _maxCacheSize = 200;

/// 清除所有静态渲染缓存
  static void clearPictureCache() {
    _pictureCache.clear();
  }

  _EditorPainter({
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
  });

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
    if (conveyorConfirmedPath.isNotEmpty && conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
      fullPathContext = [...conveyorConfirmedPath, ...conveyorPreviewPath!];
      // 去重：已确认段末尾和实时段开头可能重叠
      if (fullPathContext.length >= 2 &&
          fullPathContext[conveyorConfirmedPath.length - 1].dx == fullPathContext[conveyorConfirmedPath.length].dx &&
          fullPathContext[conveyorConfirmedPath.length - 1].dy == fullPathContext[conveyorConfirmedPath.length].dy) {
        fullPathContext.removeAt(conveyorConfirmedPath.length);
      }
    }

    // 调试：视口与裁剪统计（有裁剪时才输出，且每2秒最多一次）
    for (final belt in project.conveyors) {
      // 动态裁剪：如果当前正在绘制且起点在旧传送带上，裁剪分叉点之前的部分
      List<Offset> renderPath = belt.path;
      if (startCell != null) {
        int forkIdx = -1;
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
        final clippedBelt = ConveyorBelt(
          id: belt.id,
          path: renderPath,
          itemId: belt.itemId,
          isBlocked: belt.isBlocked,
        );
        TransportBeltRenderer.renderConveyorPath(canvas, clippedBelt, item, cellSize, detailLevel: detailLevel);
      } else {
        TransportBeltRenderer.renderConveyorPath(canvas, belt, item, cellSize, detailLevel: detailLevel);
      }
    }

    for (final pb in project.buildings) {
      if (!_isBuildingVisible(pb, viewport)) continue;

      final portConnections = portConnectionsCache[pb.id] ?? <String, bool>{};

      // 预渲染缓存 key
      final portsHash = portConnections.entries.map((e) => '${e.key}:${e.value}').join(',');
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

        _renderBuildingStatic(recordCanvas, pb, cellSize, detailLevel, portConnections);

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

      if (placingBuilding!.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation,
        );
      } else if (placingBuilding!.id == DepotLoaderConfig.id ||
          placingBuilding!.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
          rotation: placingRotation,
        );
      }
    }

    // 移动中的建筑预览
    if (movingBuilding != null && mouseGridPos != null) {
      final mb = movingBuilding!;
      final cx = mouseGridPos!.dx - (mb.building.gridWidth ~/ 2).toDouble();
      final cy = mouseGridPos!.dy - (mb.building.gridHeight ~/ 2).toDouble();

      if (mb.building.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation,
        );
      } else if (mb.building.id == DepotLoaderConfig.id ||
          mb.building.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas, mb.building, cx, cy, cellSize, 0.6,
          rotation: movingRotation,
        );
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

    // 已确认段始终使用传送带本色渲染（不论有效还是无效）
    if (conveyorConfirmedPath.isNotEmpty) {
      TransportBeltRenderer.renderConfirmedPreviewPath(
        canvas, conveyorConfirmedPath, cellSize,
        fullPathContext: fullPathContext,
      );
    }

    // 实时段根据有效/无效状态分别渲染
    if (conveyorPathInvalid) {
      // 无效状态：仅实时段标红，但是同样传入 fullPathContext 使得转弯样式能与已确认段进行平滑衔接
      if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
        TransportBeltRenderer.renderPreviewPath(
          canvas,
          conveyorPreviewPath!,
          cellSize,
          <String>{},
          isInvalid: true,
          fullPathContext: fullPathContext,
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
          fullPathContext: fullPathContext,
        );
      } else if (conveyorMode && mouseGridPos != null && conveyorConfirmedPath.isEmpty) {
        // 传送带处于尚未锚定的预备状态且当前空节点鼠标浮动时，高亮选中指示格
        TransportBeltRenderer.renderHoverHighlight(canvas, mouseGridPos!, cellSize);
      }
    }

    canvas.restore();

    // 长按圆形进度条（屏幕空间绘制）
    if (isLongPressing && longPressScreenPos != null) {
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
  void _renderBuildingStatic(Canvas canvas, PlacedBuilding pb, double cellSize, int detailLevel, Map<String, bool> portConnections) {
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
    return project != oldDelegate.project ||
        dataLoader != oldDelegate.dataLoader ||
        cellSize != oldDelegate.cellSize ||
        placingBuilding != oldDelegate.placingBuilding ||
        placingRotation != oldDelegate.placingRotation ||
        mouseGridPos != oldDelegate.mouseGridPos ||
        hoveredBuilding != oldDelegate.hoveredBuilding ||
        conveyorMode != oldDelegate.conveyorMode ||
        conveyorPathInvalid != oldDelegate.conveyorPathInvalid ||
        conveyorForkCell != oldDelegate.conveyorForkCell ||
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
