import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  static const Color _blockedOverlayColor = Color(0x40FF0000);
  static const Color _bodyColor = Color(0xFFE8751A);

  // 尺寸常量
  static const double _frameStrokeWidth = 3.0;
  static const double _cellBorderStrokeWidth = 0.8;

  // SVG 缓存
  static PictureInfo? _svgPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  static String? _baseSvgStr;
  static final Map<String, PictureInfo> _svgCache = {};
  static VoidCallback? _onReadyCallback;

  /// 预加载精炼炉 SVG 资源
  /// [onReady] 加载完成后的回调，用于通知外部刷新缓存和重绘
  static Future<void> init({VoidCallback? onReady}) async {
    _onReadyCallback = onReady;
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // 1. 加载原始 SVG 字符串
      _baseSvgStr = await rootBundle.loadString('assets/svg/Refining_Unit.svg');

      // 2. 清理 Inkscape 并预载全 0 的原始图
      final defaultKey = '00000000';
      final defaultSvg = _generateModifiedSvg(_baseSvgStr!, defaultKey);
      final cleanedSvg = _cleanInkscapeSvg(defaultSvg);

      // 3. 解析为 PictureInfo 并放到默认里
      _svgPicture = await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _svgCache[defaultKey] = _svgPicture!;
      _initialized = true;

      // 4. 通知外部刷新
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load refining unit SVG: $e');
    } finally {
      _initializing = false;
    }
  }

  /// 清理 Inkscape SVG 中 flutter_svg 不兼容的元素，使其可正常加载
  static String _cleanInkscapeSvg(String svg) {
    var result = svg;

    // 移除 <sodipodi:namedview> 块
    result = result.replaceAll(
      RegExp(r'<sodipodi:namedview[\s\S]*?</sodipodi:namedview>', multiLine: true), '',
    );

    // 移除 <inkscape:path-effect> 自闭合标签
    result = result.replaceAll(
      RegExp(r'<inkscape:path-effect[\s\S]*?/>', multiLine: true), '',
    );

    // 移除 <image> 元素（引用本地文件）
    result = result.replaceAll(
      RegExp(r'<image[\s\S]*?/>', multiLine: true), '',
    );

    // 移除 Inkscape/Sodipodi 特有属性
    result = result.replaceAll(RegExp(r'\s+inkscape:[a-zA-Z-]+="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+sodipodi:[a-zA-Z-]+="[^"]*"'), '');

    // 移除 Inkscape 命名空间声明
    result = result.replaceAll(RegExp(r'\s+xmlns:inkscape="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+xmlns:sodipodi="[^"]*"'), '');

    // 移除空的 <defs></defs>
    result = result.replaceAll(RegExp(r'<defs\s*>\s*</defs>'), '');

    return result;
  }

  /// SVG 是否已加载完成
  static bool get isReady => _initialized && _svgPicture != null;

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

    // 1. 绘制设备主体 (通过带有特定高亮端口状态的动态 SVG)
    if (isReady) {
      _drawSvgBody(canvas, w, h, portConnections: portConnections);
    } else {
      _drawBodyFallback(canvas, w, h);
    }

    // 2. 阻塞遮罩
    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
    }

    // 3. LOD 1+: 进度条
    if (detailLevel >= 1 && productionProgress > 0 && productionProgress < 1.0) {
      _drawProgressBar(canvas, w, h, productionProgress);
    }

    // 4. LOD 2: 配方标签
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

    if (isReady) {
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.translate(-w / 2, -h / 2);
      _drawSvgBody(canvas, w, h, opacity: opacity * 0.5, portConnections: null);
      canvas.restore();
    } else {
      final paint = Paint()
        ..color = _bodyColor.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

      final borderPaint = Paint()
        ..color = _bodyColor.withValues(alpha: opacity)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), borderPaint);
    }

    canvas.restore();
  }

  static String _getConnectionKey(Map<String, bool>? portConnections) {
    if (portConnections == null) return '00000000';
    final sb = StringBuffer();
    sb.write(portConnections['output_0'] == true ? '1' : '0');
    sb.write(portConnections['output_1'] == true ? '1' : '0');
    sb.write(portConnections['output_2'] == true ? '1' : '0');
    sb.write(portConnections['output_3'] == true ? '1' : '0');
    sb.write(portConnections['input_0'] == true ? '1' : '0');
    sb.write(portConnections['input_1'] == true ? '1' : '0');
    sb.write(portConnections['input_2'] == true ? '1' : '0');
    sb.write(portConnections['input_3'] == true ? '1' : '0');
    return sb.toString();
  }

  static void _preloadSvgForState(String key) async {
    if (_baseSvgStr == null) return;
    // 使用默认图占个位，防止重复预载
    _svgCache[key] = _svgPicture!;

    try {
      final modifiedSvg = _generateModifiedSvg(_baseSvgStr!, key);
      final cleanedSvg = _cleanInkscapeSvg(modifiedSvg);
      final PictureInfo picture = await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _svgCache[key] = picture;
      _onReadyCallback?.call();
    } catch (e) {
      debugPrint('Failed to load modified SVG for state $key: $e');
      _svgCache.remove(key);
    }
  }

  static String _generateModifiedSvg(String baseSvg, String key) {
    var svgText = baseSvg;

    // 1. output_0 (顶左): rect9 (#cbc9c9), rect68 (#e0dede)
    final out0ColorBg = (key[0] == '1') ? '#ffef00' : '#cbc9c9';
    final out0ColorFg = (key[0] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect9', '#cbc9c9', out0ColorBg);
    svgText = _setElementColor(svgText, 'rect68', '#e0dede', out0ColorFg);

    // 2. output_1 (顶中): rect11 (#cbc9c9), rect66 (#e0dede)
    final out1ColorBg = (key[1] == '1') ? '#ffef00' : '#cbc9c9';
    final out1ColorFg = (key[1] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect11', '#cbc9c9', out1ColorBg);
    svgText = _setElementColor(svgText, 'rect66', '#e0dede', out1ColorFg);

    // 3. output_2 (顶右): rect7 (#cbc9c9), rect70 (#e0dede)
    final out2ColorBg = (key[2] == '1') ? '#ffef00' : '#cbc9c9';
    final out2ColorFg = (key[2] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect7', '#cbc9c9', out2ColorBg);
    svgText = _setElementColor(svgText, 'rect70', '#e0dede', out2ColorFg);

    // 4. output_3 (液体右): path79 (#ffffff)
    final out3ColorBg = (key[3] == '1') ? '#ffef00' : '#ffffff';
    svgText = _setElementColor(svgText, 'path79', '#ffffff', out3ColorBg);

    // 5. input_0 (底左): rect1 (#cbc9c9), rect61 (#e0dede)
    final in0ColorBg = (key[4] == '1') ? '#ffef00' : '#cbc9c9';
    final in0ColorFg = (key[4] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect1', '#cbc9c9', in0ColorBg);
    svgText = _setElementColor(svgText, 'rect61', '#e0dede', in0ColorFg);

    // 6. input_1 (底中): rect3 (#cbc9c9), rect59 (#e0dede)
    final in1ColorBg = (key[5] == '1') ? '#ffef00' : '#cbc9c9';
    final in1ColorFg = (key[5] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect3', '#cbc9c9', in1ColorBg);
    svgText = _setElementColor(svgText, 'rect59', '#e0dede', in1ColorFg);

    // 7. input_2 (底右): rect5 (#cbc9c9), rect63 (#e0dede)
    final in2ColorBg = (key[6] == '1') ? '#ffef00' : '#cbc9c9';
    final in2ColorFg = (key[6] == '1') ? '#ffef00' : '#e0dede';
    svgText = _setElementColor(svgText, 'rect5', '#cbc9c9', in2ColorBg);
    svgText = _setElementColor(svgText, 'rect63', '#e0dede', in2ColorFg);

    // 8. input_3 (液体左): circle73 (#ffef00)
    final in3ColorBg = (key[7] == '1') ? '#ffef00' : '#ffef00';
    svgText = _setElementColor(svgText, 'circle73', '#ffef00', in3ColorBg);

    return svgText;
  }

  static String _setElementColor(String svg, String elementId, String oldColor, String newColor) {
    final regExp = RegExp(
      '(<[a-zA-Z0-9_-]+[^>]*?id="$elementId"[^>]*?>)',
      multiLine: true,
      dotAll: true,
    );

    return svg.replaceAllMapped(regExp, (match) {
      final tag = match.group(1)!;
      return tag
          .replaceAll(oldColor.toLowerCase(), newColor)
          .replaceAll(oldColor.toUpperCase(), newColor);
    });
  }

  /// 使用 SVG 绘制精炼炉主体
  static void _drawSvgBody(Canvas canvas, double w, double h, {double opacity = 1.0, Map<String, bool>? portConnections}) {
    final key = _getConnectionKey(portConnections);
    var picture = _svgCache[key];

    if (picture == null) {
      _preloadSvgForState(key);
      picture = _svgPicture; // 临时退回到默认原始状态
    }

    if (picture == null) return;
    final svgSize = picture.size;

    canvas.save();

    if (opacity < 1.0) {
      // 使用 saveLayer 实现半透明
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    final scaleX = w / svgSize.width;
    final scaleY = h / svgSize.height;
    canvas.scale(scaleX, scaleY);
    canvas.drawPicture(picture.picture);

    if (opacity < 1.0) {
      canvas.restore();
    }

    canvas.restore();
  }

  /// 旧版 Canvas 绘制（SVG 未加载时的回退）
  static void _drawBodyFallback(Canvas canvas, double w, double h) {
    // 填充背景
    final fillPaint = Paint()..color = _bodyColor.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fillPaint);

    // 外边框
    final framePaint = Paint()
      ..color = _frameColor
      ..strokeWidth = _frameStrokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), framePaint);

    // 内部网格线
    final cellSize = w / RefiningUnitConfig.gridWidth;
    final gridPaint = Paint()
      ..color = _cellBorderColor
      ..strokeWidth = _cellBorderStrokeWidth
      ..style = PaintingStyle.stroke;

    for (int col = 1; col < RefiningUnitConfig.gridWidth; col++) {
      final x = col * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (int row = 1; row < RefiningUnitConfig.gridHeight; row++) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
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
