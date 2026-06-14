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
class ProductionProgressBar extends StatelessWidget {
  final double progress;

  const ProductionProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 156,
      height: 14,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: clamped),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, child) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 8,
                right: 8,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBFBFBF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                child: Container(
                  width: 140 * animatedProgress,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Positioned(
                right: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 12, height: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
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
