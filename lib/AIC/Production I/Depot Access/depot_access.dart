import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/building.dart';
import '../../../models/recipe.dart';

/// 仓库存货口配置
class DepotLoaderConfig {
  static const String id = 'depot_loader_3x1';
  static const String name = '仓库存货口';
  static const int gridWidth = 3;
  static const int gridHeight = 1;
  static const String color = '#44AA88';
  static const String category = 'depot_access';
  static const int maxInputs = 1;
  static const int maxOutputs = 0;

  /// 端口布局：3x1 网格
  /// (0,0) - 占地  (1,0) - 进料口  (2,0) - 占地
  /// 进料口在 (1,0) 位置，方向向上
  static List<PortDefinition> get inputPorts => [
    const PortDefinition(
      relativeX: (1 + 0.5) / gridWidth,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
  ];

  static List<PortDefinition> get outputPorts => [];
}

/// 仓库取货口配置
class DepotUnloaderConfig {
  static const String id = 'depot_unloader_3x1';
  static const String name = '仓库取货口';
  static const int gridWidth = 3;
  static const int gridHeight = 1;
  static const String color = '#AA8844';
  static const String category = 'depot_access';
  static const int maxInputs = 0;
  static const int maxOutputs = 1;

  /// 端口布局：3x1 网格
  /// (0,0) - 占地  (1,0) - 出料口  (2,0) - 占地
  /// 出料口在 (1,0) 位置，方向向上
  static List<PortDefinition> get inputPorts => [];

  static List<PortDefinition> get outputPorts => [
    const PortDefinition(
      relativeX: (1 + 0.5) / gridWidth,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
  ];
}

/// 仓库存取货口共用渲染器
class DepotAccessRenderer {
  // 颜色
  static const Color _frameColor = Color(0xFF333333);
  static const Color _cellBorderColor = Color(0xFF555555);
  static const Color _portActiveColor = Color(0xFFFFCC00);
  static const Color _portInactiveColor = Color(0xFF666666);
  static const Color _blockedOverlayColor = Color(0x40FF0000);

  // 存货口特有色调
  static const Color _loaderBodyColor = Color(0xFF44AA88);
  // 取货口特有色调
  static const Color _unloaderBodyColor = Color(0xFFAA8844);

  // 尺寸
  static const double _frameStrokeWidth = 3.0;
  static const double _cellBorderStrokeWidth = 0.8;
  static const double _portSize = 10.0;
  static const double _arrowLength = 0.3;
  static const double _arrowHeadSize = 0.12;

  /// 渲染仓库存取货口
  static void render(
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

    final isLoader = building.id == DepotLoaderConfig.id;
    final bodyColor = isLoader ? _loaderBodyColor : _unloaderBodyColor;

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(rotation * math.pi / 2);
    canvas.translate(-w / 2, -h / 2);

    // 1. 主体
    _drawBody(canvas, w, h, bodyColor, isBlocked);

    // 2. LOD 1+: 内部网格线
    if (detailLevel >= 1) {
      _drawCellGrid(canvas, w, h, cellSize);
    }

    // 3. LOD 1+: 仓库连接标识
    if (detailLevel >= 1) {
      _drawDepotIndicator(canvas, w, h, cellSize, bodyColor);
    }

    // 4. LOD 2: 端口箭头
    if (detailLevel >= 2) {
      _drawPortArrows(canvas, building, cellSize, portConnections);
    }

    // 5. LOD 2: 设备名称
    if (detailLevel >= 2) {
      _drawName(canvas, w, building.name);
    }

    canvas.restore();
  }

  /// 渲染放置预览
  static void renderPlaceholder(
    Canvas canvas,
    Building building,
    double gridX,
    double gridY,
    double cellSize,
    double opacity,
  ) {
    final x = gridX * cellSize;
    final y = gridY * cellSize;
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;

    final isLoader = building.id == DepotLoaderConfig.id;
    final bodyColor = isLoader ? _loaderBodyColor : _unloaderBodyColor;

    final paint = Paint()
      ..color = bodyColor.withValues(alpha: opacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);

    final borderPaint = Paint()
      ..color = bodyColor.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), borderPaint);

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.translate(-w / 2, -h / 2);
    _drawPortArrows(canvas, building, cellSize, null, opacity: opacity * 0.6);
    canvas.restore();
  }

  static void _drawBody(
      Canvas canvas, double w, double h, Color bodyColor, bool isBlocked) {
    final fillPaint = Paint()..color = bodyColor.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fillPaint);

    final framePaint = Paint()
      ..color = _frameColor
      ..strokeWidth = _frameStrokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), framePaint);

    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
    }
  }

  static void _drawCellGrid(
      Canvas canvas, double w, double h, double cellSize) {
    final gridPaint = Paint()
      ..color = _cellBorderColor
      ..strokeWidth = _cellBorderStrokeWidth
      ..style = PaintingStyle.stroke;

    for (int col = 1; col < 3; col++) {
      final x = col * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
  }

  /// 绘制仓库连接标识 - 底边中间的虚线矩形，表示与仓库的连接面
  static void _drawDepotIndicator(
      Canvas canvas, double w, double h, double cellSize, Color bodyColor) {
    final indicatorPaint = Paint()
      ..color = bodyColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 底边中间的连接标识
    final rectLeft = cellSize * 0.75;
    final rectRight = cellSize * 2.25;
    final rectBottom = h;

    canvas.drawLine(
      Offset(rectLeft, rectBottom),
      Offset(rectRight, rectBottom),
      indicatorPaint,
    );

    // 小箭头指向底部（表示连接到仓库）
    final centerX = (rectLeft + rectRight) / 2;
    final arrowY = h - 2;
    const arrowHalf = 3.0;
    final path = Path()
      ..moveTo(centerX, arrowY)
      ..lineTo(centerX - arrowHalf, arrowY - arrowHalf)
      ..moveTo(centerX, arrowY)
      ..lineTo(centerX + arrowHalf, arrowY - arrowHalf);
    canvas.drawPath(path, indicatorPaint);
  }

  static void _drawPortArrows(
    Canvas canvas,
    Building building,
    double cellSize,
    Map<String, bool>? portConnections, {
    double opacity = 1.0,
  }) {
    // 绘制输入端口
    for (int i = 0; i < building.ports.inputs.length; i++) {
      final port = building.ports.inputs[i];
      final px = port.relativeX * building.gridWidth * cellSize;
      final py = port.relativeY * building.gridHeight * cellSize;
      final isConnected = portConnections?['input_$i'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        port.direction,
        cellSize,
        isOutput: false,
        isActive: isConnected,
        opacity: opacity,
      );
    }

    // 绘制输出端口
    for (int i = 0; i < building.ports.outputs.length; i++) {
      final port = building.ports.outputs[i];
      final px = port.relativeX * building.gridWidth * cellSize;
      final py = port.relativeY * building.gridHeight * cellSize;
      final isConnected = portConnections?['output_$i'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        port.direction,
        cellSize,
        isOutput: true,
        isActive: isConnected,
        opacity: opacity,
      );
    }
  }

  static void _drawArrow(
    Canvas canvas,
    double px,
    double py,
    String direction,
    double cellSize, {
    required bool isOutput,
    required bool isActive,
    double opacity = 1.0,
  }) {
    final color = isActive
        ? _portActiveColor.withValues(alpha: opacity)
        : _portInactiveColor.withValues(alpha: opacity);

    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final arrowLen = cellSize * _arrowLength;
    final arrowHead = cellSize * _arrowHeadSize;

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

    final dir = end - start;
    final dirNorm = dir / dir.distance;
    final perp = Offset(-dirNorm.dy, dirNorm.dx) * arrowHead * 0.7;
    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - dirNorm.dx * arrowHead + perp.dx,
        end.dy - dirNorm.dy * arrowHead + perp.dy,
      )
      ..lineTo(
        end.dx - dirNorm.dx * arrowHead - perp.dx,
        end.dy - dirNorm.dy * arrowHead - perp.dy,
      )
      ..close();
    canvas.drawPath(headPath, Paint()..color = color);

    // 端口方块
    final portRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(px, py), width: _portSize, height: _portSize),
      const Radius.circular(2.0),
    );
    canvas.drawRRect(
      portRect,
      Paint()..color = color.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      portRect,
      Paint()
        ..color = color
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  static void _drawName(Canvas canvas, double w, String name) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: _frameColor.withValues(alpha: 0.7),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: w - 4);
    textPainter.paint(canvas, const Offset(2, 2));
  }
}
