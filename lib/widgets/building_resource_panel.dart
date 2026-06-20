import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/item.dart';
import 'building_shared_widgets.dart';
import 'item_description_dialog.dart';

class ResourceItem {
  final String id;
  final String name;
  final String category;
  final Color color;
  final String imageAssetPath;
  final int level;
  final String description;
  final String secondaryDescription;

  ResourceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imageAssetPath,
    required this.level,
    this.description = '',
    this.secondaryDescription = '',
  });
}

class ResourceGridTile extends StatefulWidget {
  final ResourceItem item;
  final GlobalKey gridContainerKey;
  final bool showAddIcon;
  final VoidCallback? onAddItem;
  final bool enableDrag;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const ResourceGridTile({
    super.key,
    required this.item,
    required this.gridContainerKey,
    this.showAddIcon = false,
    this.onAddItem,
    this.enableDrag = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  @override
  State<ResourceGridTile> createState() => ResourceGridTileState();
}

String gridTileSvg(int level, {bool isHovered = false}) {
  const gradientEndColors = {
    2: '#93e8a4',
    3: '#6d9bf1',
    4: '#b73cc5',
  };
  const tagColors = {
    2: '#44aa00',
    3: '#0082ea',
    4: '#b73cc5',
  };
  final endColor = gradientEndColors[level] ?? '#dddddd';
  final tagColor = tagColors[level] ?? '#ebebeb';

  final stopColor = isHovered ? '#252525' : '#696969';

  return '<svg xmlns="http://www.w3.org/2000/svg" width="94" height="94" viewBox="0 0 94 94">'
      '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="94" gradientUnits="userSpaceOnUse">'
      '<stop offset="0" stop-color="$stopColor"/>'
      '<stop offset="0.7" stop-color="$stopColor"/>'
      '<stop offset="1" stop-color="$endColor"/>'
      '</linearGradient></defs>'
      '<rect x="0" y="0" width="94" height="94" rx="11" ry="11" fill="url(#g)"/>'
      '<path d="M 0.62286269,86.67038 C 2.1269947,90.943986 6.1932067,93.993161 11.000205,93.999896 h 72.000299 c 4.807005,-0.0066 8.873217,-3.05591 10.377348,-7.329516 z" fill="$tagColor"/>'
      '</svg>';
}

class ResourceGridTileState extends State<ResourceGridTile>
    with TickerProviderStateMixin {
  bool _hovering = false;
  double _tooltipBottomOffset = 8.0;
  late final SvgPicture _normalBg;
  late final SvgPicture _hoveredBg;
  bool _imageLogged = false;
  // 长按进度动画
  late final AnimationController _longPressController;
  bool _isLongPressing = false;
  bool _dragStarted = false;
  Timer? _longPressDelayTimer;

  @override
  void initState() {
    super.initState();
    _longPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _normalBg = SvgPicture.string(
      gridTileSvg(widget.item.level, isHovered: false),
      fit: BoxFit.fill,
    );
    _hoveredBg = SvgPicture.string(
      gridTileSvg(widget.item.level, isHovered: true),
      fit: BoxFit.fill,
    );
  }

  @override
  void dispose() {
    _longPressDelayTimer?.cancel();
    _longPressController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enableDrag) return;
    _dragStarted = false;
    // 延迟150ms后启动圆形动画，快速点击不会触发
    _longPressDelayTimer?.cancel();
    _longPressDelayTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _isLongPressing = true;
      _longPressController.forward(from: 0);
      setState(() {});
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressDelayTimer?.cancel();
    if (!_isLongPressing) return;
    _isLongPressing = false;
    _longPressController.reverse();
    setState(() {});
  }

  void _onDragStarted() {
    _dragStarted = true;
    _isLongPressing = false;
    // 拖拽开始后立即重置圆形动画，不播放回退
    _longPressController.value = 0;
    setState(() {});
    widget.onDragStarted?.call();
  }

  void _onEnter(PointerEnterEvent _) {
    double bottomOffset = 8.0;

    final tileBox = context.findRenderObject() as RenderBox;
    final gridBox = widget.gridContainerKey.currentContext?.findRenderObject()
        as RenderBox?;

    if (gridBox != null) {
      final tilePos = tileBox.localToGlobal(Offset.zero, ancestor: gridBox);
      final tileSize = tileBox.size;
      final gridSize = gridBox.size;

      final tooltipBottomInGrid = tilePos.dy + tileSize.height - 8.0;

      if (tooltipBottomInGrid > gridSize.height) {
        bottomOffset = (tileSize.height - (gridSize.height - tilePos.dy))
            .clamp(0.0, tileSize.height);
      }
    }

    setState(() {
      _tooltipBottomOffset = bottomOffset;
      _hovering = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gridContent = MouseRegion(
      onEnter: _onEnter,
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.antiAlias,
        children: [
          _hovering ? _hoveredBg : _normalBg,
          Center(
            child: AnimatedScale(
              scale: _hovering ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: widget.item.imageAssetPath.isNotEmpty
                  ? Image.asset(
                      widget.item.imageAssetPath,
                      width: 93,
                      height: 93,
                      cacheWidth: 279,
                      cacheHeight: 279,
                      fit: BoxFit.contain,
                      filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                      isAntiAlias: true,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (!_imageLogged) {
                          _imageLogged = true;
                          debugPrint('[ResourceGridTile] 图片显示: '
                              '${widget.item.name}, '
                              '同步加载=$wasSynchronouslyLoaded, '
                              '有帧=${frame != null}');
                        }
                        return child;
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.item.color.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.item.color.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.item.color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.item.color.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
            ),
          ),
          if (widget.showAddIcon)
            GestureDetector(
              onTap: widget.onAddItem,
              behavior: HitTestBehavior.opaque,
              child: Opacity(
                opacity: _hovering ? 0.3 : 0.4,
                child: SizedBox.expand(
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          _hovering ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: 0.8,
                        child: SvgPicture.asset(
                          'assets/svg/add.svg',
                          width: 40,
                          height: 40,
                          colorFilter: ColorFilter.mode(
                            _hovering
                                ? const Color(0xFFFFFFFF)
                                : const Color(0xFF000000),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_hovering)
              Positioned(
                bottom: _tooltipBottomOffset,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey[900]?.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
    );

    // 添加模式下，整个网格区域均可点击
    if (widget.showAddIcon) {
      return GestureDetector(
        onTap: widget.onAddItem,
        behavior: HitTestBehavior.opaque,
        child: gridContent,
      );
    }
    // 普通模式下，点击弹出物品说明弹窗
    final tileWidget = GestureDetector(
      onTap: () => ItemDescriptionDialog.show(context,
          item: Item(
            id: widget.item.id,
            name: widget.item.name,
            category: widget.item.category,
            subType: widget.item.category,
            color: widget.item.color,
            iconSvg: '',
            imageAssetPath: widget.item.imageAssetPath,
            level: widget.item.level,
            description: widget.item.description,
            secondaryDescription: widget.item.secondaryDescription,
          )),
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: gridContent,
      ),
    );

    if (!widget.enableDrag) return tileWidget;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => _onPointerUp(PointerUpEvent()),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.antiAlias,
        children: [
          LongPressDraggable<InventoryDragData>(
        delay: const Duration(milliseconds: 450),
            data: InventoryDragData(
              source: InventoryDragSource.itemPanel,
              itemId: widget.item.id,
              itemName: widget.item.name,
              imageAssetPath: widget.item.imageAssetPath,
              color: widget.item.color,
              level: widget.item.level,
            ),
            onDragStarted: _onDragStarted,
            onDragEnd: (_) {
              _dragStarted = false;
              _longPressController.value = 0;
              widget.onDragEnd?.call();
            },
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF373737),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: widget.item.imageAssetPath.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            widget.item.imageAssetPath,
                            width: 68,
                            height: 68,
                            cacheWidth: 204,
                            cacheHeight: 204,
                            fit: BoxFit.contain,
                            filterQuality:
                                kIsWeb ? FilterQuality.high : FilterQuality.medium,
                            isAntiAlias: true,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: tileWidget,
            ),
            child: tileWidget,
          ),
          // 长按圆形填充动画
          if (_isLongPressing || _dragStarted)
            IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _longPressController,
                  builder: (context, _) {
                    final progress = _longPressController.value;
                    final opacity = _dragStarted ? (1.0 - progress) : 1.0;
                    return Opacity(
                      opacity: opacity,
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: _CircularProgressPainter(
                          progress: progress,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 长按圆形填充动画画笔
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 实心圆，顺时针填充
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sweepAngle = progress * 2 * 3.14159265;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159265 / 2, // 从顶部开始
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
