import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';

class ResourceItem {
  final String id;
  final String name;
  final String category;
  final Color color;
  final String imageAssetPath;
  final int level;

  ResourceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imageAssetPath,
    required this.level,
  });
}

class ResourceGridTile extends StatefulWidget {
  final ResourceItem item;
  final GlobalKey gridContainerKey;
  final bool showAddIcon;
  final VoidCallback? onAddItem;

  const ResourceGridTile({
    super.key,
    required this.item,
    required this.gridContainerKey,
    this.showAddIcon = false,
    this.onAddItem,
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

class ResourceGridTileState extends State<ResourceGridTile> {
  bool _hovering = false;
  double _tooltipBottomOffset = 8.0;
  late final SvgPicture _normalBg;
  late final SvgPicture _hoveredBg;
  bool _imageLogged = false;

  @override
  void initState() {
    super.initState();
    _normalBg = SvgPicture.string(
      gridTileSvg(widget.item.level, isHovered: false),
      fit: BoxFit.fill,
    );
    _hoveredBg = SvgPicture.string(
      gridTileSvg(widget.item.level, isHovered: true),
      fit: BoxFit.fill,
    );
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
    return gridContent;
  }
}
