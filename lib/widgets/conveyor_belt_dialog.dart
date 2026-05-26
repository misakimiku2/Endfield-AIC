import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../data/data_loader.dart';

class ConveyorBeltDialog extends StatefulWidget {
  final ConveyorBelt belt;
  final List<ConveyorBelt> allBelts;
  final DataLoader dataLoader;
  final VoidCallback onStoreSingle;
  final VoidCallback onStoreLine;
  final VoidCallback onCollectAll;

  const ConveyorBeltDialog({
    super.key,
    required this.belt,
    required this.allBelts,
    required this.dataLoader,
    required this.onStoreSingle,
    required this.onStoreLine,
    required this.onCollectAll,
  });

  static Future<void> show(
    BuildContext context, {
    required ConveyorBelt belt,
    required List<ConveyorBelt> allBelts,
    required DataLoader dataLoader,
    required VoidCallback onStoreSingle,
    required VoidCallback onStoreLine,
    required VoidCallback onCollectAll,
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
      ),
    );
  }

  @override
  State<ConveyorBeltDialog> createState() => _ConveyorBeltDialogState();
}

class _ConveyorBeltDialogState extends State<ConveyorBeltDialog>
    with TickerProviderStateMixin {
  late AnimationController _beltAnimController;
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _beltAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _beltAnimController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Item? get _currentItem {
    if (widget.belt.itemId.isEmpty) return null;
    return widget.dataLoader.getItem(widget.belt.itemId);
  }

  String? get _lineItemId {
    for (final b in widget.allBelts) {
      if (b.itemId.isNotEmpty) return b.itemId;
    }
    return null;
  }

  Item? get _lineItem {
    if (_lineItemId == null || _lineItemId!.isEmpty) return null;
    return widget.dataLoader.getItem(_lineItemId!);
  }

  Color get _beltColor => const Color(0xFF8B7355);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      child: Container(
        width: 480,
        height: 380,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 16),
            _buildCurrentCargoSection(),
            const SizedBox(height: 12),
            Expanded(child: _buildBeltAnimation()),
            const SizedBox(height: 12),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _beltColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _beltColor.withValues(alpha: 0.5)),
              ),
              child: Icon(
                Icons.conveyor_belt,
                size: 16,
                color: _beltColor,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '传送带',
              style: TextStyle(
                color: Color(0xFFDDDDDD),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF444444)),
            ),
            child: const Icon(
              Icons.close,
              size: 16,
              color: Color(0xFF999999),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          icon: Icons.inventory_2_outlined,
          label: '收纳',
          onTap: () {
            widget.onStoreSingle();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.delete_sweep_outlined,
          label: '收纳整条产线',
          onTap: () {
            widget.onStoreLine();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF444444)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFFAAAAAA)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFBBBBBB),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCargoSection() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '本段货物',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildItemIcon(_currentItem, size: 36),
                const SizedBox(width: 12),
                _buildCollectButton(
                  label: '收取',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemIcon(Item? item, {double size = 36}) {
    if (item == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF555555)),
        ),
        child: Center(
          child: Icon(
            Icons.help_outline,
            size: size * 0.45,
            color: const Color(0xFF666666),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: item.color.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Container(
          width: size * 0.55,
          height: size * 0.55,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildCollectButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF555555)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFBBBBBB),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.refresh,
              size: 14,
              color: Color(0xFF888888),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeltAnimation() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: AnimatedBuilder(
        animation: _beltAnimController,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _BeltAnimationPainter(
              progress: _beltAnimController.value,
              floatProgress: _floatController.value,
              item: _currentItem,
              beltColor: _beltColor,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '— 产线全部货物 —',
              style: TextStyle(
                color: Color(0xFF777777),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildItemIcon(_lineItem, size: 32),
                const SizedBox(width: 12),
                _buildCollectButton(
                  label: '收取全部',
                  onTap: () {
                    widget.onCollectAll();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _BeltAnimationPainter extends CustomPainter {
  final double progress;
  final double floatProgress;
  final Item? item;
  final Color beltColor;

  _BeltAnimationPainter({
    required this.progress,
    required this.floatProgress,
    required this.item,
    required this.beltColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final beltHeight = 50.0;
    final beltY = size.height / 2;
    final margin = 24.0;

    _drawBeltBody(canvas, size, beltY, beltHeight, margin);
    _drawBeltArrows(canvas, size, beltY, beltHeight, margin, progress);

    if (item != null) {
      _drawFloatingItem(canvas, size, beltY, beltHeight, margin, progress, floatProgress);
    }

    _drawSideRails(canvas, size, beltY, beltHeight, margin);
  }

  void _drawBeltBody(Canvas canvas, Size size, double beltY, double beltHeight, double margin) {
    final bodyPaint = Paint()
      ..color = beltColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(margin, beltY - beltHeight / 2, size.width - margin * 2, beltHeight),
      const Radius.circular(6),
    );

    canvas.drawRRect(bodyRect, bodyPaint);

    final linePaint = Paint()
      ..color = beltColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(margin + 8, beltY),
      Offset(size.width - margin - 8, beltY),
      linePaint,
    );
  }

  void _drawBeltArrows(Canvas canvas, Size size, double beltY, double beltHeight, double margin, double animProgress) {
    final arrowPaint = Paint()
      ..color = beltColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final arrowCount = 3;
    final spacing = (size.width - margin * 2 - 40) / (arrowCount + 1);

    for (int i = 0; i < arrowCount; i++) {
      final baseX = margin + 20 + spacing * (i + 1);
      final offset = (animProgress * spacing * 2) % (spacing * 2);
      final x = baseX + offset;

      if (x > margin + 15 && x < size.width - margin - 15) {
        _drawTriangleArrow(canvas, Offset(x, beltY), 6, arrowPaint);
      }
    }
  }

  void _drawTriangleArrow(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path()
      ..moveTo(center.dx + size, center.dy)
      ..lineTo(center.dx - size * 0.6, center.dy - size * 0.6)
      ..lineTo(center.dx - size * 0.6, center.dy + size * 0.6)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawFloatingItem(Canvas canvas, Size size, double beltY, double beltHeight, double margin, double animProgress, double floatProg) {
    final centerX = size.width / 2;
    final floatOffset = math.sin(floatProg * math.pi * 2) * 4;
    final itemCenterY = beltY - 10 + floatOffset;
    final itemSize = 32.0;

    final glowPaint = Paint()
      ..color = item!.color.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(
      Offset(centerX, itemCenterY),
      itemSize * 0.8,
      glowPaint,
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.fill;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, itemCenterY), width: itemSize, height: itemSize),
      const Radius.circular(6),
    );

    canvas.drawRRect(bgRect, bgPaint);

    final borderPaint = Paint()
      ..color = item!.color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(bgRect, borderPaint);

    final innerPaint = Paint()
      ..color = item!.color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX, itemCenterY),
      itemSize * 0.3,
      innerPaint,
    );
  }

  void _drawSideRails(Canvas canvas, Size size, double beltY, double beltHeight, double margin) {
    final railPaint = Paint()
      ..color = beltColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final railTopY = beltY - beltHeight / 2 + 3;
    final railBottomY = beltY + beltHeight / 2 - 3;

    canvas.drawLine(
      Offset(margin + 4, railTopY),
      Offset(size.width - margin - 4, railTopY),
      railPaint,
    );

    canvas.drawLine(
      Offset(margin + 4, railBottomY),
      Offset(size.width - margin - 4, railBottomY),
      railPaint,
    );

    final dotPaint = Paint()
      ..color = beltColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final dotSpacing = 12.0;
    int dotCount = ((size.width - margin * 2 - 8) / dotSpacing).floor();

    for (int row = 0; row < 2; row++) {
      final y = row == 0 ? railTopY : railBottomY;
      for (int i = 0; i < dotCount; i++) {
        final x = margin + 6 + dotSpacing * i;
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeltAnimationPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        floatProgress != oldDelegate.floatProgress ||
        item != oldDelegate.item ||
        beltColor != oldDelegate.beltColor;
  }
}
