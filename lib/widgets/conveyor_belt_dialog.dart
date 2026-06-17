import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';
import 'synthesis_grid.dart';

class ConveyorBeltDialog extends StatefulWidget {
  final ConveyorBelt belt;
  final List<ConveyorBelt> allBelts;
  final DataLoader dataLoader;
  final VoidCallback onStoreSingle;
  final VoidCallback onStoreLine;
  final VoidCallback onCollectAll;
  final void Function(String itemId) onCollectItem;

  const ConveyorBeltDialog({
    super.key,
    required this.belt,
    required this.allBelts,
    required this.dataLoader,
    required this.onStoreSingle,
    required this.onStoreLine,
    required this.onCollectAll,
    required this.onCollectItem,
  });

  static Future<void> show(
    BuildContext context, {
    required ConveyorBelt belt,
    required List<ConveyorBelt> allBelts,
    required DataLoader dataLoader,
    required VoidCallback onStoreSingle,
    required VoidCallback onStoreLine,
    required VoidCallback onCollectAll,
    required void Function(String itemId) onCollectItem,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => ConveyorBeltDialog(
        belt: belt,
        allBelts: allBelts,
        dataLoader: dataLoader,
        onStoreSingle: onStoreSingle,
        onStoreLine: onStoreLine,
        onCollectAll: onCollectAll,
        onCollectItem: onCollectItem,
      ),
    );
  }

  @override
  State<ConveyorBeltDialog> createState() => _ConveyorBeltDialogState();
}

class _ConveyorBeltDialogState extends State<ConveyorBeltDialog>
    with TickerProviderStateMixin {
  late AnimationController _arrowController;
  Timer? _spawnTimer;
  Timer? _simTimer;
  final List<_ItemAnim> _itemAnims = [];
  int _spawnCounter = 0;

  static const double _trackLength = 480.0;
  static const double _trackWidth = 54.0;
  static const double _itemSize = 40.0;
  static const double _slotSize = 96.0;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _spawnTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _spawnItem();
    });

    // 定时刷新以同步传送带物品状态
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _simTimer?.cancel();
    _arrowController.dispose();
    for (final anim in _itemAnims) {
      anim.controller.dispose();
    }
    super.dispose();
  }

  /// 产线上所有不同物品类型（去重，保留顺序）
  List<String> get _distinctItemIds {
    final seen = <String>{};
    final result = <String>[];
    for (final b in widget.allBelts) {
      for (final s in b.itemSegments) {
        if (s.hasItems && !seen.contains(s.itemId)) {
          seen.add(s.itemId);
          result.add(s.itemId);
        }
      }
    }
    return result;
  }

  /// 产线上是否有任何物品
  bool get _hasAnyItem => _distinctItemIds.isNotEmpty;

  void _spawnItem() {
    final itemIds = _distinctItemIds;
    if (itemIds.isEmpty) return;

    // 多个物品时依次循环播放
    final itemId = itemIds[_spawnCounter % itemIds.length];
    _spawnCounter++;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    final curveAnim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    final anim = _ItemAnim(
      controller: controller,
      curveAnim: curveAnim,
      itemId: itemId,
    );
    _itemAnims.add(anim);
    controller.forward().then((_) {
      if (mounted) {
        _itemAnims.remove(anim);
        controller.dispose();
        setState(() {});
      }
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = (screenWidth - 48).clamp(1280.0, 1460.0);

          return Container(
            width: dialogWidth,
            height: 720,
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF444444)),
            ),
            child: Stack(
              children: [
                const DialogBackgroundPattern(),
                Column(
                  children: [
                    _buildWindowInfoBar(),
                    _buildSeparator(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Column(
                          children: [
                            _buildActionButtons(),
                            const SizedBox(height: 20),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 左侧：文字说明 + 物流速度
                                  _buildDescriptionPanel(),
                                  const SizedBox(width: 20),
                                  // 右侧：轨道 + 物品网格 + 收取按钮
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _buildTrackSection(),
                                        ),
                                        const SizedBox(height: 20),
                                        _buildItemGridsSection(),
                                        const SizedBox(height: 16),
                                        _buildCollectAllButton(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWindowInfoBar() {
    return SizedBox(
      height: 77,
      child: Row(
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: 42,
            height: 42,
            child: SvgPicture.asset(
              'assets/svg/Transport_LOGO.svg',
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
          _buildSeparatorVertical(),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                '传送带',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const Spacer(),
          _buildCloseButton(),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildSeparatorVertical() {
    return Container(
      width: 2,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF444444),
    );
  }

  Widget _buildSeparator() {
    return Container(
      height: 2,
      color: const Color(0xFF444444),
    );
  }

  Widget _buildCloseButton() {
    return HoverCloseButton(
      onTap: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ActionButton(
          svgPath: 'assets/svg/recycle.svg',
          label: '收纳',
          onTap: () {
            widget.onStoreSingle();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: 30),
        ActionButton(
          svgPath: 'assets/svg/recycle.svg',
          label: '收纳整条产线',
          onTap: () {
            widget.onStoreLine();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildDescriptionPanel() {
    return const SizedBox(
      width: 440,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              // 设备文字说明：底部留空给物流速度
              Padding(
                padding: EdgeInsets.only(bottom: 72),
                child: Text(
                  '可传输固体的传输物流工具。',
                  style: TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontSize: 18,
                    height: 1.6,
                  ),
                ),
              ),
              // 物流速度信息：定位到文字说明右下角
              Positioned(
                bottom: 0,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '物流速度',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '0.5',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '单位/秒',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 轨道
            AnimatedBuilder(
              animation: _arrowController,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _ConveyorTrackPainter(
                    isActive: _hasAnyItem,
                    animationValue: _hasAnyItem ? _arrowController.value : 0,
                    trackLength: _trackLength,
                    trackWidth: _trackWidth,
                  ),
                );
              },
            ),
            // 物品动画
            ..._buildItemWidgets(),
          ],
        );
      },
    );
  }

  List<Widget> _buildItemWidgets() {
    final widgets = <Widget>[];
    const edgeFade = _trackLength * _ConveyorTrackPainter._fadeRatio;

    for (final anim in _itemAnims) {
      final dataItem =
          anim.itemId != null ? widget.dataLoader.getItem(anim.itemId!) : null;

      final itemChild =
          dataItem != null && dataItem.imageAssetPath.isNotEmpty
              ? Image.asset(
                  dataItem.imageAssetPath,
                  width: _itemSize,
                  height: _itemSize,
                  cacheWidth: 120,
                  cacheHeight: 120,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  isAntiAlias: true,
                  errorBuilder: (_, __, ___) =>
                      _buildItemPlaceholder(dataItem),
                )
              : _buildGenericItemPlaceholder();

      widgets.add(
        AnimatedBuilder(
          animation: anim.curveAnim,
          builder: (context, child) {
            final progress = anim.curveAnim.value;
            // 水平移动
            final travel = (progress - 0.5) * _trackLength;

            return LayoutBuilder(
              builder: (context, constraints) {
                final centerX = constraints.maxWidth / 2;
                final centerY = constraints.maxHeight / 2;
                final x = centerX + travel;
                final y = centerY;

                double opacity = 0.9;
                final distFromStart = progress * _trackLength;
                if (distFromStart < edgeFade) {
                  opacity = (distFromStart / edgeFade) * 0.9;
                } else if (distFromStart > _trackLength - edgeFade) {
                  opacity =
                      ((_trackLength - distFromStart) / edgeFade) * 0.9;
                }

                return Stack(
                  children: [
                    Positioned(
                      left: x - _itemSize / 2,
                      top: y - _itemSize / 2,
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 0.9),
                        child: child,
                      ),
                    ),
                  ],
                );
              },
            );
          },
          child: itemChild,
        ),
      );
    }
    return widgets;
  }

  Widget _buildItemPlaceholder(Item dataItem) {
    return Container(
      width: _itemSize,
      height: _itemSize,
      decoration: BoxDecoration(
        color: dataItem.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: dataItem.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildGenericItemPlaceholder() {
    return Container(
      width: _itemSize,
      height: _itemSize,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB82B).withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFFB82B).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildItemGridsSection() {
    final itemIds = _distinctItemIds;

    if (itemIds.isEmpty) {
      // 空传送带：显示一个灰色空网格 + 禁用的收取按钮
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildItemSlotColumn(null, false),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < itemIds.length; i++) ...[
          if (i > 0) const SizedBox(width: 20),
          _buildItemSlotColumn(itemIds[i], true),
        ],
      ],
    );
  }

  Widget _buildItemSlotColumn(String? itemId, bool isActive) {
    final dataItem =
        itemId != null ? widget.dataLoader.getItem(itemId) : null;

    return _ItemSlot(
      slotSize: _slotSize,
      dataItem: dataItem,
      isActive: isActive,
      getGridSvg: _getGridSvg,
      onCollect: itemId != null
          ? () {
              widget.onCollectItem(itemId);
              setState(() {});
            }
          : null,
    );
  }

  Widget _buildCollectAllButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: CollectAllButton(
        width: 300,
        height: 68.32774,
        enabled: _hasAnyItem,
        onTap: () {
          widget.onCollectAll();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// 物品格子 SVG（与物流桥面板一致，悬停时顶部颜色加深）
  String _getGridSvg(int? level, bool isActive, {bool isHovered = false}) {
    if (!isActive) {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
          '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="#4a4a4a"/>'
          '</svg>';
    }

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
    final stopColor = isHovered ? '#252525' : '#696969';

    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">'
        '<stop offset="0" stop-color="$stopColor"/>'
        '<stop offset="0.7" stop-color="$stopColor"/>'
        '<stop offset="1" stop-color="$endColor"/>'
        '</linearGradient></defs>'
        '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="${hasItem ? "url(#g)" : "#696969"}"/>'
        '${hasItem ? '<path d="m 1,118 c 2,5.8 7.6,10 14,10 h 98 c 6.4,0 12,-4.2 14,-10 z" fill="$tagColor"/>' : ''}'
        '</svg>';
  }
}

class _ItemAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String? itemId;

  _ItemAnim({
    required this.controller,
    required this.curveAnim,
    this.itemId,
  });
}

/// 物品网格 + 收取按钮（带悬停效果，与普通设备弹窗物品栏一致）
class _ItemSlot extends StatefulWidget {
  final double slotSize;
  final Item? dataItem;
  final bool isActive;
  final String Function(int? level, bool isActive, {bool isHovered}) getGridSvg;
  final VoidCallback? onCollect;

  const _ItemSlot({
    required this.slotSize,
    required this.dataItem,
    required this.isActive,
    required this.getGridSvg,
    this.onCollect,
  });

  @override
  State<_ItemSlot> createState() => _ItemSlotState();
}

class _ItemSlotState extends State<_ItemSlot> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final dataItem = widget.dataItem;
    final level = dataItem?.level;
    final slotSize = widget.slotSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: SizedBox(
            width: slotSize,
            height: slotSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SvgPicture.string(
                  widget.getGridSvg(level, widget.isActive,
                      isHovered: _hovering),
                  fit: BoxFit.fill,
                ),
                if (dataItem != null && dataItem.imageAssetPath.isNotEmpty)
                  Center(
                    child: AnimatedScale(
                      scale: _hovering ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: AnimatedOpacity(
                        opacity: widget.isActive ? 1.0 : 0.3,
                        duration: const Duration(milliseconds: 300),
                        child: Image.asset(
                          dataItem.imageAssetPath,
                          width: slotSize,
                          height: slotSize,
                          cacheWidth: 192,
                          cacheHeight: 192,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          isAntiAlias: true,
                          errorBuilder: (_, __, ___) =>
                              _buildItemPlaceholder(dataItem),
                        ),
                      ),
                    ),
                  ),
                if (_hovering && dataItem != null)
                  Positioned(
                    bottom: 8,
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
                            dataItem.name,
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
                  )
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SingleCollectButton(
          enabled: widget.isActive && widget.onCollect != null,
          onTap: widget.onCollect ?? () {},
        ),
      ],
    );
  }

  Widget _buildItemPlaceholder(Item dataItem) {
    return Container(
      width: widget.slotSize,
      height: widget.slotSize,
      decoration: BoxDecoration(
        color: dataItem.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: dataItem.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 单独收取按钮（白色 Collect_A_button.svg + "收取"文字）
class _SingleCollectButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _SingleCollectButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_SingleCollectButton> createState() => _SingleCollectButtonState();
}

class _SingleCollectButtonState extends State<_SingleCollectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    // SVG 原始尺寸 207.77 x 87.6，宽度与物品网格一致（96）
    const width = 96.0;
    const height = 40.4;
    final textColor =
        enabled ? const Color(0xFF222222) : const Color(0xFF666666);

    // 悬停时呈现灰色预览
    final svgColor = !enabled
        ? const Color(0xFF666666)
        : _hovered
            ? const Color(0xFF888888)
            : Colors.white;

    return GestureDetector(
      onTap: enabled ? widget.onTap : null,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedScale(
          scale: enabled && _hovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter:
                      ColorFilter.mode(svgColor, BlendMode.srcIn),
                  child: SvgPicture.asset(
                    'assets/svg/Collect_A_button.svg',
                    width: width,
                    height: height,
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      '收取',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向传送带轨道绘制器（参考物流桥 _BridgeTrackPainter._drawTrackA，
/// 但改为纯水平方向，无等轴测投影）
class _ConveyorTrackPainter extends CustomPainter {
  final double animationValue;
  final double trackLength;
  final double trackWidth;
  final bool isActive;

  static const double _fadeRatio = 0.35;

  _ConveyorTrackPainter({
    required this.animationValue,
    required this.trackLength,
    required this.trackWidth,
    this.isActive = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halfLen = trackLength / 2;
    final halfWidth = trackWidth / 2;

    // 1. 顶面顶点（水平矩形，z=0）
    final p1 = Offset(center.dx - halfLen, center.dy - halfWidth);
    final p2 = Offset(center.dx + halfLen, center.dy - halfWidth);
    final p3 = Offset(center.dx + halfLen, center.dy + halfWidth);
    final p4 = Offset(center.dx - halfLen, center.dy + halfWidth);

    final topPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 2. 顶面渐变（水平方向，两端淡出）
    final gradStart = Offset(center.dx - halfLen, center.dy);
    final gradEnd = Offset(center.dx + halfLen, center.dy);

    final topGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00E88A11),
              Color(0xAAFFB82B),
              Color(0xAAFFB82B),
              Color(0x00E88A11),
            ]
          : const [
              Color(0x00444444),
              Color(0xAA666666),
              Color(0xAA666666),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final trackPaint = Paint()
      ..shader = topGradient
      ..style = PaintingStyle.fill;

    // 绘制顶面
    canvas.drawPath(topPath, trackPaint);

    // 3. 边框线条（同步渐变）
    final borderGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00FFBB33),
              Color(0xDDFFD266),
              Color(0xDDFFD266),
              Color(0x00FFBB33),
            ]
          : const [
              Color(0x00444444),
              Color(0xDD777777),
              Color(0xDD777777),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final borderPaint = Paint()
      ..shader = borderGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 绘制长边边框
    canvas.drawLine(p1, p2, borderPaint);
    canvas.drawLine(p4, p3, borderPaint);

    // 4. 绘制箭头动画（水平流动）
    canvas.save();
    canvas.clipPath(topPath);

    for (int a = 0; a < 3; a++) {
      final t = (animationValue + a / 3.0) % 1.0;
      final arrowX = center.dx - halfLen + t * trackLength;

      final edgeFadeLen = trackLength * _fadeRatio;
      double opacity = 0.9;
      final distFromStart = t * trackLength;
      if (distFromStart < edgeFadeLen) {
        opacity = (distFromStart / edgeFadeLen) * 0.9;
      } else if (distFromStart > trackLength - edgeFadeLen) {
        opacity = ((trackLength - distFromStart) / edgeFadeLen) * 0.9;
      }

      final arrowPaint = Paint()
        ..color = (isActive ? Colors.white : const Color(0xFF999999))
            .withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      // 水平三角形箭头（指向右）
      const arrowHalfH = 3.5;
      final tip = Offset(arrowX + 5.5, center.dy);
      final leftBack = Offset(arrowX - 4.5, center.dy - arrowHalfH);
      final rightBack = Offset(arrowX - 4.5, center.dy + arrowHalfH);

      final arrowPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(leftBack.dx, leftBack.dy)
        ..lineTo(rightBack.dx, rightBack.dy)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ConveyorTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isActive != isActive;
  }
}
