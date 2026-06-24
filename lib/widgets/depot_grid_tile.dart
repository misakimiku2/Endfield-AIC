import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/item.dart';
import 'item_description_dialog.dart';

/// 仓库存货口的物品条目：物品数据 + 是否当前正在进入 + 仓库数量
class DepotItemEntry {
  final Item item;
  final bool isActive;
  final int? warehouseQuantity;

  const DepotItemEntry({
    required this.item,
    required this.isActive,
    this.warehouseQuantity,
  });
}

/// 仓库轨道物品动画数据
class _DepotItemAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String itemId;
  final Item? displayItem;

  _DepotItemAnim({
    required this.controller,
    required this.curveAnim,
    required this.itemId,
    this.displayItem,
  });
}

/// 仓库存取口 - 网格+轨道+箭头动画
/// [isInput] true=输入网格(存货口)，false=输出网格(取货口)
/// [showNoIcon] true=空网格显示No.svg
/// [showButton] true=显示添加/移除物品按钮（仅仓库取货口）
/// [allItems] 所有不同物品条目列表（仓库存货口多卡片场景）
/// [item] 单个物品（仓库取货口场景，与 allItems 互斥）
/// [warehouseQuantity] 当前物品的全局仓库数量，null 表示无物品
class DepotGridTile extends StatefulWidget {
  final Item? item;
  final List<DepotItemEntry> allItems;
  final bool isInput;
  final bool showNoIcon;
  final bool hasItemForButton;
  final bool isAddMode;
  final bool showButton;
  final int? warehouseQuantity;
  final VoidCallback onToggleAddMode;

  const DepotGridTile({
    super.key,
    this.item,
    this.allItems = const [],
    required this.isInput,
    this.showNoIcon = false,
    this.hasItemForButton = false,
    this.isAddMode = false,
    this.showButton = true,
    this.warehouseQuantity,
    required this.onToggleAddMode,
  });

  @override
  State<DepotGridTile> createState() => _DepotGridTileState();
}

class _DepotGridTileState extends State<DepotGridTile>
    with TickerProviderStateMixin {
  late AnimationController _arrowController;
  final List<_DepotItemAnim> _itemAnims = [];
  /// 多卡片模式下，跟踪每种物品的上一次仓库数量
  final Map<String, int> _previousQuantities = {};

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    // 单卡片模式：记录初始数量
    if (widget.warehouseQuantity != null && widget.item != null) {
      _previousQuantities[widget.item!.id] = widget.warehouseQuantity!;
    }
    // 多卡片模式：记录所有物品的初始数量
    _syncAllPreviousQuantities();
  }

  void _syncAllPreviousQuantities() {
    for (final entry in widget.allItems) {
      if (entry.warehouseQuantity != null) {
        _previousQuantities[entry.item.id] = entry.warehouseQuantity!;
      }
    }
    if (widget.item != null && widget.warehouseQuantity != null) {
      _previousQuantities[widget.item!.id] = widget.warehouseQuantity!;
    }
  }

  @override
  void didUpdateWidget(DepotGridTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeCreateItemAnimations();
  }

  @override
  void dispose() {
    _arrowController.dispose();
    for (final anim in _itemAnims) {
      anim.controller.dispose();
    }
    super.dispose();
  }

  /// 检测仓库数量变化并创建物品动画
  void _maybeCreateItemAnimations() {
    // 多卡片模式
    if (widget.allItems.isNotEmpty) {
      for (final entry in widget.allItems) {
        final currentQty = entry.warehouseQuantity;
        if (currentQty == null) continue;
        final prevQty = _previousQuantities[entry.item.id];
        if (prevQty == null) {
          _previousQuantities[entry.item.id] = currentQty;
          continue;
        }
        // 存货口：数量增加时触发动画
        if (widget.isInput && currentQty > prevQty) {
          final delta = currentQty - prevQty;
          _createItemAnimations(delta, entry.item.id,
              itemForIcon: entry.item);
        }
        _previousQuantities[entry.item.id] = currentQty;
      }
      return;
    }

    // 单卡片模式
    final currentQty = widget.warehouseQuantity;
    if (currentQty == null || widget.item == null) {
      if (currentQty != null && widget.item != null) {
        _previousQuantities[widget.item!.id] = currentQty;
      }
      return;
    }

    final prevQty = _previousQuantities[widget.item!.id];
    if (prevQty == null) {
      _previousQuantities[widget.item!.id] = currentQty;
      return;
    }

    final bool shouldAnimate = widget.isInput
        ? currentQty > prevQty
        : currentQty < prevQty;

    if (shouldAnimate) {
      final delta = (currentQty - prevQty).abs();
      _createItemAnimations(delta, widget.item!.id);
    }

    _previousQuantities[widget.item!.id] = currentQty;
  }

  void _createItemAnimations(int delta, String itemId, {Item? itemForIcon}) {
    if (itemId.isEmpty) return;

    // 固定动画时长（匹配传送带速度 0.5 单位/秒，单物品轨道移动约 1.5s）
    const int animDurationMs = 1500;
    // 每个物品动画间的错开延迟
    const int staggerDelayMs = 300;

    final iconItem = itemForIcon ?? widget.item;

    for (int i = 0; i < delta; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: animDurationMs),
      );
      final curveAnim = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOutCubic,
      );
      final anim = _DepotItemAnim(
        controller: controller,
        curveAnim: curveAnim,
        itemId: itemId,
        displayItem: iconItem,
      );
      _itemAnims.add(anim);

      // 错开启动：第 i 个动画延迟 i * staggerDelayMs 后开始
      Future.delayed(Duration(milliseconds: i * staggerDelayMs), () {
        if (mounted) {
          controller.forward().then((_) {
            if (mounted) {
              _itemAnims.remove(anim);
              controller.dispose();
            }
          });
        }
      });
    }
  }

  /// 构建轨道上的物品动画 widget 列表（每个动画自带 displayItem，防止不同物品批次混用）
  List<Widget> _buildItemAnimWidgets({Item? defaultDisplayItem}) {
    if (_itemAnims.isEmpty) return [];

    const double itemSize = 40.0;
    const double trackWidth = 168.0;
    const double trackHeight = 54.0;
    const double entryOffset = itemSize;

    const double totalTravel = trackWidth + entryOffset;

    final trackGradient = widget.isInput
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
          );

    const trackRectInMask = Rect.fromLTWH(
      entryOffset, 0, trackWidth, trackHeight,
    );

    final List<Widget> widgets = [];
    for (final anim in _itemAnims) {
      // 每个动画使用自己的 displayItem，不受其他批次影响
      final item = anim.displayItem ?? defaultDisplayItem;
      if (item == null) continue;
      const double itemY = (trackHeight - itemSize) / 2;

      widgets.add(
        Positioned(
          left: -entryOffset,
          top: 0,
          width: totalTravel,
          height: trackHeight,
          child: ClipRect(
            child: ShaderMask(
              shaderCallback: (_) =>
                  trackGradient.createShader(trackRectInMask),
              child: AnimatedBuilder(
                animation: anim.curveAnim,
                builder: (context, child) {
                  final double progress = anim.curveAnim.value;
                  final double x = widget.isInput
                      ? trackWidth - progress * totalTravel
                      : progress * totalTravel - entryOffset;
                  return Transform.translate(
                    offset: Offset(x, itemY),
                    child: child,
                  );
                },
                child: Opacity(
                  opacity: 0.9,
                  child: item.imageAssetPath.isNotEmpty
                      ? Image.asset(
                          item.imageAssetPath,
                          width: itemSize,
                          height: itemSize,
                          cacheWidth: 120,
                          cacheHeight: 120,
                          fit: BoxFit.contain,
                          filterQuality: kIsWeb
                              ? FilterQuality.high
                              : FilterQuality.medium,
                          isAntiAlias: true,
                          errorBuilder: (_, __, ___) =>
                              _buildItemPlaceholder(item),
                        )
                      : _buildItemPlaceholder(item),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  String _getGridSvg(int? level) {
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
    final hasItem = level != null;

    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">'
        '<stop offset="0" stop-color="#696969"/>'
        '<stop offset="0.7" stop-color="#696969"/>'
        '<stop offset="1" stop-color="$endColor"/>'
        '</linearGradient></defs>'
        '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="${hasItem ? "url(#g)" : "#696969"}"/>'
        '${hasItem ? '<path d="m 1,118 c 2,5.8 7.6,10 14,10 h 98 c 6.4,0 12,-4.2 14,-10 z" fill="$tagColor"/>' : ''}'
        '</svg>';
  }

  /// 构建物品网格组件（提取为公共方法）
  Widget _buildItemGrid({Item? gridItem}) {
    final level = gridItem?.level;
    final hasItem = gridItem != null;
    return GestureDetector(
      onTap: hasItem
          ? () => ItemDescriptionDialog.show(context, item: gridItem)
          : null,
      child: Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFF7F7F7F),
          width: 5,
        ),
        borderRadius: BorderRadius.circular(15),
        color: const Color(0xFF696969),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.string(
            _getGridSvg(level),
            fit: BoxFit.fill,
          ),
              if (hasItem && gridItem.imageAssetPath.isNotEmpty)
            Center(
              child: Image.asset(
                gridItem.imageAssetPath,
                width: 128,
                height: 128,
                cacheWidth: 384,
                cacheHeight: 384,
                fit: BoxFit.contain,
                filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, __, ___) => _buildItemPlaceholder(gridItem),
              ),
            )
          else if (hasItem)
            Center(child: _buildItemPlaceholder(gridItem))
          else if (widget.showNoIcon)
            Center(
              child: SvgPicture.asset(
                'assets/svg/No.svg',
                width: 60,
                height: 60,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF808080),
                  BlendMode.srcIn,
                ),
              ),
            ),
        ],
      ),
      ), // GestureDetector close
    );
  }

  @override
  Widget build(BuildContext context) {
    // 多卡片布局（仓库存货口）
    if (widget.allItems.isNotEmpty && widget.isInput) {
      return _buildMultiCardLayout();
    }
    // 单卡片布局（原有逻辑，仓库取货口 / 空存货口）
    return _buildSingleCardLayout();
  }

  /// 单卡片布局（保持原有逻辑兼容）
  Widget _buildSingleCardLayout() {
    final level = widget.item?.level;
    final hasItem = widget.item != null;

    const cardWidth = 265.0;
    const connectorWidth = 75.0;
    const gridWidth = 128.0;
    const trackWidth = 168.0;
    const trackHeight = 54.0;
    const buttonGap = 16.0;
    const buttonHeight = 40.0;
    const totalWidth = cardWidth + connectorWidth + gridWidth + trackWidth;
    final totalHeight = widget.showButton
        ? 128.0 + buttonGap + buttonHeight
        : 128.0;

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: GestureDetector(
              onTap: widget.item != null
                  ? () => ItemDescriptionDialog.show(context, item: widget.item!)
                  : null,
              child: DepotWarehouseCard(
                item: widget.item,
                isInput: widget.isInput,
                quantity: widget.warehouseQuantity,
              ),
            ),
          ),
          Positioned(
            left: cardWidth + connectorWidth,
            top: 0,
            child: _buildItemGrid(
              // 动画期间优先使用动画物品，保持网格与轨道同步
              gridItem: _itemAnims.isNotEmpty
                  ? (_itemAnims.first.displayItem ?? widget.item)
                  : widget.item,
            ),
          ),
          Positioned(
            left: cardWidth + connectorWidth + gridWidth,
            top: (128 - trackHeight) / 2,
            child: SizedBox(
              width: trackWidth,
              height: trackHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DepotTrackWithArrows(
                    controller: _arrowController,
                    isInput: widget.isInput,
                  ),
                  ..._buildItemAnimWidgets(defaultDisplayItem: widget.item),
                ],
              ),
            ),
          ),
          Positioned(
            left: cardWidth,
            top: 0,
            child: DepotCardConnector(hasItem: hasItem),
          ),
          if (widget.showButton)
            Positioned(
              left: cardWidth + connectorWidth,
              top: 128 + buttonGap,
              child: SizedBox(
                width: gridWidth,
                child: Center(
                  child: DepotCapsuleButton(
                    hasItem: widget.hasItemForButton,
                    isAddMode: widget.isAddMode,
                    onToggleAddMode: widget.onToggleAddMode,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 多卡片布局（仓库存货口）
  Widget _buildMultiCardLayout() {
    const cardWidth = 265.0;
    const cardHeight = 128.0;
    const connectorWidth = 75.0;
    const gridSize = 128.0;
    const trackWidth = 168.0;
    const trackHeight = 54.0;
    const cardGap = 8.0;
    const totalWidth = cardWidth + connectorWidth + gridSize + trackWidth;

    final items = widget.allItems;
    final cardCount = items.length;
    final totalCardsHeight = cardCount * cardHeight + (cardCount - 1) * cardGap;
    final totalHeight = totalCardsHeight > gridSize ? totalCardsHeight : gridSize;
    final gridTop = (totalHeight - gridSize) / 2;
    final trackTop = gridTop + (gridSize - trackHeight) / 2;

    // 若轨道上正在播放物品动画，网格与卡片应锁定到动画物品，
    // 避免动画未播放完就跳到下一个物品（下游物品已变化但动画尚未结束）
    String? animatingItemId;
    if (_itemAnims.isNotEmpty) {
      animatingItemId = _itemAnims.first.itemId;
    }

    // 找到当前活跃物品（优先动画中的物品）
    DepotItemEntry? activeEntry;
    if (animatingItemId != null) {
      for (final e in items) {
        if (e.item.id == animatingItemId) { activeEntry = e; break; }
      }
    }
    if (activeEntry == null) {
      for (final e in items) {
        if (e.isActive) { activeEntry = e; break; }
      }
    }
    activeEntry ??= items.first;

    // 收集每条连接线的活跃状态（动画物品优先）
    final activeStates = items.map((e) {
      if (animatingItemId != null && e.item.id == animatingItemId) return true;
      if (animatingItemId != null) return false;
      return e.isActive;
    }).toList();

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 多张仓库卡片（垂直堆叠）
          for (int i = 0; i < cardCount; i++)
            Positioned(
              left: 0,
              top: i * (cardHeight + cardGap),
              child: GestureDetector(
                onTap: () {
                  ItemDescriptionDialog.show(context, item: items[i].item);
                },
                child: DepotWarehouseCard(
                  item: items[i].item,
                  isInput: true,
                  quantity: items[i].warehouseQuantity,
                  // 动画期间锁定高亮到动画物品
                  isActive: animatingItemId != null
                      ? items[i].item.id == animatingItemId
                      : items[i].isActive,
                ),
              ),
            ),
          // 共享的物品输入网格（动画期间显示动画物品，否则显示下游物品）
          Positioned(
            left: cardWidth + connectorWidth,
            top: gridTop,
            child: _buildItemGrid(
              gridItem: animatingItemId != null
                  ? (_itemAnims.first.displayItem ?? activeEntry.item)
                  : activeEntry.item,
            ),
          ),
          // 多卡连接线区域（在网格之后渲染，确保右端圆头不被网格遮挡）
          Positioned(
            left: cardWidth,
            top: 0,
            child: SizedBox(
              width: connectorWidth,
              height: totalHeight,
              child: CustomPaint(
                painter: MultiDepotCardConnectorPainter(
                  cardCount: cardCount,
                  cardHeight: cardHeight,
                  cardGap: cardGap,
                  gridTop: gridTop,
                  gridSize: gridSize,
                  totalHeight: totalHeight,
                  activeStates: activeStates,
                ),
              ),
            ),
          ),
          // 轨道 + 箭头动画
          Positioned(
            left: cardWidth + connectorWidth + gridSize,
            top: trackTop,
            child: SizedBox(
              width: trackWidth,
              height: trackHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DepotTrackWithArrows(
                    controller: _arrowController,
                    isInput: true,
                  ),
                  ..._buildItemAnimWidgets(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemPlaceholder(Item item) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: item.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 仓库存取口 - 轨道 + 箭头动画 + 遮罩蒙版
/// 轨道使用 dialog_track.svg，箭头从轨道外部开始循环移动
/// 存货口(isInput=true)：箭头指向左，从右向左移动
/// 取货口(isInput=false)：箭头指向右，从左向右移动
/// 遮罩：左边不透明，右边完全透明，覆盖整个轨道包括箭头
class DepotTrackWithArrows extends StatelessWidget {
  final AnimationController controller;
  final bool isInput;

  const DepotTrackWithArrows({
    super.key,
    required this.controller,
    required this.isInput,
  });

  @override
  Widget build(BuildContext context) {
    const trackWidth = 168.0;
    const trackHeight = 54.0;

    return SizedBox(
      width: trackWidth,
      height: trackHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(trackWidth, trackHeight),
            painter: DepotTrackPainter(
              animationValue: controller.value,
              isInput: isInput,
            ),
          );
        },
      ),
    );
  }
}

class DepotTrackPainter extends CustomPainter {
  final double animationValue;
  final bool isInput;

  DepotTrackPainter({
    required this.animationValue,
    required this.isInput,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    final Paint activeTrackPaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    const gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xAAFFB82B),
        Color(0x00E88A11),
      ],
    );
    activeTrackPaint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, activeTrackPaint);

    const borderGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xDDFFD266),
        Color(0x00FFBB33),
      ],
    );
    borderPaint.shader = borderGradient.createShader(rect);

    const double strokeHalf = 1.6 / 2;
    canvas.drawLine(
        const Offset(0, strokeHalf), Offset(size.width, strokeHalf), borderPaint);
    canvas.drawLine(Offset(0, size.height - strokeHalf),
        Offset(size.width, size.height - strokeHalf), borderPaint);

    canvas.save();
    canvas.clipRect(rect);
    final double centerY = size.height / 2;

    for (int anim = 0; anim < 2; anim++) {
      final double t = (animationValue + anim / 2.0) % 1.0;
      final double arrowX =
          isInput ? size.width - (t * size.width) : t * size.width;

      final double opacity =
          (1.0 - (arrowX / size.width)).clamp(0.0, 1.0) * 0.9;

      final Paint arrowPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final path = Path();
      if (isInput) {
        path.moveTo(arrowX + 4, centerY - 6);
        path.lineTo(arrowX - 6, centerY);
        path.lineTo(arrowX + 4, centerY + 6);
      } else {
        path.moveTo(arrowX - 4, centerY - 6);
        path.lineTo(arrowX + 6, centerY);
        path.lineTo(arrowX - 4, centerY + 6);
      }
      path.close();

      canvas.drawPath(path, arrowPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DepotTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isInput != isInput;
  }
}

/// 仓库取货口 - 白色胶囊按钮（添加物品 / 移除物品）
class DepotCapsuleButton extends StatefulWidget {
  final bool hasItem;
  final bool isAddMode;
  final VoidCallback onToggleAddMode;

  const DepotCapsuleButton({
    super.key,
    required this.hasItem,
    required this.isAddMode,
    required this.onToggleAddMode,
  });

  @override
  State<DepotCapsuleButton> createState() => _DepotCapsuleButtonState();
}

class _DepotCapsuleButtonState extends State<DepotCapsuleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _iconRotationController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _iconRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.hasItem) {
      _iconRotationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(DepotCapsuleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasItem != oldWidget.hasItem) {
      if (widget.hasItem) {
        _iconRotationController.forward();
      } else {
        _iconRotationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _iconRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 三种状态：
    // 1. 有物品 → 红色背景 + 白色文字 "移除物品"
    // 2. 无物品且选择中(isAddMode) → 灰白背景 + 白色文字 "取消选择"
    // 3. 无物品未选择 → 白色背景 + 深色文字 "添加物品"
    final bool isRemoving = widget.hasItem && !widget.isAddMode;
    final bool isCancelling = !widget.hasItem && widget.isAddMode;

    String label;
    Color bgColor;
    Color bgColorHover;
    Color textColor;

    if (isRemoving) {
      label = '移除物品';
      bgColor = const Color(0xFFE53935);
      bgColorHover = const Color(0xFF8A1717);
      textColor = Colors.white;
    } else if (isCancelling) {
      label = '取消选择';
      bgColor = const Color(0xFFCCCCCC);
      bgColorHover = const Color(0xFF777777);
      textColor = Colors.white;
    } else {
      label = '添加物品';
      bgColor = Colors.white;
      bgColorHover = const Color(0xFFA3A3A3);
      textColor = const Color(0xFF212121);
    }

    final effectiveBgColor = _isHovered ? bgColorHover : bgColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onToggleAddMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: effectiveBgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              RotationTransition(
                turns: Tween<double>(begin: 0.0, end: 0.125).animate(
                  _iconRotationController,
                ),
                child: SvgPicture.asset(
                  'assets/svg/add.svg',
                  width: 16,
                  height: 16,
                  colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 仓库卡片 — 显示当前正在输入/输出的物品信息
/// 圆角矩形，265×128，无描边
/// 左上角：物品名称；左下角：仓库图标 + 数量；右侧：物品图片（340px背景图，30%透明度）
/// [isActive] 当前物品是否正在进入（活跃卡片亮度更高，非活跃变暗）
class DepotWarehouseCard extends StatelessWidget {
  final Item? item;
  final bool isInput;
  final int? quantity;
  final bool isActive;

  const DepotWarehouseCard({
    super.key,
    required this.item,
    required this.isInput,
    this.quantity,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasItem = item != null;
    final displayName = hasItem ? item!.name : '——';
    final displayQuantity = hasItem
        ? (quantity != null ? quantity.toString() : '——')
        : '——';

    // Depot_icon.svg 原始尺寸：10.243302mm × 9.0025673mm
    // 1mm = 96/25.4 px ≈ 3.7795 px
    const iconWidth = 10.243302 * 96 / 25.4; // ≈ 38.72
    const iconHeight = 9.0025673 * 96 / 25.4; // ≈ 34.03

    // 非活跃卡片整体变暗
    final bgOpacity = isActive ? 1.0 : 0.45;
    final textOpacity = isActive ? 1.0 : 0.4;
    final imageOpacity = isActive ? 0.55 : 0.25;
    final borderColor = isActive
        ? Colors.transparent
        : const Color(0xFF555555);

    return Container(
      width: 265,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: const Color(0xFF696969),
        border: Border.all(color: borderColor, width: isActive ? 0 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: bgOpacity,
        child: Stack(
          children: [
            // 背景图片（活跃时提高透明度，非活跃时变暗）
            if (hasItem && item!.imageAssetPath.isNotEmpty)
              Positioned(
                left: 80,
                top: -60,
                child: Opacity(
                  opacity: imageOpacity,
                  child: Image.asset(
                    item!.imageAssetPath,
                    width: 256,
                    height: 256,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // 左上角：物品名称
            Positioned(
              top: 10,
              left: 10,
              child: Opacity(
                opacity: textOpacity,
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // 左下角：仓库图标 + 数量（文字高度与图标一致）
            Positioned(
              bottom: 10,
              left: 10,
              child: Opacity(
                opacity: textOpacity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/svg/Depot_icon.svg',
                      width: iconWidth,
                      height: iconHeight,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      displayQuantity,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: iconHeight,
                        height: 1.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 仓库卡片与物品格之间的连接线
/// 75px宽，水平线 + 两端圆圈，风格同普通设备 TrackJointsPainter
/// 有物品传输时金色；无物品时灰白色
class DepotCardConnector extends StatelessWidget {
  final bool hasItem;

  const DepotCardConnector({super.key, required this.hasItem});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 75,
      height: 128,
      child: CustomPaint(
        painter: DepotCardConnectorPainter(hasItem: hasItem),
      ),
    );
  }
}

class DepotCardConnectorPainter extends CustomPainter {
  final bool hasItem;

  const DepotCardConnectorPainter({required this.hasItem});

  @override
  void paint(Canvas canvas, Size size) {
    final color =
        hasItem ? const Color(0xFFEBAD26) : const Color(0xFFCCCCCC);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = color;

    final circlePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final centerY = size.height / 2;

    // 水平连接线
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);

    // 左端点圆圈（靠近仓库卡片）
    canvas.drawCircle(Offset(0, centerY), 6.0, circlePaint);

    // 右端点圆圈（靠近物品格）
    canvas.drawCircle(Offset(size.width, centerY), 6.0, circlePaint);
  }

  @override
  bool shouldRepaint(covariant DepotCardConnectorPainter oldDelegate) {
    return oldDelegate.hasItem != hasItem;
  }
}

/// 多卡片连接线绘制器：汇总所有卡片到一条垂直骨干线，
/// 再从骨干线画出一条水平线连接到物品格。
/// 样式参考普通设备弹窗的 TrackJointsPainter：
///   Card1 ──┐
///   Card2 ──┼── Grid ── Track
///   Card3 ──┘
/// 活跃卡片路径高亮为金色，非活跃为灰色。
class MultiDepotCardConnectorPainter extends CustomPainter {
  final int cardCount;
  final double cardHeight;
  final double cardGap;
  final double gridTop;
  final double gridSize;
  final double totalHeight;
  final List<bool> activeStates;

  const MultiDepotCardConnectorPainter({
    required this.cardCount,
    required this.cardHeight,
    required this.cardGap,
    required this.gridTop,
    required this.gridSize,
    required this.totalHeight,
    required this.activeStates,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cardCount == 0) return;

    // ── 静态骨架颜色 ──
    final Paint linkPaint = Paint()
      ..color = const Color(0xFF6E6E6E)
      ..style = PaintingStyle.fill;

    final Paint gridCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final Paint cardCirclePaint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.fill;

    // 骨干线 X 坐标（连接器区域 75px 宽的中间偏左）
    const double backboneX = 35.0;
    const double linkHalfH = 3.3; // 连接线半高

    // 网格中心 Y（在连接器坐标空间内）
    final double gridCenterY = gridTop + gridSize / 2;

    // ── 1. 垂直骨干线（从第一张卡片到最后一张卡片，覆盖网格中心） ──
    final double firstCardY = cardHeight / 2;
    final double lastCardY =
        (cardCount - 1) * (cardHeight + cardGap) + cardHeight / 2;
    final double backboneTop =
        firstCardY < gridCenterY ? firstCardY : gridCenterY;
    final double backboneBottom =
        lastCardY > gridCenterY ? lastCardY : gridCenterY;
    canvas.drawRect(
      Rect.fromLTRB(
          backboneX - 2.5, backboneTop, backboneX + 2.5, backboneBottom),
      linkPaint,
    );

    // ── 2. 每张卡片 → 骨干线的水平连接 ──
    for (int i = 0; i < cardCount; i++) {
      final double cardCenterY =
          i * (cardHeight + cardGap) + cardHeight / 2;
      canvas.drawRect(
        Rect.fromLTRB(
            0, cardCenterY - linkHalfH, backboneX + 2.5, cardCenterY + linkHalfH),
        linkPaint,
      );
      // 卡片端连接圆
      canvas.drawCircle(Offset(0, cardCenterY), 6.0, cardCirclePaint);
    }

    // ── 3. 骨干线 → 物品格的单条水平连接 ──
    canvas.drawRect(
      Rect.fromLTRB(backboneX - 2.5, gridCenterY - linkHalfH,
          size.width, gridCenterY + linkHalfH),
      linkPaint,
    );

    // 物品格端连接圆
    canvas.drawCircle(Offset(size.width, gridCenterY), 6.0, gridCirclePaint);

    // ── 4. 活跃卡片的高亮路径（金色，从卡片 → 骨干 → 网格） ──
    final Paint activeLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEBAD26);

    final Paint activeCirclePaint = Paint()
      ..color = const Color(0xFFEBAD26)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < cardCount; i++) {
      if (i >= activeStates.length || !activeStates[i]) continue;

      final double cardCenterY =
          i * (cardHeight + cardGap) + cardHeight / 2;

      // 高亮路径：卡片 → 骨干 → 网格
      final path = Path()
        ..moveTo(0, cardCenterY)
        ..lineTo(backboneX, cardCenterY)
        ..lineTo(backboneX, gridCenterY)
        ..lineTo(size.width, gridCenterY);
      canvas.drawPath(path, activeLinePaint);

      // 卡片端高亮圆
      canvas.drawCircle(Offset(0, cardCenterY), 6.0, activeCirclePaint);

      // 骨干转折点高亮圆
      canvas.drawCircle(
          Offset(backboneX, cardCenterY), 5.0, activeCirclePaint);
    }

    // 网格端活跃圆（覆盖在白色圆上）
    if (activeStates.any((a) => a)) {
      canvas.drawCircle(
          Offset(size.width, gridCenterY), 6.0, activeCirclePaint);
    }
  }

  @override
  bool shouldRepaint(covariant MultiDepotCardConnectorPainter oldDelegate) {
    return oldDelegate.cardCount != cardCount ||
        oldDelegate.cardHeight != cardHeight ||
        oldDelegate.cardGap != cardGap ||
        oldDelegate.gridTop != gridTop ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.totalHeight != totalHeight;
  }
}
