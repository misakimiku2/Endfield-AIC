import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/project.dart';
import '../../models/item.dart';
import '../../data/data_loader.dart';

class TransportBeltRenderer {
  static const double _cellMargin = 3.0;
  static const Color _beltColor = Color(0xFF555555);
  static const Color _beltHighlight = Color(0xFF777777);
  static const Color _arrowColor = Color(0xFF999999);
  static const double _particleSize = 3.0;
  static const Color _previewFillColor = Color(0x6044AAFF);
  static const Color _previewBorderColor = Color(0xAA44AAFF);
  static const Color _previewArrowColor = Color(0xDD44AAFF);
  static const Color _previewOccupiedFill = Color(0x60FF4444);
  static const Color _previewOccupiedBorder = Color(0xAAFF4444);

  static const Color _confirmedFillColor = Color(0xCC555555);
  static const Color _confirmedLineColor = Color(0xCC777777);
  static const Color _confirmedArrowColor = Color(0xCC999999);

  // SVG 缓存
  static PictureInfo? _movePicture;
  static PictureInfo? _rotatePicture;
  static PictureInfo? _moveBluePicture;
  static PictureInfo? _rotateBluePicture;
  static PictureInfo? _moveRedPicture;
  static PictureInfo? _rotateRedPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  // 物品 PNG 图片缓存（原始尺寸）
  static final Map<String, ui.Image> _itemImageCache = {};
  static final Map<String, bool> _itemImageLoading = {};

  // 物品 PNG 图片缓存（预缩放到目标渲染尺寸，key = "assetPath_targetSize"）
  static final Map<String, ui.Image> _scaledImageCache = {};

  /// 预加载指定物品的 PNG 图片
  static Future<void> preloadItemImage(String assetPath) async {
    if (_itemImageCache.containsKey(assetPath) || _itemImageLoading[assetPath] == true) return;
    _itemImageLoading[assetPath] = true;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _itemImageCache[assetPath] = frame.image;
    } catch (_) {} finally {
      _itemImageLoading[assetPath] = false;
    }
  }

  /// 批量预加载所有物品图片，并生成预缩放缓存
  static Future<void> preloadAllItemImages(DataLoader dataLoader) async {
    final futures = <Future<void>>[];
    for (final item in dataLoader.items.values) {
      if (item.imageAssetPath.isNotEmpty) {
        futures.add(preloadItemImage(item.imageAssetPath));
      }
    }
    await Future.wait(futures);
    // 生成预缩放缓存（cellSize = 48.0，itemSize = 24.0）
    _generateScaledCache(48.0);
  }

  /// 生成预缩放图片缓存
  static void _generateScaledCache(double cellSize) {
    final targetSize = (cellSize * 0.5).toInt();
    for (final entry in _itemImageCache.entries) {
      final cacheKey = '${entry.key}_$targetSize';
      if (_scaledImageCache.containsKey(cacheKey)) continue;
      final srcImage = entry.value;
      // 使用 PictureRecorder 预渲染缩放后的图片
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final scale = targetSize / srcImage.width;
      canvas.scale(scale, scale);
      canvas.drawImage(srcImage, Offset.zero, Paint());
      final picture = recorder.endRecording();
      // 将 Picture 转换为 Image（异步但在此处用同步方式）
      _scaledImageCache[cacheKey] = picture.toImageSync(targetSize, targetSize);
    }
  }

  /// 检测是否是输出端口 (output)
  static bool isOutputPort(Offset gridPos, List<PlacedBuilding> buildings) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();
    for (final pb in buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in pb.outputPorts) {
        final portGrid = port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portGrid.dx.round() == gx && portGrid.dy.round() == gy) {
          return true;
        }
      }
    }
    return false;
  }

  /// 检测是否是输入端口 (input)
  static bool isInputPort(Offset gridPos, List<PlacedBuilding> buildings) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();
    for (final pb in buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in pb.inputPorts) {
        final portGrid = port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portGrid.dx.round() == gx && portGrid.dy.round() == gy) {
          return true;
        }
      }
    }
    return false;
  }

  /// 获取以单元格中心 (0,0) 为原点时的裁剪 Rect。
  /// 如果不需要裁剪，返回 null。
  static Rect? getLocalClipRect({
    required List<Offset> path,
    required int index,
    required double cellSize,
    required List<PlacedBuilding>? buildings,
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
  }) {
    if (buildings == null) return null;

    // 确定当前这一格在传送带完整上下文中的位置和完整路径
    List<Offset> actualPath = path;
    int actualIndex = index;
    if (fullPathContext != null) {
      actualPath = fullPathContext;
      actualIndex = contextStartIndex + index;
    }

    if (actualPath.isEmpty) return null;

    final cell = actualPath[actualIndex];

    // 情况 1：起点，且是 Output 端口
    if (actualIndex == 0) {
      if (isOutputPort(cell, buildings)) {
        final dir = _getCellDirection(actualPath, actualIndex);
        final half = cellSize / 2;
        switch (dir) {
          case 'right':
            return Rect.fromLTRB(0, -half, half, half);
          case 'left':
            return Rect.fromLTRB(-half, -half, 0, half);
          case 'down':
            return Rect.fromLTRB(-half, 0, half, half);
          case 'up':
            return Rect.fromLTRB(-half, -half, half, 0);
        }
      }
    }

    // 情况 2：终点，且是 Input 端口
    if (actualIndex == actualPath.length - 1) {
      if (isInputPort(cell, buildings)) {
        final dir = _getCellDirection(actualPath, actualIndex);
        final half = cellSize / 2;
        switch (dir) {
          case 'right':
            return Rect.fromLTRB(-half, -half, 0, half);
          case 'left':
            return Rect.fromLTRB(0, -half, half, half);
          case 'down':
            return Rect.fromLTRB(-half, -half, half, 0);
          case 'up':
            return Rect.fromLTRB(-half, 0, half, half);
        }
      }
    }

    return null;
  }

  /// 判断粒子是否需要过滤（在缩小的两个首位单元格里排除掉朝内部流动的半段）
  static bool _shouldDiscardParticle(
    Offset particlePos,
    List<Offset> path,
    double cellSize,
    List<PlacedBuilding> buildings,
  ) {
    if (path.length < 2) return false;

    // 1. 判断是否在第一格 (起点/输出端)
    final firstCell = path.first;
    final fcx = firstCell.dx * cellSize + cellSize / 2;
    final fcy = firstCell.dy * cellSize + cellSize / 2;
    if ((particlePos.dx - fcx).abs() <= cellSize / 2 &&
        (particlePos.dy - fcy).abs() <= cellSize / 2) {
      if (isOutputPort(firstCell, buildings)) {
        final dir = _getCellDirection(path, 0);
        switch (dir) {
          case 'right':
            return particlePos.dx < fcx;
          case 'left':
            return particlePos.dx > fcx;
          case 'down':
            return particlePos.dy < fcy;
          case 'up':
            return particlePos.dy > fcy;
        }
      }
    }

    // 2. 判断是否在最后一格 (终点/输入端)
    final lastCell = path.last;
    final lcx = lastCell.dx * cellSize + cellSize / 2;
    final lcy = lastCell.dy * cellSize + cellSize / 2;
    if ((particlePos.dx - lcx).abs() <= cellSize / 2 &&
        (particlePos.dy - lcy).abs() <= cellSize / 2) {
      if (isInputPort(lastCell, buildings)) {
        final dir = _getCellDirection(path, path.length - 1);
        switch (dir) {
          case 'right':
            return particlePos.dx > lcx;
          case 'left':
            return particlePos.dx < lcx;
          case 'down':
            return particlePos.dy > lcy;
          case 'up':
            return particlePos.dy < lcy;
        }
      }
    }

    return false;
  }

  /// 预加载传送带 SVG 资源并生成预览资源
  static Future<void> init() async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // 1. 加载原始 SVG 字符串
      final moveStr = await rootBundle.loadString('assets/svg/Transport_Belt_Move.svg');
      final rotateStr = await rootBundle.loadString('assets/svg/Transport_Belt_rotate.svg');

      // 2. 生成蓝色预览 SVG 字符串
      final moveBlueStr = _makePreviewSvg(moveStr, '#44AAFF');
      final rotateBlueStr = _makePreviewSvg(rotateStr, '#44AAFF');

      // 3. 生成红色预览 SVG 字符串
      final moveRedStr = _makePreviewSvg(moveStr, '#FF4444');
      final rotateRedStr = _makePreviewSvg(rotateStr, '#FF4444');

      final results = await Future.wait([
        vg.loadPicture(const SvgAssetLoader('assets/svg/Transport_Belt_Move.svg'), null),
        vg.loadPicture(const SvgAssetLoader('assets/svg/Transport_Belt_rotate.svg'), null),
        vg.loadPicture(SvgStringLoader(moveBlueStr), null),
        vg.loadPicture(SvgStringLoader(rotateBlueStr), null),
        vg.loadPicture(SvgStringLoader(moveRedStr), null),
        vg.loadPicture(SvgStringLoader(rotateRedStr), null),
      ]);

      _movePicture = results[0];
      _rotatePicture = results[1];
      _moveBluePicture = results[2];
      _rotateBluePicture = results[3];
      _moveRedPicture = results[4];
      _rotateRedPicture = results[5];
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to load conveyor belt SVGs: $e');
    } finally {
      _initializing = false;
    }
  }

  static String _makePreviewSvg(String original, String hexColor) {
    return original
        .replaceAll('#ffef00', hexColor) // 黄色带身 -> 预览色 (蓝/红)
        .replaceAll('#cecccc', hexColor) // 灰色边框 -> 预览色 (蓝/红)
        .replaceAll('#8c8c8c', '#FFFFFF'); // 灰色箭头 -> 白色
  }

  static bool get isReady =>
      _initialized &&
      _movePicture != null &&
      _rotatePicture != null &&
      _moveBluePicture != null &&
      _rotateBluePicture != null &&
      _moveRedPicture != null &&
      _rotateRedPicture != null;

  // 方向索引：up=0, right=1, down=2, left=3
  static const int _dirUp = 0;
  static const int _dirRight = 1;
  static const int _dirDown = 2;
  static const int _dirLeft = 3;

  static int _directionToIndex(String direction) {
    switch (direction) {
      case 'up':
        return _dirUp;
      case 'right':
        return _dirRight;
      case 'down':
        return _dirDown;
      case 'left':
        return _dirLeft;
      default:
        return _dirRight;
    }
  }

  /// 方向对应的角度（弧度），right=0, down=π/2, left=π, up=3π/2
  static double _directionAngle(String direction) {
    switch (direction) {
      case 'right':
        return 0;
      case 'down':
        return math.pi / 2;
      case 'left':
        return math.pi;
      case 'up':
        return 3 * math.pi / 2;
      default:
        return 0;
    }
  }

  static String _offsetToDirection(double dx, double dy) {
    if (dx > 0) return 'right';
    if (dx < 0) return 'left';
    if (dy > 0) return 'down';
    return 'up';
  }

  /// 判断格子是直线段还是转弯点
  /// 返回 (isTurn, incomingDir, outgoingDir, isCounterClockwise)
  static (bool, String, String, bool) _getCellTurnInfo(
      List<Offset> path, int index, {String? incomingDirection}) {
    if (index == 0) {
      // 首格：如果有 incomingDirection，用它作为入方向
      if (incomingDirection != null && index < path.length - 1) {
        final nextDx = path[index + 1].dx - path[index].dx;
        final nextDy = path[index + 1].dy - path[index].dy;
        final outgoingDir = _offsetToDirection(nextDx, nextDy);
        if (incomingDirection == outgoingDir) {
          return (false, incomingDirection, outgoingDir, false);
        }
        final inIdx = _directionToIndex(incomingDirection);
        final outIdx = _directionToIndex(outgoingDir);
        final diff = (outIdx - inIdx + 4) % 4;
        final isCCW = diff == 3;
        return (true, incomingDirection, outgoingDir, isCCW);
      }
      final dir = _getCellDirection(path, index);
      return (false, dir, dir, false);
    }
    if (index == path.length - 1) {
      final dir = _getCellDirection(path, index);
      return (false, dir, dir, false);
    }

    final prevDx = path[index].dx - path[index - 1].dx;
    final prevDy = path[index].dy - path[index - 1].dy;
    final nextDx = path[index + 1].dx - path[index].dx;
    final nextDy = path[index + 1].dy - path[index].dy;

    final incomingDir = _offsetToDirection(prevDx, prevDy);
    final outgoingDir = _offsetToDirection(nextDx, nextDy);

    if (incomingDir == outgoingDir) {
      return (false, incomingDir, outgoingDir, false);
    }

    // 判断是顺时针转弯还是逆时针转弯
    final inIdx = _directionToIndex(incomingDir);
    final outIdx = _directionToIndex(outgoingDir);
    final diff = (outIdx - inIdx + 4) % 4;
    final isCCW = diff == 3; // 逆时针

    return (true, incomingDir, outgoingDir, isCCW);
  }

  static void renderConveyorPath(
    Canvas canvas,
    ConveyorBelt belt,
    Item? item,
    double cellSize,
    List<PlacedBuilding> buildings, {
    int detailLevel = 2,
    DataLoader? dataLoader,
  }) {
    if (belt.path.isEmpty) return;

    if (isReady) {
      _renderWithSvg(canvas, belt.path, cellSize, buildings, forcedDirection: belt.forcedDirection, incomingDirection: belt.incomingDirection);
    } else {
      for (int i = 0; i < belt.path.length; i++) {
        final cell = belt.path[i];
        final direction = _getCellDirection(belt.path, i, forcedDirection: belt.forcedDirection);
        final cx = cell.dx * cellSize + cellSize / 2;
        final cy = cell.dy * cellSize + cellSize / 2;
        final localClip = getLocalClipRect(
          path: belt.path,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
        );

        if (localClip != null) {
          canvas.save();
          canvas.clipRect(localClip.shift(Offset(cx, cy)));
          _drawConveyorCell(canvas, cell, direction, cellSize, _beltColor,
              _beltHighlight, _arrowColor,
              detailLevel: detailLevel);
          canvas.restore();
        } else {
          _drawConveyorCell(canvas, cell, direction, cellSize, _beltColor,
              _beltHighlight, _arrowColor,
              detailLevel: detailLevel);
        }
      }
    }

    // 渲染传送带上的物品
    if (belt.items.isNotEmpty) {
      _renderItems(canvas, belt, cellSize, buildings, dataLoader);
    }

    if (belt.isBlocked && belt.path.isNotEmpty) {
      _renderBlockedIndicator(canvas, belt.path.last, cellSize);
    }
  }

  /// 使用 SVG 图标渲染传送带路径
  static void _renderWithSvg(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    List<PlacedBuilding> buildings, {
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
    String? forcedDirection,
    String? incomingDirection,
  }) {
    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final cx = cell.dx * cellSize + cellSize / 2;
      final cy = cell.dy * cellSize + cellSize / 2;

      canvas.save();
      canvas.translate(cx, cy);

      final clip = getLocalClipRect(
        path: path,
        index: i,
        cellSize: cellSize,
        buildings: buildings,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
      );
      if (clip != null) {
        canvas.clipRect(clip);
      }

      _drawSvgCellAtOrigin(
        canvas, path, i, cellSize,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
      );
      canvas.restore();
    }
  }

  static void _drawConveyorCell(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color fillColor,
    Color lineColor,
    Color arrowColor, {
    int detailLevel = 2,
  }) {
    final x = cell.dx * cellSize + _cellMargin;
    final y = cell.dy * cellSize + _cellMargin;
    final w = cellSize - _cellMargin * 2;
    final h = cellSize - _cellMargin * 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(3.0),
    );

    canvas.drawRRect(rect, Paint()..color = fillColor);

    if (detailLevel >= 1) {
      _drawCenterLine(canvas, cell, direction, cellSize, lineColor);
      _drawArrow(canvas, cell, direction, cellSize, arrowColor);
    }
  }

  static void _drawCenterLine(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color color,
  ) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final halfLen = cellSize / 2 - _cellMargin - 4;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    Offset start, end;
    switch (direction) {
      case 'right':
        start = Offset(cx - halfLen, cy);
        end = Offset(cx + halfLen, cy);
        break;
      case 'left':
        start = Offset(cx + halfLen, cy);
        end = Offset(cx - halfLen, cy);
        break;
      case 'down':
        start = Offset(cx, cy - halfLen);
        end = Offset(cx, cy + halfLen);
        break;
      case 'up':
        start = Offset(cx, cy + halfLen);
        end = Offset(cx, cy - halfLen);
        break;
      default:
        start = Offset(cx - halfLen, cy);
        end = Offset(cx + halfLen, cy);
    }

    canvas.drawLine(start, end, paint);
  }

  static void _drawArrow(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color color,
  ) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    const arrowSize = 5.0;

    final paint = Paint()..color = color;

    Offset p1, p2, p3;
    switch (direction) {
      case 'right':
        p1 = Offset(cx + arrowSize, cy);
        p2 = Offset(cx - arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx - arrowSize * 0.4, cy + arrowSize * 0.8);
        break;
      case 'left':
        p1 = Offset(cx - arrowSize, cy);
        p2 = Offset(cx + arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx + arrowSize * 0.4, cy + arrowSize * 0.8);
        break;
      case 'down':
        p1 = Offset(cx, cy + arrowSize);
        p2 = Offset(cx - arrowSize * 0.8, cy - arrowSize * 0.4);
        p3 = Offset(cx + arrowSize * 0.8, cy - arrowSize * 0.4);
        break;
      case 'up':
        p1 = Offset(cx, cy - arrowSize);
        p2 = Offset(cx - arrowSize * 0.8, cy + arrowSize * 0.4);
        p3 = Offset(cx + arrowSize * 0.8, cy + arrowSize * 0.4);
        break;
      default:
        p1 = Offset(cx + arrowSize, cy);
        p2 = Offset(cx - arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx - arrowSize * 0.4, cy + arrowSize * 0.8);
    }

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static String _getCellDirection(List<Offset> path, int index, {String? forcedDirection}) {
    if (forcedDirection != null && path.length == 1) return forcedDirection;
    if (index < path.length - 1) {
      final dx = path[index + 1].dx - path[index].dx;
      final dy = path[index + 1].dy - path[index].dy;
      if (dx > 0) return 'right';
      if (dx < 0) return 'left';
      if (dy > 0) return 'down';
      if (dy < 0) return 'up';
    }
    if (index > 0) {
      final dx = path[index].dx - path[index - 1].dx;
      final dy = path[index].dy - path[index - 1].dy;
      if (dx > 0) return 'right';
      if (dx < 0) return 'left';
      if (dy > 0) return 'down';
      if (dy < 0) return 'up';
    }
    return 'right';
  }

  /// 渲染传送带上的物品图标
  static void _renderItems(
    Canvas canvas,
    ConveyorBelt belt,
    double cellSize,
    List<PlacedBuilding> buildings,
    DataLoader? dataLoader,
  ) {
    final itemSize = (cellSize * 0.5).toInt();
    final halfSize = itemSize / 2.0;

    for (final conveyorItem in belt.items) {
      final pos = _getPositionFromGridUnits(belt.path, conveyorItem.position, cellSize);

      final item = dataLoader?.getItem(conveyorItem.itemId);

      // 优先使用预缩放图片缓存
      if (item != null && item.imageAssetPath.isNotEmpty) {
        final cacheKey = '${item.imageAssetPath}_$itemSize';
        final scaledImage = _scaledImageCache[cacheKey];
        if (scaledImage != null) {
          canvas.drawImage(scaledImage, Offset(pos.dx - halfSize, pos.dy - halfSize), Paint());
          continue;
        }

        // 回退到原始缓存（需要 scale 变换）
        final cachedImage = _itemImageCache[item.imageAssetPath];
        if (cachedImage != null) {
          final srcSize = cachedImage.width.toDouble();
          final scale = itemSize / srcSize;
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.scale(scale, scale);
          canvas.drawImage(cachedImage, Offset(-srcSize / 2, -srcSize / 2), Paint());
          canvas.restore();
          continue;
        }
      }

      // 最终回退：使用颜色圆形
      final color = item?.color ?? const Color(0xFFAAAAAA);
      canvas.drawCircle(pos, halfSize, Paint()..color = color);
    }
  }

  /// 根据网格单位位置计算世界坐标
  /// position 为格数单位，0=路径起点，path.length-1=路径终点
  static Offset _getPositionFromGridUnits(
      List<Offset> path, double gridPosition, double cellSize) {
    if (path.isEmpty) return Offset.zero;
    if (path.length == 1) {
      return Offset(
        path[0].dx * cellSize + cellSize / 2,
        path[0].dy * cellSize + cellSize / 2,
      );
    }

    int segmentIndex = gridPosition.floor();
    if (segmentIndex >= path.length - 1) segmentIndex = path.length - 2;
    if (segmentIndex < 0) segmentIndex = 0;

    final t = gridPosition - segmentIndex;
    final from = path[segmentIndex];
    final to = path[segmentIndex + 1];

    return Offset(
      (from.dx + (to.dx - from.dx) * t) * cellSize + cellSize / 2,
      (from.dy + (to.dy - from.dy) * t) * cellSize + cellSize / 2,
    );
  }

  static void _renderBlockedIndicator(Canvas canvas, Offset cell, double cellSize) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final pos = Offset(cx, cy);

    canvas.drawCircle(pos, _particleSize * 2, Paint()..color = const Color(0xFFFF3333));

    final crossPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.5;
    const s = _particleSize;
    canvas.drawLine(
      Offset(pos.dx - s, pos.dy - s),
      Offset(pos.dx + s, pos.dy + s),
      crossPaint,
    );
    canvas.drawLine(
      Offset(pos.dx + s, pos.dy - s),
      Offset(pos.dx - s, pos.dy + s),
      crossPaint,
    );
  }

  static void renderPreviewPath(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    Set<String> occupiedKeys,
    List<PlacedBuilding> buildings, {
    bool isInvalid = false,
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
  }) {
    if (path.isEmpty) return;

    if (isReady) {
      _renderPreviewWithSvg(canvas, path, cellSize, occupiedKeys, buildings, isInvalid: isInvalid, fullPathContext: fullPathContext, contextStartIndex: contextStartIndex);
    } else {
      _renderPreviewLegacy(canvas, path, cellSize, occupiedKeys, buildings, isInvalid: isInvalid);
    }
  }

  /// 判断是否是转弯点
  static bool _isTurn(List<Offset> path, int index, {String? incomingDirection}) {
    if (index == 0) {
      // 首格：如果有 incomingDirection 且路径有后继，检查入方向与出方向是否不同
      if (incomingDirection != null && index < path.length - 1) {
        final nextDx = path[index + 1].dx - path[index].dx;
        final nextDy = path[index + 1].dy - path[index].dy;
        final outgoingDir = _offsetToDirection(nextDx, nextDy);
        return incomingDirection != outgoingDir;
      }
      return false;
    }
    if (index == path.length - 1) return false;
    final prevDx = path[index].dx - path[index - 1].dx;
    final prevDy = path[index].dy - path[index - 1].dy;
    final nextDx = path[index + 1].dx - path[index].dx;
    final nextDy = path[index + 1].dy - path[index].dy;
    final incomingDir = _offsetToDirection(prevDx, prevDy);
    final outgoingDir = _offsetToDirection(nextDx, nextDy);
    return incomingDir != outgoingDir;
  }

  /// 获取对应的 SVG 画卷
  static PictureInfo _getPicture({bool isTurn = false, bool isBlue = false, bool isRed = false}) {
    if (isTurn) {
      if (isBlue) return _rotateBluePicture!;
      if (isRed) return _rotateRedPicture!;
      return _rotatePicture!;
    } else {
      if (isBlue) return _moveBluePicture!;
      if (isRed) return _moveRedPicture!;
      return _movePicture!;
    }
  }

  /// 使用 SVG 渲染蓝色或红色预览路径
  static void _renderPreviewWithSvg(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    Set<String> occupiedKeys,
    List<PlacedBuilding> buildings, {
    bool isInvalid = false,
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
  }) {
    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      final isOccupied = isInvalid || occupiedKeys.contains(key);

      final cx = cell.dx * cellSize + cellSize / 2;
      final cy = cell.dy * cellSize + cellSize / 2;

      canvas.save();
      canvas.translate(cx, cy);

      // 预览时应用 60% 透明度 (0x99FFFFFF)
      canvas.saveLayer(null, Paint()..color = const Color(0x99FFFFFF));

      final clip = getLocalClipRect(
        path: path,
        index: i,
        cellSize: cellSize,
        buildings: buildings,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
      );
      if (clip != null) {
        canvas.clipRect(clip);
      }

      _drawSvgCellAtOrigin(
        canvas,
        path,
        i,
        cellSize,
        isPreview: true,
        isOccupied: isOccupied,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
      );
      canvas.restore();

      canvas.restore();
    }
  }

  /// 在原点绘制单个 SVG 单元格（供预览等复用）
  static void _drawSvgCellAtOrigin(
    Canvas canvas,
    List<Offset> path,
    int index,
    double cellSize, {
    bool isPreview = false,
    bool isOccupied = false,
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
    String? forcedDirection,
    String? incomingDirection,
  }) {
    // 确定用于转弯检测的路径 and 索引
    List<Offset> turnPath = path;
    int turnIndex = index;

    if (fullPathContext != null) {
      turnPath = fullPathContext;
      turnIndex = contextStartIndex + index;
    }

    final turn = _isTurn(turnPath, turnIndex, incomingDirection: incomingDirection);
    final PictureInfo picture;
    if (isPreview) {
      if (isOccupied) {
        picture = _getPicture(isTurn: turn, isRed: true);
      } else {
        picture = _getPicture(isTurn: turn, isBlue: true);
      }
    } else {
      picture = _getPicture(isTurn: turn);
    }

    final svgSize = picture.size;
    final scaleX = cellSize / svgSize.width;
    final scaleY = cellSize / svgSize.height;

    final (isTurn, _, outgoingDir, isCCW) =
        _getCellTurnInfo(turnPath, turnIndex, incomingDirection: incomingDirection);

    if (isTurn) {
      double rotation;
      bool mirrorH;

      if (isCCW) {
        final outAngle = _directionAngle(outgoingDir);
        rotation = (outAngle - math.pi + 2 * math.pi) % (2 * math.pi);
        mirrorH = true;
      } else {
        rotation = _directionAngle(outgoingDir);
        mirrorH = false;
      }

      // 关键修复：先进行旋转，再进行水平镜像
      canvas.rotate(rotation);
      if (mirrorH) {
        canvas.scale(-1, 1);
      }
      canvas.scale(scaleX, scaleY);
      canvas.translate(-svgSize.width / 2, -svgSize.height / 2);
      canvas.drawPicture(picture.picture);
    } else {
      final direction = _getCellDirection(turnPath, turnIndex, forcedDirection: forcedDirection);
      final dirIdx = _directionToIndex(direction);
      final rotation = dirIdx * math.pi / 2;

      canvas.rotate(rotation);
      canvas.scale(scaleX, scaleY);
      canvas.translate(-svgSize.width / 2, -svgSize.height / 2);
      canvas.drawPicture(picture.picture);
    }
  }

  /// 旧版圆角矩形预览（SVG 未加载时的回退）
  static void _renderPreviewLegacy(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    Set<String> occupiedKeys,
    List<PlacedBuilding> buildings, {
    bool isInvalid = false,
  }) {
    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      final isOccupied = isInvalid || occupiedKeys.contains(key);

      final cx = cell.dx * cellSize + cellSize / 2;
      final cy = cell.dy * cellSize + cellSize / 2;

      final x = cell.dx * cellSize + _cellMargin;
      final y = cell.dy * cellSize + _cellMargin;
      final w = cellSize - _cellMargin * 2;
      final h = cellSize - _cellMargin * 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(3.0),
      );

      final localClip = getLocalClipRect(
        path: path,
        index: i,
        cellSize: cellSize,
        buildings: buildings,
      );

      if (localClip != null) {
        canvas.save();
        canvas.clipRect(localClip.shift(Offset(cx, cy)));
        canvas.drawRRect(rect, Paint()..color = isOccupied ? _previewOccupiedFill : _previewFillColor);
        canvas.drawRRect(
            rect,
            Paint()
              ..color = isOccupied ? _previewOccupiedBorder : _previewBorderColor
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke);

        if (path.length >= 2 && !isOccupied) {
          final direction = _getCellDirection(path, i);
          _drawArrow(canvas, cell, direction, cellSize, _previewArrowColor);
        }
        canvas.restore();
      } else {
        canvas.drawRRect(rect, Paint()..color = isOccupied ? _previewOccupiedFill : _previewFillColor);
        canvas.drawRRect(
            rect,
            Paint()
              ..color = isOccupied ? _previewOccupiedBorder : _previewBorderColor
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke);

        if (path.length >= 2 && !isOccupied) {
          final direction = _getCellDirection(path, i);
          _drawArrow(canvas, cell, direction, cellSize, _previewArrowColor);
        }
      }
    }
  }

  /// 渲染传送带路径中被阻拦的格子为红色传送带预览
  /// 用于设备创建/移动时，遇到传送带的阻拦叠加显示
  static void renderBlockedBeltCells(
    Canvas canvas,
    List<Offset> beltPath,
    double cellSize,
    Set<String> blockedKeys,
    List<PlacedBuilding> buildings, {
    String? incomingDirection,
  }) {
    if (beltPath.isEmpty) return;

    if (isReady) {
      for (int i = 0; i < beltPath.length; i++) {
        final cell = beltPath[i];
        final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
        if (!blockedKeys.contains(key)) continue;

        final cx = cell.dx * cellSize + cellSize / 2;
        final cy = cell.dy * cellSize + cellSize / 2;

        canvas.save();
        canvas.translate(cx, cy);
        canvas.saveLayer(null, Paint()..color = const Color(0x99FFFFFF));

        final clip = getLocalClipRect(
          path: beltPath,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
        );
        if (clip != null) {
          canvas.clipRect(clip);
        }

        _drawSvgCellAtOrigin(
          canvas,
          beltPath,
          i,
          cellSize,
          isPreview: true,
          isOccupied: true,
          incomingDirection: incomingDirection,
        );
        canvas.restore();
        canvas.restore();
      }
    } else {
      // SVG 未加载时回退到旧版红色圆角矩形
      for (int i = 0; i < beltPath.length; i++) {
        final cell = beltPath[i];
        final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
        if (!blockedKeys.contains(key)) continue;

        final x = cell.dx * cellSize + _cellMargin;
        final y = cell.dy * cellSize + _cellMargin;
        final w = cellSize - _cellMargin * 2;
        final h = cellSize - _cellMargin * 2;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(3.0),
        );

        canvas.drawRRect(rect, Paint()..color = _previewOccupiedFill);
        canvas.drawRRect(
          rect,
          Paint()
            ..color = _previewOccupiedBorder
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  static void renderHoverHighlight(Canvas canvas, Offset gridPos, double cellSize) {
    final x = gridPos.dx * cellSize + _cellMargin;
    final y = gridPos.dy * cellSize + _cellMargin;
    final w = cellSize - _cellMargin * 2;
    final h = cellSize - _cellMargin * 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(3.0),
    );

    canvas.drawRRect(rect, Paint()..color = const Color(0x2544AAFF));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0x7744AAFF)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  /// 渲染已确认的传送带段（非实时预览部分），使用传送带本色但稍带透明
  static void renderConfirmedPreviewPath(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    List<PlacedBuilding> buildings, {
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
    String? forcedDirection,
    String? incomingDirection,
  }) {
    if (path.isEmpty) return;

    if (isReady) {
      // 使用 SVG 渲染，通过 saveLayer 降低透明度
      canvas.saveLayer(null, Paint()..color = const Color(0xCCFFFFFF));
      _renderWithSvg(canvas, path, cellSize, buildings, fullPathContext: fullPathContext, contextStartIndex: contextStartIndex, forcedDirection: forcedDirection, incomingDirection: incomingDirection);
      canvas.restore();
    } else {
      for (int i = 0; i < path.length; i++) {
        final cell = path[i];
        final direction = _getCellDirection(path, i, forcedDirection: forcedDirection);
        final cx = cell.dx * cellSize + cellSize / 2;
        final cy = cell.dy * cellSize + cellSize / 2;

        final localClip = getLocalClipRect(
          path: path,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
        );

        if (localClip != null) {
          canvas.save();
          canvas.clipRect(localClip.shift(Offset(cx, cy)));
          _drawConveyorCell(
            canvas, path[i], direction, cellSize,
            _confirmedFillColor, _confirmedLineColor, _confirmedArrowColor,
          );
          canvas.restore();
        } else {
          _drawConveyorCell(
            canvas, path[i], direction, cellSize,
            _confirmedFillColor, _confirmedLineColor, _confirmedArrowColor,
          );
        }
      }
    }
  }
}
