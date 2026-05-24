import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/building.dart';
import '../models/recipe.dart';

class BuildingRenderer {
  static const double _frameStrokeTopBottom = 3.0;
  static const double _frameStrokeLeftRight = 1.5;
  static const double _portSize = 8.0;
  static const double _cornerRadius = 0.0;
  static const Color _frameColor = Color(0xFF333333);
  static const Color _portActiveColor = Color(0xFFFFCC00);
  static const Color _portInactiveColor = Color(0xFF666666);
  static const Color _blockedOverlayColor = Color(0x40FF0000);

  static void renderBuilding(
    Canvas canvas,
    Building building,
    double gridX,
    double gridY,
    double cellSize,
    int rotation, {
    Recipe? activeRecipe,
    bool isBlocked = false,
    double productionProgress = 0.0,
    Map<String, bool>? portConnections,
    int detailLevel = 2,
  }) {
    final x = gridX * cellSize;
    final y = gridY * cellSize;
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(rotation * math.pi / 2);
    canvas.translate(-w / 2, -h / 2);

    _drawBuildingBody(canvas, building, cellSize, isBlocked);

    // LOD 1+: 进度条
    if (detailLevel >= 1 && productionProgress > 0 && productionProgress < 1.0) {
      _drawProgressBar(canvas, cellSize, building, productionProgress);
    }

    // LOD 2: 端口箭头
    if (detailLevel >= 2) {
      _drawPorts(canvas, building, cellSize, activeRecipe, portConnections);
    }

    // LOD 2: 设备名称
    if (detailLevel >= 2) {
      _drawBuildingName(canvas, building, cellSize);
    }

    // LOD 2: 配方标签
    if (detailLevel >= 2 && activeRecipe != null) {
      _drawRecipeLabel(canvas, activeRecipe.name, cellSize, building);
    }

    canvas.restore();
  }

  static void _drawBuildingBody(
    Canvas canvas, Building building, double cellSize, bool isBlocked) {
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(_cornerRadius),
    );

    final fillPaint = Paint()..color = building.color.withValues(alpha: 0.15);
    canvas.drawRRect(rect, fillPaint);

    final topBottomPaint = Paint()
      ..color = _frameColor
      ..strokeWidth = _frameStrokeTopBottom
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0), Offset(w, 0), topBottomPaint);
    canvas.drawLine(Offset(0, h), Offset(w, h), topBottomPaint);

    final leftRightPaint = Paint()
      ..color = _frameColor
      ..strokeWidth = _frameStrokeLeftRight
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0), Offset(0, h), leftRightPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, h), leftRightPaint);

    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
    }
  }

  static void _drawProgressBar(
    Canvas canvas, double cellSize, Building building, double progress) {
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;
    const barHeight = 4.0;
    final barY = h - barHeight - 2;

    final bgPaint = Paint()..color = const Color(0x40000000);
    canvas.drawRect(
      Rect.fromLTWH(2, barY, w - 4, barHeight),
      bgPaint,
    );

    final progressPaint = Paint()..color = const Color(0xFF00FF66);
    canvas.drawRect(
      Rect.fromLTWH(2, barY, (w - 4) * progress, barHeight),
      progressPaint,
    );
  }

  static void _drawPorts(
    Canvas canvas,
    Building building,
    double cellSize,
    Recipe? activeRecipe,
    Map<String, bool>? portConnections,
  ) {
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;
    final portPaint = Paint()..style = PaintingStyle.fill;
    final portStroke = Paint()
      ..color = _frameColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final port in building.ports.inputs) {
      final px = port.relativeX * w;
      final py = port.relativeY * h;
      final portRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(px, py), width: _portSize, height: _portSize),
        const Radius.circular(1.0),
      );

      final isConnected = portConnections?['input_${building.ports.inputs.indexOf(port)}'] ?? false;
      portPaint.color = isConnected ? _portActiveColor : _portInactiveColor;
      canvas.drawRRect(portRect, portPaint);
      canvas.drawRRect(portRect, portStroke);

      _drawPortArrow(canvas, px, py, port.direction, cellSize, isConnected);
    }

    for (final port in building.ports.outputs) {
      final px = port.relativeX * w;
      final py = port.relativeY * h;
      final portRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(px, py), width: _portSize, height: _portSize),
        const Radius.circular(1.0),
      );

      final isConnected = portConnections?['output_${building.ports.outputs.indexOf(port)}'] ?? false;
      portPaint.color = isConnected ? _portActiveColor : _portInactiveColor;
      canvas.drawRRect(portRect, portPaint);
      canvas.drawRRect(portRect, portStroke);

      _drawPortArrow(canvas, px, py, port.direction, cellSize, isConnected);
    }
  }

  static void _drawPortArrow(
    Canvas canvas, double px, double py, String direction, double cellSize, bool active) {
    final arrowPaint = Paint()
      ..color = active ? _portActiveColor : _portInactiveColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final arrowLen = cellSize * 0.3;
    final arrowHead = cellSize * 0.1;
    late Offset start, end;

    switch (direction) {
      case 'up':
        start = Offset(px, py);
        end = Offset(px, py - arrowLen);
        break;
      case 'down':
        start = Offset(px, py);
        end = Offset(px, py + arrowLen);
        break;
      case 'left':
        start = Offset(px, py);
        end = Offset(px - arrowLen, py);
        break;
      case 'right':
      default:
        start = Offset(px, py);
        end = Offset(px + arrowLen, py);
        break;
    }

    canvas.drawLine(start, end, arrowPaint);

    final dir = (end - start);
    final dirNorm = dir / dir.distance;
    final perp = Offset(-dirNorm.dy, dirNorm.dx) * arrowHead * 0.6;
    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - dirNorm.dx * arrowHead + perp.dx,
          end.dy - dirNorm.dy * arrowHead + perp.dy)
      ..lineTo(end.dx - dirNorm.dx * arrowHead - perp.dx,
          end.dy - dirNorm.dy * arrowHead - perp.dy)
      ..close();
    canvas.drawPath(headPath, Paint()..color = arrowPaint.color);
  }

  static void _drawBuildingName(
    Canvas canvas, Building building, double cellSize) {
    final w = building.gridWidth * cellSize;
    final textPainter = TextPainter(
      text: TextSpan(
        text: building.name,
        style: TextStyle(
          color: _frameColor.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: w - 4);
    textPainter.paint(canvas, const Offset(2, 2));
  }

  static void _drawRecipeLabel(
    Canvas canvas, String recipeName, double cellSize, Building building) {
    final w = building.gridWidth * cellSize;
    final textPainter = TextPainter(
      text: TextSpan(
        text: recipeName,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 8,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: w - 4);
    textPainter.paint(canvas, const Offset(2, 14));
  }

  static void renderPlaceholder(
    Canvas canvas,
    Building building,
    double gridX,
    double gridY,
    double cellSize,
    double opacity, {
    int rotation = 0,
  }) {
    final x = gridX * cellSize;
    final y = gridY * cellSize;
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(rotation * math.pi / 2);
    canvas.translate(-w / 2, -h / 2);

    final paint = Paint()
      ..color = building.color.withValues(alpha: opacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

    final borderPaint = Paint()
      ..color = building.color.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), borderPaint);

    canvas.restore();
  }
}