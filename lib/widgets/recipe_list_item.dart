import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/item.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';

/// 配方列表项 - 显示配方输入/输出和固定按钮
class RecipeListItem extends StatelessWidget {
  final Recipe recipe;
  final DataLoader dataLoader;
  final bool isPinned;
  final VoidCallback onPin;

  const RecipeListItem({
    super.key,
    required this.recipe,
    required this.dataLoader,
    required this.isPinned,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final inputs = recipe.inputs;
    final input1 =
        inputs.isNotEmpty ? dataLoader.getItem(inputs[0].itemId) : null;
    final amount1 = inputs.isNotEmpty ? inputs[0].amount : 1;
    final input2 =
        inputs.length > 1 ? dataLoader.getItem(inputs[1].itemId) : null;
    final amount2 = inputs.length > 1 ? inputs[1].amount : 1;

    final outputs = recipe.outputs;
    final output1 =
        outputs.isNotEmpty ? dataLoader.getItem(outputs[0].itemId) : null;
    final outAmount1 = outputs.isNotEmpty ? outputs[0].amount : 1;
    final output2 =
        outputs.length > 1 ? dataLoader.getItem(outputs[1].itemId) : null;
    final outAmount2 = outputs.length > 1 ? outputs[1].amount : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 14,
                color: Color(0xFFCCCCCC),
              ),
              const SizedBox(width: 6),
              Text(
                recipe.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              MiniItemTile(item: input1, amount: amount1),
              const SizedBox(width: 8),
              MiniItemTile(item: input2, amount: amount2),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_right_rounded,
                          size: 14, color: Color(0xFF666666)),
                      Icon(Icons.chevron_right_rounded,
                          size: 14, color: Color(0xFF666666)),
                      Icon(Icons.chevron_right_rounded,
                          size: 14, color: Color(0xFF666666)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${recipe.processTimeSeconds.toStringAsFixed(0)}秒',
                    style: const TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              MiniItemTile(item: output1, amount: outAmount1),
              const SizedBox(width: 8),
              MiniItemTile(item: output2, amount: outAmount2),
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 54,
                color: const Color(0xFFDCDCDC),
              ),
              const SizedBox(width: 12),
              RecipePinButton(
                isPinned: isPinned,
                onTap: onPin,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 配方固定按钮 - 图钉图标，悬停/固定时旋转45度
class RecipePinButton extends StatefulWidget {
  final bool isPinned;
  final VoidCallback onTap;

  const RecipePinButton({
    super.key,
    required this.isPinned,
    required this.onTap,
  });

  @override
  State<RecipePinButton> createState() => _RecipePinButtonState();
}

class _RecipePinButtonState extends State<RecipePinButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool applyTransform = widget.isPinned || _isHovered;

    Color mainColor;
    if (widget.isPinned) {
      mainColor = const Color(0xFF99932A);
    } else if (_isHovered) {
      mainColor = const Color(0xFFCAAD2B);
    } else {
      mainColor = const Color(0xFF888888);
    }

    Color borderColor = widget.isPinned
        ? const Color(0xFF99932A)
        : (_isHovered ? const Color(0xFFCAAD2B) : const Color(0xFFCCCCCC));

    double rotationAngle = applyTransform ? math.pi / 4 : 0.0;
    double scale = applyTransform ? 1.25 : 1.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isPinned
                ? mainColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: widget.isPinned ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: AnimatedRotation(
              turns: rotationAngle / (2 * math.pi),
              duration: const Duration(milliseconds: 150),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.push_pin,
                  size: 18,
                  color: mainColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你物品方块 - 配方列表中的小物品图标
class MiniItemTile extends StatelessWidget {
  final Item? item;
  final int amount;

  const MiniItemTile({super.key, required this.item, required this.amount});

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFCCCCCC)),
        ),
        child: CustomPaint(
          painter: DiagonalSlashPainter(),
        ),
      );
    }

    final colors = {
      2: const Color(0xFF44AA00),
      3: const Color(0xFF0082EA),
      4: const Color(0xFFB73CC5),
    };
    final tagColor = colors[item!.level] ?? const Color(0xFFEBEBEB);

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF666666)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item!.imageAssetPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(2),
              child: Image.asset(
                item!.imageAssetPath,
                cacheWidth: 162,
                cacheHeight: 162,
                fit: BoxFit.contain,
                filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, __, ___) => Container(),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 12,
            child: Container(
              color: tagColor,
              alignment: Alignment.center,
              child: Text(
                '$amount',
                style: TextStyle(
                  color: item!.level >= 2 ? Colors.white : Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 配方运行指示器 - 三个三角形循环闪烁
class RecipeRunIndicator extends StatefulWidget {
  const RecipeRunIndicator({super.key});

  @override
  State<RecipeRunIndicator> createState() => _RecipeRunIndicatorState();
}

class _RecipeRunIndicatorState extends State<RecipeRunIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;

        double op1, op2, op3;
        if (t < 1.0 / 3.0) {
          double subT = t / (1.0 / 3.0);
          op1 = 0.2 + (1.0 - 0.2) * subT;
          op2 = 0.6 + (0.2 - 0.6) * subT;
          op3 = 1.0 + (0.6 - 1.0) * subT;
        } else if (t < 2.0 / 3.0) {
          double subT = (t - 1.0 / 3.0) / (1.0 / 3.0);
          op1 = 1.0 + (0.6 - 1.0) * subT;
          op2 = 0.2 + (1.0 - 0.2) * subT;
          op3 = 0.6 + (0.2 - 0.6) * subT;
        } else {
          double subT = (t - 2.0 / 3.0) / (1.0 / 3.0);
          op1 = 0.6 + (0.2 - 0.6) * subT;
          op2 = 1.0 + (0.6 - 1.0) * subT;
          op3 = 0.2 + (1.0 - 0.2) * subT;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTriangle(op1),
            const SizedBox(width: 4),
            _buildTriangle(op2),
            const SizedBox(width: 4),
            _buildTriangle(op3),
          ],
        );
      },
    );
  }

  Widget _buildTriangle(double opacity) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: SizedBox(
        width: 10,
        height: 12,
        child: CustomPaint(
          painter: const TrianglePainter(color: Colors.white),
        ),
      ),
    );
  }
}
