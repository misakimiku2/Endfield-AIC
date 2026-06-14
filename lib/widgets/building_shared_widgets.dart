import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 带图标和文字的操作按钮（移动、收纳等）
class ActionButton extends StatefulWidget {
  final String svgPath;
  final String label;
  final VoidCallback onTap;

  const ActionButton({
    super.key,
    required this.svgPath,
    required this.label,
    required this.onTap,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _isHovered = false;
  String? _svgString;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSvg();
  }

  @override
  void didUpdateWidget(ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgPath != widget.svgPath) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    try {
      final data =
          await DefaultAssetBundle.of(context).loadString(widget.svgPath);
      if (mounted) {
        setState(() {
          _svgString = data;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    if (_svgString == null) {
      iconWidget = const SizedBox(
        width: 44,
        height: 44,
      );
    } else {
      String finalSvg = _svgString!;
      if (_isHovered) {
        finalSvg = finalSvg
            .replaceAll('fill:#636363', 'fill:#TEMP_WHITE_SVG')
            .replaceAll('fill:#ffffff', 'fill:#636363')
            .replaceAll('fill:#TEMP_WHITE_SVG', 'fill:#ffffff');
      }
      iconWidget = SvgPicture.string(
        finalSvg,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 悬停变色关闭按钮
class HoverCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const HoverCloseButton({super.key, required this.onTap});

  @override
  State<HoverCloseButton> createState() => _HoverCloseButtonState();
}

class _HoverCloseButtonState extends State<HoverCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 26,
          height: 26,
          child: SvgPicture.asset(
            'assets/png/window/Close_button.svg',
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            colorFilter: _isHovered
                ? const ColorFilter.mode(Color(0xFF636363), BlendMode.srcIn)
                : null,
          ),
        ),
      ),
    );
  }
}

/// 悬停变色 SVG 按钮
class HoverSvgButton extends StatefulWidget {
  final String svgPath;
  final double width;
  final double height;
  final VoidCallback onTap;

  const HoverSvgButton({
    super.key,
    required this.svgPath,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<HoverSvgButton> createState() => _HoverSvgButtonState();
}

class _HoverSvgButtonState extends State<HoverSvgButton> {
  bool _isHovered = false;
  String? _svgString;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSvg();
  }

  @override
  void didUpdateWidget(HoverSvgButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgPath != widget.svgPath) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    try {
      final data =
          await DefaultAssetBundle.of(context).loadString(widget.svgPath);
      if (mounted) {
        setState(() {
          _svgString = data;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_svgString == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }
    String finalSvg = _svgString!;
    if (_isHovered) {
      finalSvg = finalSvg
          .replaceAll('fill:#636363', 'fill:#TEMP_WHITE_SVG')
          .replaceAll('fill:#ffffff', 'fill:#636363')
          .replaceAll('fill:#TEMP_WHITE_SVG', 'fill:#ffffff');
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: SvgPicture.string(
            finalSvg,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// 对角斜线画笔（用于空物品占位）
class DiagonalSlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 三角形画笔（用于配方运行指示器）
class TrianglePainter extends CustomPainter {
  final Color color;
  const TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
