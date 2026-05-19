import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/recipe.dart';
import '../models/item.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
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

  late Ticker _ticker;
  double _displayScale = 1.0;
  double _displayOffsetX = 0;
  double _displayOffsetY = 0;
  double _targetScale = 1.0;
  double _targetOffsetX = 0;
  double _targetOffsetY = 0;
  bool _animating = false;
  double _gestureStartScale = 1.0;

  static const double _cellSize = 48.0;
  static const double _minScale = 0.25;
  static const double _maxScale = 5.0;

  ProjectState get _project => widget.project;
  set _project(ProjectState v) => widget.onProjectChanged(v);

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

    if (scaleDone && offsetXDone && offsetYDone) {
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

  Offset _screenToWorld(Offset screenPos, Size size) {
    return Offset(
      (screenPos.dx + _displayOffsetX) / _displayScale,
      (screenPos.dy + _displayOffsetY) / _displayScale,
    );
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
        _targetOffsetX -= delta.dx;
        _targetOffsetY -= delta.dy;
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

  void _handleMiddleDown(PointerDownEvent event) {
    if (event.buttons & kMiddleMouseButton != 0 && _middleDragPointerId == null) {
      _middleDragPointerId = event.pointer;
      _lastMiddlePos = event.localPosition;
      _isMiddleDragging = true;
    }
  }

  void _handleMiddleMove(PointerMoveEvent event) {
    if (event.pointer == _middleDragPointerId && _lastMiddlePos != null) {
      final delta = event.localPosition - _lastMiddlePos!;
      _targetOffsetX -= delta.dx;
      _targetOffsetY -= delta.dy;
      _displayOffsetX = _targetOffsetX;
      _displayOffsetY = _targetOffsetY;
      _lastMiddlePos = event.localPosition;
      setState(() {});
    }
  }

  void _handleMiddleUp(PointerEvent event) {
    if (event.pointer == _middleDragPointerId) {
      _middleDragPointerId = null;
      _lastMiddlePos = null;
      _isMiddleDragging = false;
    }
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
      // Don't allow clicking on occupied cells as anchors
      if (_isCellOccupied(gridPos)) {
        debugPrint('[传送带] 点击了已占用的格子 (${gridPos.dx.toInt()}, ${gridPos.dy.toInt()})，忽略');
        return;
      }

      debugPrint('[传送带] 添加锚点: (${gridPos.dx.toInt()}, ${gridPos.dy.toInt()})');

      if (_conveyorAnchors.isNotEmpty && _conveyorAnchors.last != gridPos) {
        final segment = _calculateConveyorPath(_conveyorAnchors.last, gridPos);
        if (segment.length >= 1) {
          final fullPath = <Offset>[_conveyorAnchors.last, ...segment];
          debugPrint('[传送带] 创建传送带段: ${fullPath.length} 个格子, 从 (${fullPath.first.dx.toInt()},${fullPath.first.dy.toInt()}) 到 (${fullPath.last.dx.toInt()},${fullPath.last.dy.toInt()})');
          _placeConveyorPath(fullPath);
        } else {
          debugPrint('[传送带] 路径被占用截断，无法创建传送带段');
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

      debugPrint('[传送带] 当前锚点数: ${_conveyorAnchors.length}, 已创建传送带数: ${_project.conveyors.length}');
      setState(() {});
      return;
    }
  }

  void _placeBuilding(Building building, Offset gridPos) {
    final newBuilding = PlacedBuilding(
      id: 'building_${DateTime.now().millisecondsSinceEpoch}',
      building: building,
      gridX: gridPos.dx,
      gridY: gridPos.dy,
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
    debugPrint('[传送带] 完成创建, 锚点数: ${_conveyorAnchors.length}, 总传送带数: ${_project.conveyors.length}');
    _conveyorAnchors = [];
    _conveyorPreviewPath = null;
    _conveyorPreviewOccupied = null;
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.conveyorMode && _conveyorAnchors.isNotEmpty) {
        _finishConveyor();
        return KeyEventResult.handled;
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
        onPointerDown: _handleMiddleDown,
        onPointerMove: _handleMiddleMove,
        onPointerUp: _handleMiddleUp,
        onPointerCancel: _handleMiddleUp,
        child: GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            _handleScaleUpdate(details, renderBox.size);
          },
          onScaleEnd: _handleScaleEnd,
          onTapUp: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            _handleTap(details.localPosition, renderBox.size);
            setState(() {});
          },
          onDoubleTapDown: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            _handleDoubleTap(details.localPosition, renderBox.size);
          },
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPainter = GridPainter(
      offsetX: displayOffsetX,
      offsetY: displayOffsetY,
      scale: displayScale,
      cellSize: cellSize,
    );
    gridPainter.paint(canvas, size);

    canvas.save();
    canvas.translate(-displayOffsetX, -displayOffsetY);
    canvas.scale(displayScale);

    for (final belt in project.conveyors) {
      final item = dataLoader.getItem(belt.itemId);
      ConveyorRenderer.renderConveyorPath(canvas, belt, item, cellSize);
    }

    for (final pb in project.buildings) {
      Recipe? recipe;
      if (pb.activeRecipeId != null) {
        recipe = dataLoader.getRecipe(pb.activeRecipeId!);
      }

      final portConnections = <String, bool>{};
      for (final belt in project.conveyors) {
        for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
          final portWorld = port.worldPosition(
              pb.gridX, pb.gridY, cellSize, pb.building.gridWidth, pb.building.gridHeight);
          final distStart = (belt.start - portWorld).distance;
          final distEnd = (belt.end - portWorld).distance;
          if (distStart < 30 || distEnd < 30) {
            portConnections['${port.type}_${port.index}'] = true;
          }
        }
      }

      BuildingRenderer.renderBuilding(
        canvas,
        pb.building,
        pb.gridX,
        pb.gridY,
        cellSize,
        pb.rotation,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: pb.productionProgress,
        portConnections: portConnections,
      );
    }

    if (placingBuilding != null && mouseGridPos != null) {
      BuildingRenderer.renderPlaceholder(
        canvas,
        placingBuilding!,
        mouseGridPos!.dx,
        mouseGridPos!.dy,
        cellSize,
        0.6,
      );
    }

    if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
      ConveyorRenderer.renderPreviewPath(
          canvas, conveyorPreviewPath!, cellSize, conveyorPreviewOccupied ?? <String>{});
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) => true;
}
