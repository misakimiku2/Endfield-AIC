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
import 'conveyor_renderer.dart';

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
    with SingleTickerProviderStateMixin {
  Offset? _lastFocalPoint;
  bool _isPanning = false;
  Offset? _mouseGridPos;

  List<Offset> _conveyorAnchors = [];
  List<Offset>? _conveyorPreviewPath;
  Set<String>? _conveyorPreviewOccupied;

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

  // 端口连接缓存：building id -> port key -> 是否连接
  Map<String, Map<String, bool>> _portConnectionsCache = {};

  ProjectState get _project => widget.project;
  set _project(ProjectState v) => widget.onProjectChanged(v);

  /// 重新计算所有端口连接关系（仅在数据变更时调用）
  void _rebuildPortConnectionsCache() {
    _portConnectionsCache = {};
    for (final pb in _project.buildings) {
      final connections = <String, bool>{};
      for (final belt in _project.conveyors) {
        for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
          final portWorld = port.worldPosition(
              pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
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
    _rebuildPortConnectionsCache();
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
    if (oldWidget.conveyorMode && !widget.conveyorMode) {
      _conveyorAnchors = [];
      _conveyorPreviewPath = null;
      _conveyorPreviewOccupied = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
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

    if (scaleDone && offsetXDone && offsetYDone && rotationDone) {
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

  // === Conveyor helpers ===

  bool _isCellOccupied(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in _project.conveyors) {
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return true;
      }
    }
    return false;
  }

  Set<String> _getOccupiedCellSet() {
    final cells = <String>{};
    for (final belt in _project.conveyors) {
      for (final cell in belt.path) {
        cells.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
      }
    }
    return cells;
  }

  /// Calculate L-shaped path from start to end grid cell.
  /// Truncates at the first occupied cell (exclusive).
  List<Offset> _calculateConveyorPath(Offset startGrid, Offset endGrid) {
    final sx = startGrid.dx.toInt();
    final sy = startGrid.dy.toInt();
    final ex = endGrid.dx.toInt();
    final ey = endGrid.dy.toInt();

    if (sx == ex && sy == ey) return [startGrid];

    final path = <Offset>[];

    if (sx != ex) {
      final dx = ex > sx ? 1 : -1;
      for (int x = sx + dx; ; x += dx) {
        final cell = Offset(x.toDouble(), sy.toDouble());
        if (_isCellOccupied(cell)) break;
        path.add(cell);
        if (x == ex) break;
      }
    }

    // Only add vertical segment if horizontal reached target column
    final lastX = path.isNotEmpty ? path.last.dx.toInt() : sx;
    if (lastX == ex && sy != ey) {
      final dy = ey > sy ? 1 : -1;
      for (int y = sy + dy; ; y += dy) {
        final cell = Offset(ex.toDouble(), y.toDouble());
        if (_isCellOccupied(cell)) break;
        path.add(cell);
        if (y == ey) break;
      }
    }

    return path;
  }

  /// Build preview path from last anchor to hover position.
  /// Returns the path and marks which cells are occupied (for red rendering).
  /// The starting anchor is excluded from occupied marking since it's a valid connection point.
  _PreviewPath _buildPreviewSegment(Offset lastAnchor, Offset hoverGrid) {
    if (lastAnchor == hoverGrid) {
      return _PreviewPath([lastAnchor], <String>{});
    }

    final rawPath = _calculateConveyorPathRaw(lastAnchor, hoverGrid);
    final occupied = _getOccupiedCellSet();
    final anchorKey = '${lastAnchor.dx.toInt()}_${lastAnchor.dy.toInt()}';

    final occupiedInPath = <String>{};
    for (final cell in rawPath) {
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      if (occupied.contains(key) && key != anchorKey) {
        occupiedInPath.add(key);
      }
    }

    return _PreviewPath(rawPath, occupiedInPath);
  }

  /// Raw path calculation without truncation (for preview with red cells).
  List<Offset> _calculateConveyorPathRaw(Offset startGrid, Offset endGrid) {
    final sx = startGrid.dx.toInt();
    final sy = startGrid.dy.toInt();
    final ex = endGrid.dx.toInt();
    final ey = endGrid.dy.toInt();

    if (sx == ex && sy == ey) return [startGrid];

    final path = <Offset>[startGrid];

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

  void _handleTap(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final building = widget.placingBuilding;

    if (building != null) {
      _placeBuilding(building, gridPos);
      return;
    }

    if (widget.conveyorMode) {
      if (_isCellOccupied(gridPos)) {
        return;
      }

      if (_conveyorAnchors.isNotEmpty && _conveyorAnchors.last != gridPos) {
        final segment = _calculateConveyorPath(_conveyorAnchors.last, gridPos);
        if (segment.length >= 1) {
          final fullPath = <Offset>[_conveyorAnchors.last, ...segment];
          _placeConveyorPath(fullPath);
        }
      }

      _conveyorAnchors.add(gridPos);

      if (_mouseGridPos != null) {
        final preview = _buildPreviewSegment(gridPos, _mouseGridPos!);
        _conveyorPreviewPath = preview.path;
        _conveyorPreviewOccupied = preview.occupiedKeys;
      } else {
        _conveyorPreviewPath = null;
        _conveyorPreviewOccupied = null;
      }

      setState(() {});
      return;
    }
  }

  void _placeBuilding(Building building, Offset gridPos) {
    final cx = gridPos.dx - (building.gridWidth ~/ 2).toDouble();
    final cy = gridPos.dy - (building.gridHeight ~/ 2).toDouble();
    final newBuilding = PlacedBuilding(
      id: 'building_${DateTime.now().millisecondsSinceEpoch}',
      building: building,
      gridX: cx,
      gridY: cy,
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

  void _placeConveyorPath(List<Offset> path) {
    if (path.length < 2) return;

    final belt = ConveyorBelt(
      id: 'belt_${DateTime.now().millisecondsSinceEpoch}',
      path: path,
      itemId: '',
    );

    _project.conveyors.add(belt);
    _project.offsetX = _targetOffsetX;
    _project.offsetY = _targetOffsetY;
    _project.scale = _targetScale;
    _rebuildPortConnectionsCache();
    widget.onProjectChanged(_project);
  }

  void _handleDoubleTap(Offset screenPos, Size size) {
    final gridPos = _screenToGrid(screenPos, size);
    final pb = _getBuildingAt(gridPos);
    widget.onBuildingSelected?.call(pb);
  }

  void _handleRightClick(Offset screenPos, Size size) {
    _finishConveyor();
  }

  void _finishConveyor() {
    _conveyorAnchors = [];
    _conveyorPreviewPath = null;
    _conveyorPreviewOccupied = null;
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (widget.conveyorMode && _conveyorAnchors.isNotEmpty) {
          _finishConveyor();
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
          if (_conveyorAnchors.isNotEmpty && widget.conveyorMode) {
            final preview = _buildPreviewSegment(_conveyorAnchors.last, gridPos);
            _conveyorPreviewPath = preview.path;
            _conveyorPreviewOccupied = preview.occupiedKeys;
          } else {
            _conveyorPreviewPath = null;
            _conveyorPreviewOccupied = null;
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
          // 左键：手动双击检测，单击立即响应
          if (event.buttons & kPrimaryMouseButton != 0) {
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
              // 单击 - 立即执行
              _handleTap(localPos, renderBox.size);
              _lastTapTime = now;
              _lastTapPos = localPos;
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
        },
        onPointerUp: (event) {
          if (event.pointer == _middleDragPointerId) {
            _middleDragPointerId = null;
            _lastMiddlePos = null;
            _isMiddleDragging = false;
          }
        },
        onPointerCancel: (event) {
          if (event.pointer == _middleDragPointerId) {
            _middleDragPointerId = null;
            _lastMiddlePos = null;
            _isMiddleDragging = false;
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
              mouseGridPos: _mouseGridPos,
              conveyorPreviewPath: _conveyorPreviewPath,
              conveyorPreviewOccupied: _conveyorPreviewOccupied,
              displayScale: _displayScale,
              displayOffsetX: _displayOffsetX,
              displayOffsetY: _displayOffsetY,
              displayAngle: _displayAngle,
              portConnectionsCache: _portConnectionsCache,
            ),
            size: Size.infinite,
          ),
        ),
      ),
      ),
    );
  }
}

class _PreviewPath {
  final List<Offset> path;
  final Set<String> occupiedKeys;
  _PreviewPath(this.path, this.occupiedKeys);
}

class _EditorPainter extends CustomPainter {
  final ProjectState project;
  final DataLoader dataLoader;
  final double cellSize;
  final Building? placingBuilding;
  final Offset? mouseGridPos;
  final List<Offset>? conveyorPreviewPath;
  final Set<String>? conveyorPreviewOccupied;
  final double displayScale;
  final double displayOffsetX;
  final double displayOffsetY;
  final double displayAngle;
  final Map<String, Map<String, bool>> portConnectionsCache;

  // 预渲染缓存: key = "buildingId_rotation_detailLevel_portsHash" -> Picture
  static final Map<String, ui.Picture> _pictureCache = {};
  static const int _maxCacheSize = 200;

  _EditorPainter({
    required this.project,
    required this.dataLoader,
    required this.cellSize,
    this.placingBuilding,
    this.mouseGridPos,
    this.conveyorPreviewPath,
    this.conveyorPreviewOccupied,
    required this.displayScale,
    required this.displayOffsetX,
    required this.displayOffsetY,
    required this.displayAngle,
    required this.portConnectionsCache,
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

    for (final belt in project.conveyors) {
      if (!_isBeltVisible(belt, viewport)) continue;
      final item = dataLoader.getItem(belt.itemId);
      ConveyorRenderer.renderConveyorPath(canvas, belt, item, cellSize, detailLevel: detailLevel);
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
        );
      } else if (placingBuilding!.id == DepotLoaderConfig.id ||
          placingBuilding!.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas, placingBuilding!, cx, cy, cellSize, 0.6,
        );
      }
    }

    if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
      ConveyorRenderer.renderPreviewPath(
          canvas, conveyorPreviewPath!, cellSize, conveyorPreviewOccupied ?? <String>{});
    }

    canvas.restore();
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

  /// 判断传送带是否在视口内
  bool _isBeltVisible(ConveyorBelt belt, _Viewport vp) {
    // belt.start/end 已经是世界像素坐标（含 cellSize），无需再乘
    final startX = belt.start.dx;
    final startY = belt.start.dy;
    final endX = belt.end.dx;
    final endY = belt.end.dy;
    final minX = startX < endX ? startX : endX;
    final minY = startY < endY ? startY : endY;
    final maxX = (startX > endX ? startX : endX) + cellSize;
    final maxY = (startY > endY ? startY : endY) + cellSize;
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
        mouseGridPos != oldDelegate.mouseGridPos ||
        !_listEquals(conveyorPreviewPath, oldDelegate.conveyorPreviewPath) ||
        !_setEquals(conveyorPreviewOccupied, oldDelegate.conveyorPreviewOccupied) ||
        displayScale != oldDelegate.displayScale ||
        displayOffsetX != oldDelegate.displayOffsetX ||
        displayOffsetY != oldDelegate.displayOffsetY ||
        displayAngle != oldDelegate.displayAngle;
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
