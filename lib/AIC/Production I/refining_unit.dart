import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/building.dart';
import '../../models/recipe.dart';

/// 精炼炉配置常量
class RefiningUnitConfig {
  static const String id = 'refining_unit_3x3';
  static const String name = '精炼炉';
  static const int gridWidth = 3;
  static const int gridHeight = 3;
  static const String color = '#E8751A';
  static const String category = 'basic_production';
  static const int maxInputs = 4; // 3个固体进料口 + 1个液体输入口
  static const int maxOutputs = 4; // 3个固体出料口 + 1个液体输出口

  /// 端口定义：基于3x3网格坐标
  /// 出料口: (0,0) (1,0) (2,0) - 顶边，方向向上
  /// 进料口: (0,2) (1,2) (2,2) - 底边，方向向下
  /// 液体输入口: (0,1) - 左边，方向向左
  /// 液体输出口: (2,1) - 右边，方向向右
  static List<PortDefinition> get inputPorts => [
    // 固体进料口 - 底边三个格子
    const PortDefinition(
      relativeX: (0 + 0.5) / gridWidth,
      relativeY: 1.0,
      direction: 'down',
      portType: 'solid',
    ),
    const PortDefinition(
      relativeX: (1 + 0.5) / gridWidth,
      relativeY: 1.0,
      direction: 'down',
      portType: 'solid',
    ),
    const PortDefinition(
      relativeX: (2 + 0.5) / gridWidth,
      relativeY: 1.0,
      direction: 'down',
      portType: 'solid',
    ),
    // 液体输入口 - 左边中间格子
    const PortDefinition(
      relativeX: 0.0,
      relativeY: (1 + 0.5) / gridHeight,
      direction: 'left',
      portType: 'liquid',
    ),
  ];

  static List<PortDefinition> get outputPorts => [
    // 固体出料口 - 顶边三个格子
    const PortDefinition(
      relativeX: (0 + 0.5) / gridWidth,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
    const PortDefinition(
      relativeX: (1 + 0.5) / gridWidth,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
    const PortDefinition(
      relativeX: (2 + 0.5) / gridWidth,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
    // 液体输出口 - 右边中间格子
    const PortDefinition(
      relativeX: 1.0,
      relativeY: (1 + 0.5) / gridHeight,
      direction: 'right',
      portType: 'liquid',
    ),
  ];
}

/// 精炼炉专用渲染器
/// 独立于通用 BuildingRenderer，方便后续设备扩展维护
class RefiningUnitRenderer {
  // 颜色常量
  static const Color _frameColor = Color(0xFF333333);
  static const Color _cellBorderColor = Color(0xFF555555);
  static const Color _solidPortColor = Color(0xFFFFCC00);
  static const Color _liquidPortColor = Color(0xFF44AAFF);
  static const Color _portInactiveColor = Color(0xFF666666);
  static const Color _blockedOverlayColor = Color(0x40FF0000);
  static const Color _bodyColor = Color(0xFFE8751A);

  // 尺寸常量
  static const double _frameStrokeWidth = 3.0;
  static const double _cellBorderStrokeWidth = 0.8;
  static const double _portSize = 10.0;
  static const double _arrowLength = 0.3; // 相对于 cellSize 的比例
  static const double _arrowHeadSize = 0.12;

  /// 渲染精炼炉
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

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(rotation * math.pi / 2);
    canvas.translate(-w / 2, -h / 2);

    // 1. 绘制设备主体
    _drawBody(canvas, w, h, isBlocked);

    // 2. LOD 1+: 内部网格线
    if (detailLevel >= 1) {
      _drawCellGrid(canvas, w, h, cellSize);
    }

    // 3. LOD 2: 端口箭头
    if (detailLevel >= 2) {
      _drawPortArrows(canvas, building, cellSize, portConnections);
    }

    // 4. LOD 1+: 进度条
    if (detailLevel >= 1 && productionProgress > 0 && productionProgress < 1.0) {
      _drawProgressBar(canvas, w, h, productionProgress);
    }

    // 5. LOD 2: 设备名称
    if (detailLevel >= 2) {
      _drawName(canvas, w);
    }

    // 6. LOD 2: 配方标签
    if (detailLevel >= 2 && activeRecipe != null) {
      _drawRecipeLabel(canvas, activeRecipe.name, w);
    }

    canvas.restore();
  }

  /// 渲染放置预览（半透明）
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

    final paint = Paint()
      ..color = _bodyColor.withValues(alpha: opacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);

    final borderPaint = Paint()
      ..color = _bodyColor.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), borderPaint);

    // 预览时也画端口箭头
    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.translate(-w / 2, -h / 2);
    _drawPortArrows(canvas, building, cellSize, null, opacity: opacity * 0.6);
    canvas.restore();
  }

  static void _drawBody(Canvas canvas, double w, double h, bool isBlocked) {
    // 填充背景
    final fillPaint = Paint()..color = _bodyColor.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fillPaint);

    // 外边框
    final framePaint = Paint()
      ..color = _frameColor
      ..strokeWidth = _frameStrokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), framePaint);

    // 阻塞遮罩
    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
    }
  }

  static void _drawCellGrid(Canvas canvas, double w, double h, double cellSize) {
    final gridPaint = Paint()
      ..color = _cellBorderColor
      ..strokeWidth = _cellBorderStrokeWidth
      ..style = PaintingStyle.stroke;

    // 竖线（3列之间2条线）
    for (int col = 1; col < 3; col++) {
      final x = col * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    // 横线（3行之间2条线）
    for (int row = 1; row < 3; row++) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
  }

  static void _drawPortArrows(
    Canvas canvas,
    Building building,
    double cellSize,
    Map<String, bool>? portConnections, {
    double opacity = 1.0,
  }) {
    final w = building.gridWidth * cellSize;

    // 绘制出料口箭头（顶边3个）
    for (int i = 0; i < 3; i++) {
      final px = (i + 0.5) * cellSize;
      const py = 0.0;
      final isConnected = portConnections?['output_$i'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        'up',
        cellSize,
        isOutput: true,
        isLiquid: false,
        isActive: isConnected,
        opacity: opacity,
      );
    }

    // 绘制进料口箭头（底边3个）
    for (int i = 0; i < 3; i++) {
      final px = (i + 0.5) * cellSize;
      final py = 3.0 * cellSize;
      final isConnected = portConnections?['input_$i'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        'down',
        cellSize,
        isOutput: false,
        isLiquid: false,
        isActive: isConnected,
        opacity: opacity,
      );
    }

    // 绘制液体输入口箭头（左边中间）
    {
      const px = 0.0;
      final py = 1.5 * cellSize;
      final isConnected = portConnections?['input_3'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        'left',
        cellSize,
        isOutput: false,
        isLiquid: true,
        isActive: isConnected,
        opacity: opacity,
      );
    }

    // 绘制液体输出口箭头（右边中间）
    {
      final px = w;
      final py = 1.5 * cellSize;
      final isConnected = portConnections?['output_3'] ?? false;
      _drawArrow(
        canvas,
        px,
        py,
        'right',
        cellSize,
        isOutput: true,
        isLiquid: true,
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
    required bool isLiquid,
    required bool isActive,
    double opacity = 1.0,
  }) {
    final baseColor = isLiquid ? _liquidPortColor : _solidPortColor;
    final color = isActive
        ? baseColor.withValues(alpha: opacity)
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

    // 画箭头线段
    canvas.drawLine(start, end, arrowPaint);

    // 画箭头头部
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

    // 液体端口额外标记：小圆圈
    if (isLiquid) {
      final circlePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final circleCenter = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );
      canvas.drawCircle(circleCenter, cellSize * 0.06, circlePaint);
    }

    // 端口方块标记
    final portRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(px, py), width: _portSize, height: _portSize),
      const Radius.circular(2.0),
    );
    final portFillPaint = Paint()
      ..color = color.withValues(alpha: 0.6);
    canvas.drawRRect(portRect, portFillPaint);
    final portStrokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(portRect, portStrokePaint);
  }

  static void _drawProgressBar(Canvas canvas, double w, double h, double progress) {
    const barHeight = 4.0;
    final barY = h - barHeight - 2;

    final bgPaint = Paint()..color = const Color(0x40000000);
    canvas.drawRect(Rect.fromLTWH(2, barY, w - 4, barHeight), bgPaint);

    final progressPaint = Paint()..color = const Color(0xFF00FF66);
    canvas.drawRect(
      Rect.fromLTWH(2, barY, (w - 4) * progress, barHeight),
      progressPaint,
    );
  }

  static void _drawName(Canvas canvas, double w) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: RefiningUnitConfig.name,
        style: TextStyle(
          color: _frameColor.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: w - 4);
    textPainter.paint(canvas, const Offset(2, 2));
  }

  static void _drawRecipeLabel(Canvas canvas, String recipeName, double w) {
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
}
