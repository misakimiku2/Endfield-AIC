import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/project.dart';
import '../../models/item.dart';
import '../../constants/app_constants.dart';

class TransportBeltRenderer {
  static const double _cellMargin = 3.0;
  static const Color _beltColor = Color(0xFF555555);
  static const Color _beltHighlight = Color(0xFF777777);
  static const Color _arrowColor = Color(0xFF999999);
  static const double _particleSize = 3.0;
  static const double _particleSpacing = 16.0;
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
  static PictureInfo? _pointerPicture;
  static PictureInfo? _previewPointerPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  // 物品 PNG 图片缓存
  static final Map<String, ui.Image> _itemImageCache = {};
  static final Set<String> _itemImageLoading = {};
  static VoidCallback? onItemImageReady;

  /// 检测是否是输出端口 (output)
  /// 对1x1建筑（如分流器），端口坐标在格边缘，需补检建筑占据范围。
  static bool isOutputPort(Offset gridPos, List<PlacedBuilding> buildings) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();
    for (final pb in buildings) {
      // 先检查精确端口坐标
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in pb.outputPorts) {
        final portGrid =
            port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portGrid.dx.round() == gx && portGrid.dy.round() == gy) {
          return true;
        }
      }
      // 1x1补检：若建筑占据此格且有输出端口，视为输出端口格
      if (pb.outputPorts.isNotEmpty) {
        final bx = pb.effectiveGridX.toInt();
        final by = pb.effectiveGridY.toInt();
        if (gx >= bx &&
            gx < bx + pb.effectiveWidth &&
            gy >= by &&
            gy < by + pb.effectiveHeight) {
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
        final portGrid =
            port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portGrid.dx.round() == gx && portGrid.dy.round() == gy) {
          return true;
        }
      }
      // 1x1补检：若建筑占据此格且有输入端口，视为输入端口格
      if (pb.inputPorts.isNotEmpty) {
        final bx = pb.effectiveGridX.toInt();
        final by = pb.effectiveGridY.toInt();
        if (gx >= bx &&
            gx < bx + pb.effectiveWidth &&
            gy >= by &&
            gy < by + pb.effectiveHeight) {
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
    String? forcedDirection,
    String? incomingDirection,
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

    double clipLeft = -10000;
    double clipRight = 10000;
    double clipTop = -10000;
    double clipBottom = 10000;
    final half = cellSize / 2;

    // 情况 1：起点 — 裁剪入方向的反侧
    if (actualIndex == 0) {
      // 优先使用 incomingDirection（转角首格），否则从路径推断出方向再取反侧
      final dir =
          incomingDirection ?? _getCellDirection(actualPath, actualIndex);
      final isPort = isOutputPort(cell, buildings);
      switch (dir) {
        case 'right':
          clipLeft = isPort ? 0 : -half;
          break;
        case 'left':
          clipRight = isPort ? 0 : half;
          break;
        case 'down':
          clipTop = isPort ? 0 : -half;
          break;
        case 'up':
          clipBottom = isPort ? 0 : half;
          break;
      }
    }

    // 情况 2：终点 — 裁剪出方向侧
    if (actualIndex == actualPath.length - 1) {
      // 优先使用 forcedDirection（转角末格的出方向），否则从路径推断
      final dir = forcedDirection ?? _getCellDirection(actualPath, actualIndex);
      final isPort = isInputPort(cell, buildings);
      switch (dir) {
        case 'right':
          clipRight = isPort ? 0 : half;
          break;
        case 'left':
          clipLeft = isPort ? 0 : -half;
          break;
        case 'down':
          clipBottom = isPort ? 0 : half;
          break;
        case 'up':
          clipTop = isPort ? 0 : -half;
          break;
      }
    }

    if (clipLeft == -10000 &&
        clipRight == 10000 &&
        clipTop == -10000 &&
        clipBottom == 10000) {
      return null;
    }

    return Rect.fromLTRB(
      clipLeft == -10000 ? -cellSize * 2 : clipLeft,
      clipTop == -10000 ? -cellSize * 2 : clipTop,
      clipRight == 10000 ? cellSize * 2 : clipRight,
      clipBottom == 10000 ? cellSize * 2 : clipBottom,
    );
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
      final moveStr =
          await rootBundle.loadString('assets/svg/Transport_Belt_Move.svg');
      final rotateStr =
          await rootBundle.loadString('assets/svg/Transport_Belt_rotate.svg');
      final pointerStr = await rootBundle.loadString('assets/svg/pointer.svg');

      // 2. 生成蓝色预览 SVG 字符串
      final moveBlueStr = _makePreviewSvg(moveStr, '#44AAFF');
      final rotateBlueStr = _makePreviewSvg(rotateStr, '#44AAFF');

      // 3. 生成红色预览 SVG 字符串
      final moveRedStr = _makePreviewSvg(moveStr, '#FF4444');
      final rotateRedStr = _makePreviewSvg(rotateStr, '#FF4444');
      final pointerPreviewStr = pointerStr.replaceAll('#dfb615', '#555555');

      final results = await Future.wait([
        vg.loadPicture(
            const SvgAssetLoader('assets/svg/Transport_Belt_Move.svg'), null),
        vg.loadPicture(
            const SvgAssetLoader('assets/svg/Transport_Belt_rotate.svg'), null),
        vg.loadPicture(SvgStringLoader(moveBlueStr), null),
        vg.loadPicture(SvgStringLoader(rotateBlueStr), null),
        vg.loadPicture(SvgStringLoader(moveRedStr), null),
        vg.loadPicture(SvgStringLoader(rotateRedStr), null),
        vg.loadPicture(const SvgAssetLoader('assets/svg/pointer.svg'), null),
        vg.loadPicture(SvgStringLoader(pointerPreviewStr), null),
      ]);

      _movePicture = results[0];
      _rotatePicture = results[1];
      _moveBluePicture = results[2];
      _rotateBluePicture = results[3];
      _moveRedPicture = results[4];
      _rotateRedPicture = results[5];
      _pointerPicture = results[6];
      _previewPointerPicture = results[7];
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

  /// 异步加载物品 PNG 图片并缓存
  static Future<void> _loadItemImage(String assetPath) async {
    if (_itemImageCache.containsKey(assetPath) ||
        _itemImageLoading.contains(assetPath)) {
      return;
    }
    _itemImageLoading.add(assetPath);
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _itemImageCache[assetPath] = frame.image;
      onItemImageReady?.call();
    } catch (e) {
      debugPrint('Failed to load item image: $e');
    } finally {
      _itemImageLoading.remove(assetPath);
    }
  }

  static bool get isReady =>
      _initialized &&
      _movePicture != null &&
      _rotatePicture != null &&
      _moveBluePicture != null &&
      _rotateBluePicture != null &&
      _moveRedPicture != null &&
      _rotateRedPicture != null &&
      _pointerPicture != null &&
      _previewPointerPicture != null;

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
      List<Offset> path, int index,
      {String? incomingDirection, String? forcedDirection}) {
    if (path.length == 1) {
      if (incomingDirection != null &&
          forcedDirection != null &&
          incomingDirection != forcedDirection) {
        final inIdx = _directionToIndex(incomingDirection);
        final outIdx = _directionToIndex(forcedDirection);
        final diff = (outIdx - inIdx + 4) % 4;
        final isCCW = diff == 3;
        return (true, incomingDirection, forcedDirection, isCCW);
      }
      final dir =
          _getCellDirection(path, index, forcedDirection: forcedDirection);
      return (false, dir, dir, false);
    }

    if (index == 0) {
      // 首格：如果有 incomingDirection，用它作为入方向
      if (incomingDirection != null) {
        final nextDx = path[1].dx - path[0].dx;
        final nextDy = path[1].dy - path[0].dy;
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
      final dir =
          _getCellDirection(path, index, forcedDirection: forcedDirection);
      return (false, dir, dir, false);
    }

    if (index == path.length - 1) {
      final prevDx = path[index].dx - path[index - 1].dx;
      final prevDy = path[index].dy - path[index - 1].dy;
      final incomingDir = _offsetToDirection(prevDx, prevDy);
      if (forcedDirection != null && incomingDir != forcedDirection) {
        final inIdx = _directionToIndex(incomingDir);
        final outIdx = _directionToIndex(forcedDirection);
        final diff = (outIdx - inIdx + 4) % 4;
        final isCCW = diff == 3;
        return (true, incomingDir, forcedDirection, isCCW);
      }
      final dir =
          _getCellDirection(path, index, forcedDirection: forcedDirection);
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
    double arrowProgress = 0.0,
    Item? lastItem,
    Map<String, Item>? allItems,
    bool hideTerminalBackground = false,
    Set<Offset>? hiddenBackgroundCells,
  }) {
    if (belt.path.isEmpty) return;

    // 检测是否是断头传送带（终点未连接设备输入端口）
    final isDeadEnd = !isInputPort(belt.path.last, buildings);

    belt.ensureItemSegmentsFromLegacy();

    final hasItemImage = item != null && item.imageAssetPath.isNotEmpty;
    final itemImage =
        hasItemImage ? _itemImageCache[item.imageAssetPath] : null;

    // 残留物品图片
    final hasLastItemImage =
        lastItem != null && lastItem.imageAssetPath.isNotEmpty;
    final lastItemImage =
        hasLastItemImage ? _itemImageCache[lastItem.imageAssetPath] : null;

    final renderSegments = belt.itemSegments
        .where((segment) => segment.hasItems)
        .map((segment) => ConveyorItemSegment(
              itemId: segment.itemId,
              fillCount: segment.fillCount.clamp(0, belt.path.length).toInt(),
              drainCount: segment.drainCount.clamp(0, belt.path.length).toInt(),
              freezeProgress: segment.freezeProgress,
            ))
        .toList()
      ..sort((a, b) => a.drainCount.compareTo(b.drainCount));

    final segmentImages = <String, ui.Image?>{};
    for (final segment in renderSegments) {
      final dataItem = allItems?[segment.itemId] ??
          (segment.itemId == belt.itemId
              ? item
              : (segment.itemId == belt.lastItemId ? lastItem : null));
      final imagePath = dataItem?.imageAssetPath;
      segmentImages[segment.itemId] = imagePath != null && imagePath.isNotEmpty
          ? _itemImageCache[imagePath]
          : null;
    }

    // === 断头传送带满载时冻结 arrowProgress ===
    // 队列段优先：每一段抵达它前方的阻挡位置后单独冻结，避免 B→A
    // 这类多物品队列在断源或重连时重新播放一小段移动动画。
    if (renderSegments.isNotEmpty) {
      final sourceSegments = belt.itemSegments
          .where((segment) => segment.hasItems)
          .toList()
        ..sort((a, b) => a.drainCount.compareTo(b.drainCount));
      bool frozenAhead = false;
      for (int i = renderSegments.length - 1; i >= 0; i--) {
        final segment = renderSegments[i];
        final limit = i + 1 < renderSegments.length
            ? renderSegments[i + 1].drainCount.clamp(0, belt.path.length)
            : belt.path.length;
        final sourceSegment =
            i < sourceSegments.length ? sourceSegments[i] : segment;
        if (sourceSegment.freezeProgress == FreezeSentinels.rendererWaiting &&
            arrowProgress >= 0.5) {
          sourceSegment.freezeProgress = null;
        }
        final fp = sourceSegment.freezeProgress;
        final isLastSegment = i == renderSegments.length - 1;
        final atLimit = segment.fillCount >= limit;
        final shouldFreezeSegment = atLimit && (isLastSegment || frozenAhead);
        if (shouldFreezeSegment && fp == null) {
          sourceSegment.freezeProgress = FreezeSentinels.newlyFrozen;
        }
        if (shouldFreezeSegment && fp == FreezeSentinels.newlyFrozen) {
          sourceSegment.freezeProgress = FreezeSentinels.waiting;
        }
        if (shouldFreezeSegment && fp == FreezeSentinels.waiting) {
          if (arrowProgress < 0.5) {
            sourceSegment.freezeProgress = FreezeSentinels.midFrozen;
          }
        }
        if (shouldFreezeSegment && fp == FreezeSentinels.midFrozen) {
          if (arrowProgress >= 0.5) {
            sourceSegment.freezeProgress = FreezeSentinels.settled;
          }
        }
        final newFp = sourceSegment.freezeProgress;
        frozenAhead = FreezeSentinels.isFreezing(newFp);
        segment.freezeProgress = newFp;
      }
      belt.syncLegacyFromSegments();
    }

    final currentFillLimit =
        belt.currentItemFillLimit.clamp(0, belt.path.length);
    final currentFull = currentFillLimit > 0 &&
        belt.itemFillCount.clamp(0, belt.path.length) >= currentFillLimit;
    final lastFull =
        belt.lastItemFillCount.clamp(0, belt.path.length) >= belt.path.length;
    final bool shouldFreezeCurrent =
        isDeadEnd && currentFull && renderSegments.isEmpty;
    final bool shouldFreezeLast =
        isDeadEnd && lastFull && renderSegments.isEmpty;

    if (shouldFreezeCurrent && belt.deadEndFreezeProgress == null) {
      // 阶段 0→1：物品刚刚到达停止位置，标记为 waiting（等待自然流入）
      belt.deadEndFreezeProgress = FreezeSentinels.waiting;
    }
    if (shouldFreezeCurrent && belt.deadEndFreezeProgress == FreezeSentinels.waiting) {
      // 阶段 1→2：等待 arrowProgress 降到 0.5 以下（物品已通过入口半区）
      if (arrowProgress < 0.5) {
        belt.deadEndFreezeProgress = FreezeSentinels.midFrozen;
      }
    }
    if (shouldFreezeCurrent && belt.deadEndFreezeProgress == FreezeSentinels.midFrozen) {
      // 阶段 2→3：等待 arrowProgress 回升到 0.5（物品已自然流到格子中央）
      if (arrowProgress >= 0.5) {
        belt.deadEndFreezeProgress = FreezeSentinels.settled;
      }
    }
    if (!shouldFreezeCurrent && belt.deadEndFreezeProgress != null) {
      // 不再满载（如被加长或源断开排空）：清除冻结值
      belt.deadEndFreezeProgress = null;
    }

    if (shouldFreezeLast && belt.lastItemFreezeProgress == null) {
      // 阶段 0→1：物品刚刚到达停止位置，标记为 waiting（等待自然流入）
      belt.lastItemFreezeProgress = FreezeSentinels.waiting;
    }
    if (shouldFreezeLast && belt.lastItemFreezeProgress == FreezeSentinels.waiting) {
      // 阶段 1→2：等待 arrowProgress 降到 0.5 以下
      if (arrowProgress < 0.5) {
        belt.lastItemFreezeProgress = FreezeSentinels.midFrozen;
      }
    }
    if (shouldFreezeLast && belt.lastItemFreezeProgress == FreezeSentinels.midFrozen) {
      // 阶段 2→3：等待 arrowProgress 回升到 0.5
      if (arrowProgress >= 0.5) {
        belt.lastItemFreezeProgress = FreezeSentinels.settled;
      }
    }
    if (!shouldFreezeLast && belt.lastItemFreezeProgress != null) {
      belt.lastItemFreezeProgress = null;
    }

    final effectiveArrowProgress = (shouldFreezeCurrent &&
            belt.deadEndFreezeProgress != null &&
            belt.deadEndFreezeProgress! > 0)
        ? belt.deadEndFreezeProgress!
        : arrowProgress;
    final effectiveLastArrowProgress = (shouldFreezeLast &&
            belt.lastItemFreezeProgress != null &&
            belt.lastItemFreezeProgress! > 0)
        ? belt.lastItemFreezeProgress!
        : arrowProgress;

    if (isReady) {
      _renderWithSvg(
        canvas,
        belt.path,
        cellSize,
        buildings,
        forcedDirection: belt.forcedDirection,
        incomingDirection: belt.incomingDirection,
        arrowProgress: effectiveArrowProgress,
        lastArrowProgress: effectiveLastArrowProgress,
        itemImage: itemImage,
        itemFillCount: belt.itemFillCount.clamp(0, belt.path.length).toInt(),
        itemDrainCount: belt.itemDrainCount.clamp(0, belt.path.length).toInt(),
        lastItemImage: lastItemImage,
        lastItemFillCount:
            belt.lastItemFillCount.clamp(0, belt.path.length).toInt(),
        lastItemDrainCount:
            belt.lastItemDrainCount.clamp(0, belt.path.length).toInt(),
        itemSegments: renderSegments,
        segmentImages: segmentImages,
        hideTerminalBackground: hideTerminalBackground,
        hiddenBackgroundCells: hiddenBackgroundCells,
      );
    } else {
      for (int i = 0; i < belt.path.length; i++) {
        final cell = belt.path[i];
        final direction = _getCellDirection(belt.path, i,
            forcedDirection: belt.forcedDirection);
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

    // LOD 2: 无物品图片时回退到粒子动画
    if (detailLevel >= 2 &&
        item != null &&
        (belt.itemFillCount > belt.itemDrainCount) &&
        itemImage == null) {
      _renderParticles(canvas, belt, item, cellSize, buildings);
    }

    // 触发图片异步加载
    if (hasItemImage &&
        itemImage == null &&
        !_itemImageLoading.contains(item.imageAssetPath)) {
      _loadItemImage(item.imageAssetPath);
    }
    if (hasLastItemImage &&
        lastItemImage == null &&
        !_itemImageLoading.contains(lastItem.imageAssetPath)) {
      _loadItemImage(lastItem.imageAssetPath);
    }
    if (allItems != null) {
      for (final segment in renderSegments) {
        final segmentItem = allItems[segment.itemId];
        final imagePath = segmentItem?.imageAssetPath;
        if (imagePath != null &&
            imagePath.isNotEmpty &&
            !_itemImageCache.containsKey(imagePath) &&
            !_itemImageLoading.contains(imagePath)) {
          _loadItemImage(imagePath);
        }
      }
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
    double arrowProgress = 0.0,
    double? lastArrowProgress,
    ui.Image? itemImage,
    int itemFillCount = 0,
    int itemDrainCount = 0,
    ui.Image? lastItemImage,
    int lastItemFillCount = 0,
    int lastItemDrainCount = 0,
    List<ConveyorItemSegment>? itemSegments,
    Map<String, ui.Image?>? segmentImages,
    bool hideTerminalBackground = false,
    Set<Offset>? hiddenBackgroundCells,
  }) {
    // 第一次绘制：只绘制背景（传送带）
    // 当 hideTerminalBackground=true 时，跳过最后一格的背景绘制
    // （该格由预览覆盖），但物品仍需在第二趟绘制中渲染
    // 当 hiddenBackgroundCells 包含某格子时，跳过该格背景（物品仍渲染）
    for (int i = 0; i < path.length; i++) {
      if (hideTerminalBackground && i == path.length - 1) continue;
      final cell = path[i];
      final isHiddenCell = hiddenBackgroundCells != null && hiddenBackgroundCells.contains(cell);
      if (isHiddenCell) {
        // 半透明绘制：用 saveLayer + 半透明 Paint 实现整体透明度
        final cx = cell.dx * cellSize + cellSize / 2;
        final cy = cell.dy * cellSize + cellSize / 2;
        canvas.saveLayer(
          Rect.fromCenter(center: Offset(cx, cy), width: cellSize, height: cellSize),
          Paint()..color = const Color(0x66FFFFFF), // 40% 不透明度
        );
        canvas.translate(cx, cy);
        final clip = getLocalClipRect(
          path: path,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
        );
        if (clip != null) {
          canvas.clipRect(clip);
        }
        _drawSvgCellAtOrigin(
          canvas,
          path,
          i,
          cellSize,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
          arrowProgress: arrowProgress,
          drawBackground: true,
          drawPointer: false,
        );
        canvas.restore();
        continue;
      }
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
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
      );
      if (clip != null) {
        canvas.clipRect(clip);
      }

      _drawSvgCellAtOrigin(
        canvas,
        path,
        i,
        cellSize,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
        arrowProgress: arrowProgress,
        drawBackground: true,
        drawPointer: false,
      );
      canvas.restore();
    }

    // 第二次绘制：只绘制前景（指针/物品），避免被相邻背景覆盖
    //
    // === 渲染不变量（添加新功能时必须遵守）===
    // 1. 每个格子只画一个前景元素：物品 > 残留物品 > 指针（优先级从高到低）
    // 2. 有 itemImage 时 _drawSvgCellAtOrigin 总是画物品，不受 drawPointer 影响
    // 3. 新模型：fillCount/drainCount 为整数，由 _onTick 跨零检测驱动
    //
    final int fillCount = itemFillCount.clamp(0, path.length);
    final int drainCount = itemDrainCount.clamp(0, path.length);
    final int lastFillCount = lastItemFillCount.clamp(0, path.length);
    final int lastDrainCount = lastItemDrainCount.clamp(0, path.length);
    final lastProgress = lastArrowProgress ?? arrowProgress;
    final segments = itemSegments?.where((segment) => segment.hasItems).toList()
      ?..sort((a, b) => a.drainCount.compareTo(b.drainCount));

    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final cx = cell.dx * cellSize + cellSize / 2;
      final cy = cell.dy * cellSize + cellSize / 2;

      ui.Image? cellItemImage;
      double cellArrowProgress = arrowProgress;
      if (segments != null && segments.isNotEmpty) {
        for (int j = segments.length - 1; j >= 0; j--) {
          final segment = segments[j];
          final segmentDrain = segment.drainCount.clamp(0, path.length);
          final segmentFill = segment.fillCount.clamp(0, path.length);
          if (i >= segmentDrain && i < segmentFill) {
            cellItemImage = segmentImages?[segment.itemId];
            final frozen = segment.freezeProgress;
            if (frozen == FreezeSentinels.clearing) {
              cellArrowProgress = arrowProgress < 0.5 ? 0.5 : arrowProgress;
            } else if (frozen != null &&
                (frozen > 0 || frozen == FreezeSentinels.rendererWaiting)) {
              cellArrowProgress =
                  frozen == FreezeSentinels.rendererWaiting ? 0.5 : frozen;
            }
            break;
          }
        }
      } else {
        final cellLastFilled =
            lastItemImage != null && i >= lastDrainCount && i < lastFillCount;
        final cellCurrentFilled = !cellLastFilled &&
            itemImage != null &&
            i >= drainCount &&
            i < fillCount;
        cellItemImage = cellLastFilled
            ? lastItemImage
            : (cellCurrentFilled ? itemImage : null);
        cellArrowProgress = cellLastFilled ? lastProgress : arrowProgress;
      }

      canvas.save();
      canvas.translate(cx, cy);

      final clip = getLocalClipRect(
        path: path,
        index: i,
        cellSize: cellSize,
        buildings: buildings,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
      );
      if (clip != null) {
        canvas.clipRect(clip);
      }

      _drawSvgCellAtOrigin(
        canvas,
        path,
        i,
        cellSize,
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
        arrowProgress: cellArrowProgress,
        drawBackground: false,
        drawPointer: !(hideTerminalBackground && i == path.length - 1),
        itemImage: cellItemImage,
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

  static String _getCellDirection(List<Offset> path, int index,
      {String? forcedDirection}) {
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

  static void _renderParticles(
    Canvas canvas,
    ConveyorBelt belt,
    Item item,
    double cellSize,
    List<PlacedBuilding> buildings,
  ) {
    final totalLength = belt.length;
    if (totalLength <= 0) return;

    final particlePaint = Paint()..color = item.color;
    final particleCount =
        (totalLength / _particleSpacing).floor().clamp(1, 200);
    final flowOffset = belt.flowProgress * _particleSpacing;

    for (int i = 0; i < particleCount; i++) {
      final distance = (i * _particleSpacing + flowOffset) % totalLength;
      final pos = _getPositionAlongPath(belt.path, distance, cellSize);
      if (_shouldDiscardParticle(pos, belt.path, cellSize, buildings)) {
        continue;
      }
      canvas.drawCircle(pos, _particleSize, particlePaint);
    }
  }

  static Offset _getPositionAlongPath(
      List<Offset> path, double distance, double cellSize) {
    if (path.length < 2) return Offset.zero;

    int segmentIndex = (distance / cellSize).floor();
    if (segmentIndex >= path.length - 1) segmentIndex = path.length - 2;
    if (segmentIndex < 0) segmentIndex = 0;

    final t = (distance - segmentIndex * cellSize) / cellSize;
    final from = path[segmentIndex];
    final to = path[segmentIndex + 1];

    return Offset(
      (from.dx + (to.dx - from.dx) * t) * cellSize + cellSize / 2,
      (from.dy + (to.dy - from.dy) * t) * cellSize + cellSize / 2,
    );
  }

  static void _renderBlockedIndicator(
      Canvas canvas, Offset cell, double cellSize) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final pos = Offset(cx, cy);

    canvas.drawCircle(
        pos, _particleSize * 2, Paint()..color = const Color(0xFFFF3333));

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
    String? forcedDirection,
    String? incomingDirection,
    double arrowProgress = 0.0,
    List<ConveyorItemSegment>? itemSegments,
    Map<String, Item>? allItems,
    bool opaqueItems = false,
    double? itemArrowProgress,
  }) {
    if (path.isEmpty) return;

    if (isReady) {
      _renderPreviewWithSvg(canvas, path, cellSize, occupiedKeys, buildings,
          isInvalid: isInvalid,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
          arrowProgress: arrowProgress,
          itemSegments: itemSegments,
          allItems: allItems,
          opaqueItems: opaqueItems,
          itemArrowProgress: itemArrowProgress);
    } else {
      _renderPreviewLegacy(canvas, path, cellSize, occupiedKeys, buildings,
          isInvalid: isInvalid);
    }
  }

  /// 判断是否是转弯点
  static bool _isTurn(List<Offset> path, int index,
      {String? incomingDirection}) {
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
  static PictureInfo _getPicture(
      {bool isTurn = false, bool isBlue = false, bool isRed = false}) {
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
    String? forcedDirection,
    String? incomingDirection,
    double arrowProgress = 0.0,
    List<ConveyorItemSegment>? itemSegments,
    Map<String, Item>? allItems,
    bool opaqueItems = false,
    double? itemArrowProgress,
  }) {
    final segmentImages = <String, ui.Image?>{};
    if (itemSegments != null && allItems != null) {
      for (final segment in itemSegments) {
        final imagePath = allItems[segment.itemId]?.imageAssetPath;
        if (imagePath == null || imagePath.isEmpty) continue;
        segmentImages[segment.itemId] = _itemImageCache[imagePath];
        if (!_itemImageCache.containsKey(imagePath) &&
            !_itemImageLoading.contains(imagePath)) {
          _loadItemImage(imagePath);
        }
      }
    }

    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      final isOccupied = isInvalid || occupiedKeys.contains(key);
      final actualIndex = fullPathContext != null ? contextStartIndex + i : i;
      ui.Image? cellItemImage;
      if (itemSegments != null) {
        for (int j = itemSegments.length - 1; j >= 0; j--) {
          final segment = itemSegments[j];
          if (!segment.hasItems) continue;
          if (actualIndex >= segment.drainCount &&
              actualIndex < segment.fillCount) {
            cellItemImage = segmentImages[segment.itemId];
            break;
          }
        }
      }

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
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
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
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
        arrowProgress: arrowProgress,
        drawBackground: true,
        drawPointer: !(opaqueItems && cellItemImage != null),
        itemImage: opaqueItems ? null : cellItemImage,
      );
      canvas.restore();

      canvas.restore();

      if (opaqueItems && cellItemImage != null) {
        canvas.save();
        canvas.translate(cx, cy);
        final clip = getLocalClipRect(
          path: path,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
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
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
          arrowProgress: itemArrowProgress ?? arrowProgress,
          drawBackground: false,
          drawPointer: false,
          itemImage: cellItemImage,
        );
        canvas.restore();
      }
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
    double arrowProgress = 0.0,
    bool drawBackground = true,
    bool drawPointer = true,
    ui.Image? itemImage,
  }) {
    // 确定用于转弯检测的路径 and 索引
    List<Offset> turnPath = path;
    int turnIndex = index;

    if (fullPathContext != null) {
      turnPath = fullPathContext;
      turnIndex = contextStartIndex + index;
    }

    final (isTurn, _, outgoingDir, isCCW) = _getCellTurnInfo(
        turnPath, turnIndex,
        incomingDirection: incomingDirection, forcedDirection: forcedDirection);

    final PictureInfo picture;
    if (isPreview) {
      if (isOccupied) {
        picture = _getPicture(isTurn: isTurn, isRed: true);
      } else {
        picture = _getPicture(isTurn: isTurn, isBlue: true);
      }
    } else {
      picture = _getPicture(isTurn: isTurn);
    }

    final svgSize = picture.size;
    final scaleX = cellSize / svgSize.width;
    final scaleY = cellSize / svgSize.height;

    if (drawBackground) {
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
        canvas.save();
        canvas.rotate(rotation);
        if (mirrorH) {
          canvas.scale(-1, 1);
        }
        canvas.scale(scaleX, scaleY);
        canvas.translate(-svgSize.width / 2, -svgSize.height / 2);
        canvas.drawPicture(picture.picture);
        canvas.restore();
      } else {
        final direction = _getCellDirection(turnPath, turnIndex,
            forcedDirection: forcedDirection);
        final dirIdx = _directionToIndex(direction);
        final rotation = dirIdx * math.pi / 2;

        canvas.save();
        canvas.rotate(rotation);
        canvas.scale(scaleX, scaleY);
        canvas.translate(-svgSize.width / 2, -svgSize.height / 2);
        canvas.drawPicture(picture.picture);
        canvas.restore();
      }
    }

    // 渲染前景（指针/物品）：
    // - 有 itemImage 时总是画物品（不受 drawPointer 影响）
    // - 无 itemImage 且 drawPointer=true 时画指针
    // 这确保物品一旦出现就不会因为 drawPointer 标志而被意外隐藏
    if (itemImage != null || (drawPointer && _pointerPicture != null)) {
      canvas.save();

      void drawItemAt(double pProgress) {
        if (isTurn) {
          final (_, inDir, outDir, isCCW) = _getCellTurnInfo(
              turnPath, turnIndex,
              incomingDirection: incomingDirection,
              forcedDirection: forcedDirection);
          double eX = 0, eY = 0;
          if (inDir == 'up') eY = 0.5;
          if (inDir == 'down') eY = -0.5;
          if (inDir == 'left') eX = 0.5;
          if (inDir == 'right') eX = -0.5;

          double xX = 0, xY = 0;
          if (outDir == 'up') xY = -0.5;
          if (outDir == 'down') xY = 0.5;
          if (outDir == 'left') xX = -0.5;
          if (outDir == 'right') xX = 0.5;

          final pivotX = eX + xX;
          final pivotY = eY + xY;

          final startVecX = -xX;
          final startVecY = -xY;

          final startAngle = math.atan2(startVecY, startVecX);
          final deltaAngle = isCCW ? -math.pi / 2 : math.pi / 2;
          final currentAngle = startAngle + pProgress * deltaAngle;

          final px = pivotX + 0.5 * math.cos(currentAngle);
          final py = pivotY + 0.5 * math.sin(currentAngle);

          final tangentAngle = currentAngle + deltaAngle;

          canvas.save();
          canvas.translate(px * cellSize, py * cellSize);
          canvas.rotate(tangentAngle + math.pi / 2);

          if (itemImage != null) {
            final drawSize = cellSize * 0.35;
            final srcRect = Rect.fromLTWH(
                0, 0, itemImage.width.toDouble(), itemImage.height.toDouble());
            final dstRect = Rect.fromCenter(
                center: Offset.zero, width: drawSize, height: drawSize);
            canvas.drawImageRect(itemImage, srcRect, dstRect, Paint());
          } else {
            final pointer =
                isPreview ? _previewPointerPicture! : _pointerPicture!;
            final pSize = pointer.size;
            final double uniformScale = (cellSize * 0.25) / pSize.height;
            canvas.scale(uniformScale, uniformScale);
            canvas.translate(-pSize.width / 2, -pSize.height / 2);
            canvas.drawPicture(pointer.picture);
          }
          canvas.restore();
        } else {
          // straight movement
          final direction = _getCellDirection(turnPath, turnIndex,
              forcedDirection: forcedDirection);
          final dirIdx = _directionToIndex(direction);
          final rotation = dirIdx * math.pi / 2;

          final double moveDist = (0.5 - pProgress) * cellSize;

          canvas.save();
          canvas.rotate(rotation);
          canvas.translate(0, moveDist);

          if (itemImage != null) {
            final drawSize = cellSize * 0.35;
            final srcRect = Rect.fromLTWH(
                0, 0, itemImage.width.toDouble(), itemImage.height.toDouble());
            final dstRect = Rect.fromCenter(
                center: Offset.zero, width: drawSize, height: drawSize);
            canvas.drawImageRect(itemImage, srcRect, dstRect, Paint());
          } else {
            final pointer =
                isPreview ? _previewPointerPicture! : _pointerPicture!;
            final pSize = pointer.size;
            final double uniformScale = (cellSize * 0.25) / pSize.height;
            canvas.scale(uniformScale, uniformScale);
            canvas.translate(-pSize.width / 2, -pSize.height / 2);
            canvas.drawPicture(pointer.picture);
          }
          canvas.restore();
        }
      }

      drawItemAt(arrowProgress);

      canvas.restore();
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
        canvas.drawRRect(
            rect,
            Paint()
              ..color = isOccupied ? _previewOccupiedFill : _previewFillColor);
        canvas.drawRRect(
            rect,
            Paint()
              ..color =
                  isOccupied ? _previewOccupiedBorder : _previewBorderColor
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke);

        if (path.length >= 2 && !isOccupied) {
          final direction = _getCellDirection(path, i);
          _drawArrow(canvas, cell, direction, cellSize, _previewArrowColor);
        }
        canvas.restore();
      } else {
        canvas.drawRRect(
            rect,
            Paint()
              ..color = isOccupied ? _previewOccupiedFill : _previewFillColor);
        canvas.drawRRect(
            rect,
            Paint()
              ..color =
                  isOccupied ? _previewOccupiedBorder : _previewBorderColor
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
          incomingDirection: incomingDirection,
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

  static void renderHoverHighlight(
      Canvas canvas, Offset gridPos, double cellSize) {
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
  static void _renderOpaquePreviewItems(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    List<PlacedBuilding> buildings,
    List<ConveyorItemSegment> itemSegments,
    Map<String, ui.Image?> segmentImages, {
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
    String? forcedDirection,
    String? incomingDirection,
    double arrowProgress = 0.5,
  }) {
    for (int i = 0; i < path.length; i++) {
      final actualIndex = fullPathContext != null ? contextStartIndex + i : i;
      ui.Image? cellItemImage;
      for (int j = itemSegments.length - 1; j >= 0; j--) {
        final segment = itemSegments[j];
        if (!segment.hasItems) continue;
        if (actualIndex >= segment.drainCount &&
            actualIndex < segment.fillCount) {
          cellItemImage = segmentImages[segment.itemId];
          break;
        }
      }
      if (cellItemImage == null) continue;

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
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
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
        fullPathContext: fullPathContext,
        contextStartIndex: contextStartIndex,
        forcedDirection: forcedDirection,
        incomingDirection: incomingDirection,
        arrowProgress: arrowProgress,
        drawBackground: false,
        drawPointer: false,
        itemImage: cellItemImage,
      );
      canvas.restore();
    }
  }

  static void renderConfirmedPreviewPath(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    List<PlacedBuilding> buildings, {
    List<Offset>? fullPathContext,
    int contextStartIndex = 0,
    String? forcedDirection,
    String? incomingDirection,
    double arrowProgress = 0.0,
    List<ConveyorItemSegment>? itemSegments,
    Map<String, Item>? allItems,
    bool opaqueItems = false,
    double? itemArrowProgress,
  }) {
    if (path.isEmpty) return;

    if (isReady) {
      final segmentImages = <String, ui.Image?>{};
      if (itemSegments != null && allItems != null) {
        for (final segment in itemSegments) {
          final imagePath = allItems[segment.itemId]?.imageAssetPath;
          if (imagePath == null || imagePath.isEmpty) continue;
          segmentImages[segment.itemId] = _itemImageCache[imagePath];
          if (!_itemImageCache.containsKey(imagePath) &&
              !_itemImageLoading.contains(imagePath)) {
            _loadItemImage(imagePath);
          }
        }
      }

      // 使用 SVG 渲染，通过 saveLayer 降低透明度
      canvas.saveLayer(null, Paint()..color = const Color(0xCCFFFFFF));
      _renderWithSvg(canvas, path, cellSize, buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
          arrowProgress: arrowProgress,
          itemSegments: opaqueItems ? null : itemSegments,
          segmentImages: segmentImages);
      canvas.restore();
      if (opaqueItems && itemSegments != null) {
        _renderOpaquePreviewItems(
          canvas,
          path,
          cellSize,
          buildings,
          itemSegments,
          segmentImages,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
          arrowProgress: itemArrowProgress ?? arrowProgress,
        );
      }
    } else {
      for (int i = 0; i < path.length; i++) {
        final cell = path[i];
        final direction =
            _getCellDirection(path, i, forcedDirection: forcedDirection);
        final cx = cell.dx * cellSize + cellSize / 2;
        final cy = cell.dy * cellSize + cellSize / 2;

        final localClip = getLocalClipRect(
          path: path,
          index: i,
          cellSize: cellSize,
          buildings: buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: contextStartIndex,
          forcedDirection: forcedDirection,
          incomingDirection: incomingDirection,
        );

        if (localClip != null) {
          canvas.save();
          canvas.clipRect(localClip.shift(Offset(cx, cy)));
          _drawConveyorCell(
            canvas,
            path[i],
            direction,
            cellSize,
            _confirmedFillColor,
            _confirmedLineColor,
            _confirmedArrowColor,
          );
          canvas.restore();
        } else {
          _drawConveyorCell(
            canvas,
            path[i],
            direction,
            cellSize,
            _confirmedFillColor,
            _confirmedLineColor,
            _confirmedArrowColor,
          );
        }
      }
    }
  }
}
