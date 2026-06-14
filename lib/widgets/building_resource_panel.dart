import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  return '<svg xmlns="http://www.w3.org/2000/svg" width="93.44" height="93.621" viewBox="0 0 93.44 93.621">'
      '<defs><linearGradient id="g" x1="902.412" y1="521.936" x2="902.412" y2="649.936" gradientUnits="userSpaceOnUse">'
      '<stop offset="0" stop-color="$stopColor"/>'
      '<stop offset="0.7" stop-color="$stopColor"/>'
      '<stop offset="1" stop-color="$endColor"/>'
      '</linearGradient></defs>'
      '<g transform="matrix(0.73,0,0,0.73,-610.056,-380.923)">'
      '<rect x="838.412" y="521.812" width="128" height="128.249" rx="15" ry="15" fill="url(#g)"/>'
      '<path d="m 839.26,640.061 c 2.048,5.831 7.585,9.991 14.131,10 h 98.043 c 6.546,-0.009 12.083,-4.169 14.131,-10 z" fill="$tagColor"/>'
      '</g></svg>';
}

class ResourceGridTileState extends State<ResourceGridTile> {
  bool _hovering = false;
  double _tooltipBottomOffset = 8.0;

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
    return MouseRegion(
      onEnter: _onEnter,
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            SvgPicture.string(
              gridTileSvg(widget.item.level, isHovered: _hovering),
              fit: BoxFit.fill,
            ),
            Center(
              child: widget.item.imageAssetPath.isNotEmpty
                  ? Image.asset(
                      widget.item.imageAssetPath,
                      width: 93,
                      height: 93,
                      cacheWidth: 279,
                      cacheHeight: 279,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      isAntiAlias: true,
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
            if (widget.showAddIcon)
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: widget.onAddItem,
                  child: Container(
                    width: 21.9,
                    height: 21.9,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/svg/add.svg',
                        width: 12,
                        height: 12,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF212121),
                          BlendMode.srcIn,
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
      ),
    );
  }
}
