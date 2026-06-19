import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 生产中指示器 - 三个方向箭头闪烁动画
class ProcessingIndicator extends StatefulWidget {
  final bool isRunning;

  const ProcessingIndicator({super.key, required this.isRunning});

  @override
  State<ProcessingIndicator> createState() => _ProcessingIndicatorState();
}

class _ProcessingIndicatorState extends State<ProcessingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
    });

    if (widget.isRunning) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted && widget.isRunning) {
          _controllers[i].repeat();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ProcessingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning != oldWidget.isRunning) {
      if (widget.isRunning) {
        _startAnimations();
      } else {
        for (final controller in _controllers) {
          controller.stop();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controllers[index],
            builder: (context, child) {
              final value = _controllers[index].value;
              final opacity =
                  0.2 + 0.8 * (0.5 + 0.5 * math.sin(value * 2 * math.pi));
              return Opacity(
                opacity: widget.isRunning ? opacity : 0.2,
                child: child,
              );
            },
            child: SizedBox(
              width: 16,
              height: 36,
              child: SvgPicture.asset(
                'assets/svg/Directional.svg',
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          );
        }).expand((widget) => [widget, const SizedBox(width: 4)]).toList()
          ..removeLast(),
      ],
    );
  }
}

/// 生产进度条
class ProductionProgressBar extends StatefulWidget {
  final double progress;

  const ProductionProgressBar({super.key, required this.progress});

  @override
  State<ProductionProgressBar> createState() => _ProductionProgressBarState();
}

class _ProductionProgressBarState extends State<ProductionProgressBar>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rippleAnimation = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(ProductionProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 生产周期完成时 progress 会从较高值突然回落，以此触发涟漪
    if (oldWidget.progress > 0.5 && widget.progress < oldWidget.progress) {
      _rippleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.progress.clamp(0.0, 1.0).toDouble();
    return AnimatedBuilder(
      animation: _rippleAnimation,
      builder: (context, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: clamped),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, child) {
            return CustomPaint(
              size: const Size(156, 14),
              painter: _ProductionProgressBarPainter(
                animatedProgress,
                _rippleAnimation.value,
              ),
            );
          },
        );
      },
    );
  }
}

class _ProductionProgressBarPainter extends CustomPainter {
  final double progress;
  final double rippleProgress;

  _ProductionProgressBarPainter(this.progress, this.rippleProgress);

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackWidth = size.width - 16;

    // 背景条
    final trackRect = Rect.fromLTWH(8, centerY - 2, trackWidth, 4);
    final trackRRect = RRect.fromRectAndRadius(
      trackRect,
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackRRect,
      Paint()..color = const Color(0xFFBFBFBF),
    );

    // 白色进度条，终点位于圆形中心（size.width - 8）
    final fillWidth = trackWidth * progress;
    final fillRect = Rect.fromLTWH(8, centerY - 4, fillWidth, 8);
    final fillRRect = RRect.fromRectAndRadius(
      fillRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      fillRRect,
      Paint()..color = Colors.white,
    );

    // 白色圆形绘制在进度条之上，覆盖末端；圆心向右偏移一个半径，
    // 使进度条实体恰好填充到圆形的左边缘（即原中心位置）。
    final circleCenter = Offset(size.width - 14, centerY);

    // 涟漪：进度条到达终点时触发，白色圆从基础大小放大并逐渐透明
    if (rippleProgress > 0) {
      final rippleRadius = 6 + 16 * rippleProgress;
      final alpha = ((1 - rippleProgress) * 255).round();
      canvas.drawCircle(
        circleCenter,
        rippleRadius,
        Paint()..color = Colors.white.withAlpha(alpha),
      );
    }

    canvas.drawCircle(
      circleCenter,
      6,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ProductionProgressBarPainter old) {
    return old.progress != progress || old.rippleProgress != rippleProgress;
  }
}

/// 暂停指示器 - 灰色 Close_button + 两侧灰色条
class PausedIndicator extends StatelessWidget {
  const PausedIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF929292),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SvgPicture.asset(
          'assets/png/window/Close_button.svg',
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(
            Color(0xFF929292),
            BlendMode.srcIn,
          ),
        ),
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF929292),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// 暂停进度条 - 灰色 "生产已暂停" + 两侧灰色条
class PausedProgressBar extends StatelessWidget {
  const PausedProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF929292),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '生产已暂停',
            style: TextStyle(
              color: Color(0xFF929292),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 20,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF929292),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 阻塞指示器 - 红色 Close_button + 两侧红色条
class BlockedIndicator extends StatelessWidget {
  const BlockedIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SvgPicture.asset(
          'assets/png/window/Close_button.svg',
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(
            Color(0xFFE53935),
            BlendMode.srcIn,
          ),
        ),
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// 阻塞进度条 - 红色 "阻塞" + 两侧红色条
class BlockedProgressBar extends StatelessWidget {
  const BlockedProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '阻塞',
          style: TextStyle(
            color: Color(0xFFE53935),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
