import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/item.dart';

class ConveyorRenderer {
  static const double _cellMargin = 3.0;
  static const Color _beltColor = Color(0xFF555555);
  static const Color _beltHighlight = Color(0xFF777777);
  static const Color _arrowColor = Color(0xFF999999);
  static const double _particleSize = 3.0;
  static const double _particleSpacing = 16.0;
  static const Color _previewFillColor = Color(0x6044AAFF);
  static const Color _previewBorderColor = Color(0xAA44AAFF);
  static const Color _previewArrowColor = Color(0xDD44AAFF);
  static const Color _previewOccupiedFill = Color(0x60FF4444);
  static const Color _previewOccupiedBorder = Color(0xAAFF4444);

  static void renderConveyorPath(
    Canvas canvas,
    ConveyorBelt belt,
    Item? item,
    double cellSize,
  ) {
    if (belt.path.length < 2) return;

    for (int i = 0; i < belt.path.length; i++) {
      final cell = belt.path[i];
      final direction = _getCellDirection(belt.path, i);
      _drawConveyorCell(canvas, cell, direction, cellSize, _beltColor, _beltHighlight, _arrowColor);
    }

    if (item != null && !belt.isBlocked) {
      _renderParticles(canvas, belt, item, cellSize);
    }

    if (belt.isBlocked && belt.path.isNotEmpty) {
      _renderBlockedIndicator(canvas, belt.path.last, cellSize);
    }
  }

  static void _drawConveyorCell(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color fillColor,
    Color lineColor,
    Color arrowColor,
  ) {
    final x = cell.dx * cellSize + _cellMargin;
    final y = cell.dy * cellSize + _cellMargin;
    final w = cellSize - _cellMargin * 2;
    final h = cellSize - _cellMargin * 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(3.0),
    );

    canvas.drawRRect(rect, Paint()..color = fillColor);

    _drawCenterLine(canvas, cell, direction, cellSize, lineColor);
    _drawArrow(canvas, cell, direction, cellSize, arrowColor);
  }

  static void _drawCenterLine(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color color,
  ) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final halfLen = cellSize / 2 - _cellMargin - 4;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    Offset start, end;
    switch (direction) {
      case 'right':
        start = Offset(cx - halfLen, cy);
        end = Offset(cx + halfLen, cy);
        break;
      case 'left':
        start = Offset(cx + halfLen, cy);
        end = Offset(cx - halfLen, cy);
        break;
      case 'down':
        start = Offset(cx, cy - halfLen);
        end = Offset(cx, cy + halfLen);
        break;
      case 'up':
        start = Offset(cx, cy + halfLen);
        end = Offset(cx, cy - halfLen);
        break;
      default:
        start = Offset(cx - halfLen, cy);
        end = Offset(cx + halfLen, cy);
    }

    canvas.drawLine(start, end, paint);
  }

  static void _drawArrow(
    Canvas canvas,
    Offset cell,
    String direction,
    double cellSize,
    Color color,
  ) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final arrowSize = 5.0;

    final paint = Paint()..color = color;

    Offset p1, p2, p3;
    switch (direction) {
      case 'right':
        p1 = Offset(cx + arrowSize, cy);
        p2 = Offset(cx - arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx - arrowSize * 0.4, cy + arrowSize * 0.8);
        break;
      case 'left':
        p1 = Offset(cx - arrowSize, cy);
        p2 = Offset(cx + arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx + arrowSize * 0.4, cy + arrowSize * 0.8);
        break;
      case 'down':
        p1 = Offset(cx, cy + arrowSize);
        p2 = Offset(cx - arrowSize * 0.8, cy - arrowSize * 0.4);
        p3 = Offset(cx + arrowSize * 0.8, cy - arrowSize * 0.4);
        break;
      case 'up':
        p1 = Offset(cx, cy - arrowSize);
        p2 = Offset(cx - arrowSize * 0.8, cy + arrowSize * 0.4);
        p3 = Offset(cx + arrowSize * 0.8, cy + arrowSize * 0.4);
        break;
      default:
        p1 = Offset(cx + arrowSize, cy);
        p2 = Offset(cx - arrowSize * 0.4, cy - arrowSize * 0.8);
        p3 = Offset(cx - arrowSize * 0.4, cy + arrowSize * 0.8);
    }

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static String _getCellDirection(List<Offset> path, int index) {
    if (index < path.length - 1) {
      final dx = path[index + 1].dx - path[index].dx;
      final dy = path[index + 1].dy - path[index].dy;
      if (dx > 0) return 'right';
      if (dx < 0) return 'left';
      if (dy > 0) return 'down';
      if (dy < 0) return 'up';
    }
    if (index > 0) {
      final dx = path[index].dx - path[index - 1].dx;
      final dy = path[index].dy - path[index - 1].dy;
      if (dx > 0) return 'right';
      if (dx < 0) return 'left';
      if (dy > 0) return 'down';
      if (dy < 0) return 'up';
    }
    return 'right';
  }

  static void _renderParticles(
    Canvas canvas,
    ConveyorBelt belt,
    Item item,
    double cellSize,
  ) {
    final totalLength = belt.length;
    if (totalLength <= 0) return;

    final particlePaint = Paint()..color = item.color;
    final particleCount = (totalLength / _particleSpacing).floor().clamp(1, 200);
    final flowOffset = belt.flowProgress * _particleSpacing;

    for (int i = 0; i < particleCount; i++) {
      final distance = (i * _particleSpacing + flowOffset) % totalLength;
      final pos = _getPositionAlongPath(belt.path, distance, cellSize);
      canvas.drawCircle(pos, _particleSize, particlePaint);
    }
  }

  static Offset _getPositionAlongPath(
      List<Offset> path, double distance, double cellSize) {
    if (path.length < 2) return Offset.zero;

    int segmentIndex = (distance / cellSize).floor();
    if (segmentIndex >= path.length - 1) segmentIndex = path.length - 2;
    if (segmentIndex < 0) segmentIndex = 0;

    final t = (distance - segmentIndex * cellSize) / cellSize;
    final from = path[segmentIndex];
    final to = path[segmentIndex + 1];

    return Offset(
      (from.dx + (to.dx - from.dx) * t) * cellSize + cellSize / 2,
      (from.dy + (to.dy - from.dy) * t) * cellSize + cellSize / 2,
    );
  }

  static void _renderBlockedIndicator(Canvas canvas, Offset cell, double cellSize) {
    final cx = cell.dx * cellSize + cellSize / 2;
    final cy = cell.dy * cellSize + cellSize / 2;
    final pos = Offset(cx, cy);

    canvas.drawCircle(pos, _particleSize * 2, Paint()..color = const Color(0xFFFF3333));

    final crossPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.5;
    const s = _particleSize;
    canvas.drawLine(
      Offset(pos.dx - s, pos.dy - s),
      Offset(pos.dx + s, pos.dy + s),
      crossPaint,
    );
    canvas.drawLine(
      Offset(pos.dx + s, pos.dy - s),
      Offset(pos.dx - s, pos.dy + s),
      crossPaint,
    );
  }

  static void renderPreviewPath(
    Canvas canvas,
    List<Offset> path,
    double cellSize,
    Set<String> occupiedKeys,
  ) {
    if (path.isEmpty) return;

    for (int i = 0; i < path.length; i++) {
      final cell = path[i];
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      final isOccupied = occupiedKeys.contains(key);

      final x = cell.dx * cellSize + _cellMargin;
      final y = cell.dy * cellSize + _cellMargin;
      final w = cellSize - _cellMargin * 2;
      final h = cellSize - _cellMargin * 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(3.0),
      );

      canvas.drawRRect(rect, Paint()..color = isOccupied ? _previewOccupiedFill : _previewFillColor);
      canvas.drawRRect(
          rect,
          Paint()
            ..color = isOccupied ? _previewOccupiedBorder : _previewBorderColor
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke);

      if (path.length >= 2 && !isOccupied) {
        final direction = _getCellDirection(path, i);
        _drawArrow(canvas, cell, direction, cellSize, _previewArrowColor);
      }
    }
  }
}
