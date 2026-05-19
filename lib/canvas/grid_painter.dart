import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double scale;
  final double cellSize;

  static const double _baseCellSize = 48.0;
  static const Color _backgroundColor = Color(0xFFE4E4E4);

  static const double _fadeStartScale = 0.5;
  static const double _fadeEndScale = 0.25;

  GridPainter({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    this.cellSize = _baseCellSize,
  });

  double _gridOpacity() {
    if (scale >= _fadeStartScale) return 1.0;
    if (scale <= _fadeEndScale) return 0.0;
    return (scale - _fadeEndScale) / (_fadeStartScale - _fadeEndScale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _backgroundColor);

    final opacity = _gridOpacity();
    if (opacity <= 0) return;

    final scaledCellSize = cellSize * scale;
    if (scaledCellSize < 4) return;

    final gridAlpha = (0x80 * opacity).round().clamp(0, 255);
    final majorAlpha = (0x60 * opacity).round().clamp(0, 255);
    final gridColor = Color.fromARGB(gridAlpha, 0xB0, 0xB0, 0xB0);
    final majorGridColor = Color.fromARGB(majorAlpha, 0xB0, 0xB0, 0xB0);

    final startCol = (offsetX / scaledCellSize).floor() - 1;
    final endCol = ((offsetX + size.width) / scaledCellSize).ceil() + 1;
    final startRow = (offsetY / scaledCellSize).floor() - 1;
    final endRow = ((offsetY + size.height) / scaledCellSize).ceil() + 1;

    for (int col = startCol; col <= endCol; col++) {
      final x = col * scaledCellSize - offsetX;
      final isMajor = col % 8 == 0;
      final paint = Paint()
        ..color = isMajor ? majorGridColor : gridColor
        ..strokeWidth = isMajor ? 1.2 : 0.6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (int row = startRow; row <= endRow; row++) {
      final y = row * scaledCellSize - offsetY;
      final isMajor = row % 8 == 0;
      final paint = Paint()
        ..color = isMajor ? majorGridColor : gridColor
        ..strokeWidth = isMajor ? 1.2 : 0.6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.scale != scale;
  }
}
