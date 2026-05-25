import 'dart:math' as math;
import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final double offsetX;
  final double offsetY;
  final double scale;
  final double cellSize;
  final double rotation;

  static const double _baseCellSize = 48.0;
  static const Color _backgroundColor = Color(0xFFE4E4E4);

  static const double _fadeStartScale = 0.5;
  static const double _fadeEndScale = 0.25;

  GridPainter({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    this.cellSize = _baseCellSize,
    this.rotation = 0.0,
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

    if (rotation != 0) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.translate(-center.dx, -center.dy);
    }

    // 计算旋转后可见区域在旋转坐标系中的边界
    // 旋转后，屏幕矩形在旋转坐标系中是一个旋转的矩形，需要计算其包围盒
    final double visXMin;
    final double visXMax;
    final double visYMin;
    final double visYMax;
    final double lineExtent; // 网格线延伸长度，确保覆盖旋转后的可见区域

    if (rotation != 0) {
      final cx = size.width / 2;
      final cy = size.height / 2;
      final cosR = math.cos(rotation);
      final sinR = math.sin(rotation);

      // 将屏幕四角逆旋转到旋转坐标系，求包围盒
      final corners = [
        Offset(0, 0),
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ];

      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;

      for (final corner in corners) {
        final dx = corner.dx - cx;
        final dy = corner.dy - cy;
        final rx = dx * cosR + dy * sinR + cx;
        final ry = -dx * sinR + dy * cosR + cy;
        if (rx < minX) minX = rx;
        if (rx > maxX) maxX = rx;
        if (ry < minY) minY = ry;
        if (ry > maxY) maxY = ry;
      }

      visXMin = minX;
      visXMax = maxX;
      visYMin = minY;
      visYMax = maxY;
      lineExtent = math.sqrt(size.width * size.width + size.height * size.height);
    } else {
      visXMin = 0;
      visXMax = size.width;
      visYMin = 0;
      visYMax = size.height;
      lineExtent = 0; // 未旋转时不使用
    }

    final startCol = ((visXMin + offsetX) / scaledCellSize).floor() - 1;
    final endCol = ((visXMax + offsetX) / scaledCellSize).ceil() + 1;
    final startRow = ((visYMin + offsetY) / scaledCellSize).floor() - 1;
    final endRow = ((visYMax + offsetY) / scaledCellSize).ceil() + 1;

    final double lineH = rotation != 0 ? lineExtent : size.height;
    final double lineW = rotation != 0 ? lineExtent : size.width;

    for (int col = startCol; col <= endCol; col++) {
      final x = col * scaledCellSize - offsetX;
      final isMajor = col % 8 == 0;
      final paint = Paint()
        ..color = isMajor ? majorGridColor : gridColor
        ..strokeWidth = isMajor ? 1.2 : 0.6;
      canvas.drawLine(Offset(x, -lineH), Offset(x, lineH), paint);
    }

    for (int row = startRow; row <= endRow; row++) {
      final y = row * scaledCellSize - offsetY;
      final isMajor = row % 8 == 0;
      final paint = Paint()
        ..color = isMajor ? majorGridColor : gridColor
        ..strokeWidth = isMajor ? 1.2 : 0.6;
      canvas.drawLine(Offset(-lineW, y), Offset(lineW, y), paint);
    }

    if (rotation != 0) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.scale != scale ||
        (oldDelegate.rotation - rotation).abs() > 0.001;
  }
}
