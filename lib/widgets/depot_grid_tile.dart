import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/item.dart';
import 'building_shared_widgets.dart';

/// 仓库存取口 - 网格+轨道+箭头动画
/// [isInput] true=输入网格(存货口)，false=输出网格(取货口)
/// [showNoIcon] true=空网格显示No.svg
class DepotGridTile extends StatefulWidget {
  final Item? item;
  final bool isInput;
  final bool showNoIcon;
  final bool hasItemForButton;
  final bool isAddMode;
  final VoidCallback onToggleAddMode;

  const DepotGridTile({
    super.key,
    required this.item,
    required this.isInput,
    this.showNoIcon = false,
    this.hasItemForButton = false,
    this.isAddMode = false,
    required this.onToggleAddMode,
  });

  @override
  State<DepotGridTile> createState() => _DepotGridTileState();
}

class _DepotGridTileState extends State<DepotGridTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _arrowController;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _arrowController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final level = widget.item?.level;
    final hasItem = widget.item != null;

    const cardWidth = 265.0;
    const connectorWidth = 75.0;
    const gridWidth = 128.0;
    const trackWidth = 168.0;
    const trackHeight = 54.0;
    const buttonGap = 16.0;
    const buttonHeight = 40.0; // 胶囊按钮约40px高
    final totalWidth = cardWidth + connectorWidth + gridWidth + trackWidth;
    final totalHeight = 128.0 + buttonGap + buttonHeight;

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 仓库卡片
          Positioned(
            left: 0,
            top: 0,
            child: DepotWarehouseCard(
              item: widget.item,
              isInput: widget.isInput,
            ),
          ),
          // 网格 + 5px边框（圆角与SVG rx=15 完全对齐）
          Positioned(
            left: cardWidth + connectorWidth,
            top: 0,
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
                  if (hasItem && widget.item!.imageAssetPath.isNotEmpty)
                    Center(
                      child: Image.asset(
                        widget.item!.imageAssetPath,
                        width: 128,
                        height: 128,
                        cacheWidth: 384,
                        cacheHeight: 384,
                        fit: BoxFit.contain,
                        filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                        isAntiAlias: true,
                        errorBuilder: (_, __, ___) => _buildItemPlaceholder(),
                      ),
                    )
                  else if (hasItem)
                    Center(child: _buildItemPlaceholder())
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
            ),
          ),
          // 轨道 + 箭头动画 + 遮罩
          Positioned(
            left: cardWidth + connectorWidth + gridWidth,
            top: (128 - trackHeight) / 2,
            child: DepotTrackWithArrows(
              controller: _arrowController,
              isInput: widget.isInput,
            ),
          ),
          // 连接线（最后渲染，处于最上层，不被物品格遮挡）
          Positioned(
            left: cardWidth,
            top: 0,
            child: DepotCardConnector(hasItem: hasItem),
          ),
          // 添加/移除物品按钮（位于物品格下方水平居中）
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

  Widget _buildItemPlaceholder() {
    if (widget.item == null) return const SizedBox.shrink();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: widget.item!.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.item!.color.withValues(alpha: 0.5),
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

    final gradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xAAFFB82B),
        Color(0x00E88A11),
      ],
    );
    activeTrackPaint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, activeTrackPaint);

    final borderGradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xDDFFD266),
        Color(0x00FFBB33),
      ],
    );
    borderPaint.shader = borderGradient.createShader(rect);

    final double strokeHalf = 1.6 / 2;
    canvas.drawLine(
        Offset(0, strokeHalf), Offset(size.width, strokeHalf), borderPaint);
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
class DepotWarehouseCard extends StatelessWidget {
  final Item? item;
  final bool isInput;

  const DepotWarehouseCard({
    super.key,
    required this.item,
    required this.isInput,
  });

  @override
  Widget build(BuildContext context) {
    final hasItem = item != null;
    final displayName = hasItem ? item!.name : '——';
    final displayQuantity = hasItem ? '99999' : '——';

    // Depot_icon.svg 原始尺寸：10.243302mm × 9.0025673mm
    // 1mm = 96/25.4 px ≈ 3.7795 px
    const iconWidth = 10.243302 * 96 / 25.4; // ≈ 38.72
    const iconHeight = 9.0025673 * 96 / 25.4; // ≈ 34.03

    return Container(
      width: 265,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: const Color(0xFF696969),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 背景图片（340px原始尺寸，30%透明度，超出部分由外层Container裁剪）
          if (hasItem && item!.imageAssetPath.isNotEmpty)
            Positioned(
              left: 80,
              top: -60,
              child: Opacity(
                opacity: 0.3,
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
            child: Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 左下角：仓库图标 + 数量（文字高度与图标一致）
          Positioned(
            bottom: 10,
            left: 10,
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
        ],
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
