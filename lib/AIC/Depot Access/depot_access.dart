import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/building.dart';
import '../../models/recipe.dart';

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

/// 仓库存取货口共用渲染器（SVG 版本）
class DepotAccessRenderer {
  // 颜色常量
  static const Color _frameColor = Color(0xFF333333);
  static const Color _blockedOverlayColor = Color(0x40FF0000);
  static const Color _loaderBodyColor = Color(0xFF44AA88);
  static const Color _unloaderBodyColor = Color(0xFFAA8844);

  // SVG 缓存
  static PictureInfo? _loaderPicture;
  static PictureInfo? _unloaderPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  static String? _baseLoaderSvgStr;
  static String? _baseUnloaderSvgStr;
  static final Map<String, PictureInfo> _svgCache = {};

  /// 预加载仓库存取口 SVG 资源
  /// [onReady] 加载完成后的回调，用于通知外部刷新缓存和重绘
  static Future<void> init({VoidCallback? onReady}) async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // 1. 加载原始 SVG 字符串
      _baseLoaderSvgStr = await rootBundle.loadString('assets/svg/Depot_Loader.svg');
      _baseUnloaderSvgStr = await rootBundle.loadString('assets/svg/Depot_Unloader.svg');

      // 2. 清理 Inkscape 并预载默认图
      const defaultLoaderKey = 'L0';
      const defaultUnloaderKey = 'U0';

      final loaderSvg = _cleanInkscapeSvg(_baseLoaderSvgStr!);
      final unloaderSvg = _cleanInkscapeSvg(_baseUnloaderSvgStr!);

      // 3. 解析为 PictureInfo 并缓存
      _loaderPicture = await vg.loadPicture(SvgStringLoader(loaderSvg), null);
      _unloaderPicture = await vg.loadPicture(SvgStringLoader(unloaderSvg), null);

      _svgCache[defaultLoaderKey] = _loaderPicture!;
      _svgCache[defaultUnloaderKey] = _unloaderPicture!;

      _initialized = true;

      // 4. 通知外部刷新
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load depot access SVG: $e');
    } finally {
      _initializing = false;
    }
  }

  /// 清理 Inkscape SVG 中 flutter_svg 不兼容的元素
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

    // 移除 <image> 元素
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
  static bool get isReady => _initialized && _loaderPicture != null && _unloaderPicture != null;

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
    Map<String, int>? portConnections,
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

    // 1. 绘制设备主体 (SVG)
    if (isReady) {
      _drawSvgBody(canvas, w, h, building.id, portConnections: portConnections);
    } else {
      _drawBodyFallback(canvas, w, h, building.id);
    }

    // 2. 阻塞遮罩
    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
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
    double opacity, {
    int rotation = 0,
    bool isBlocked = false,
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
      _drawSvgBody(canvas, w, h, building.id, opacity: opacity * 0.5, portConnections: null, tintBlue: !isBlocked, tintRed: isBlocked);
    } else {
      // 碰撞时红色，否则蓝色
      final previewColor = isBlocked ? const Color(0xFFFF4444) : const Color(0xFF44AAFF);
      final paint = Paint()
        ..color = previewColor.withValues(alpha: opacity * 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

      final borderPaint = Paint()
        ..color = previewColor.withValues(alpha: opacity * 0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), borderPaint);
    }

    canvas.restore();
  }

  /// 使用 SVG 绘制仓库存取口主体
  static void _drawSvgBody(
    Canvas canvas,
    double w,
    double h,
    String buildingId, {
    double opacity = 1.0,
    Map<String, int>? portConnections,
    bool tintBlue = false,
    bool tintRed = false,
  }) {
    final isLoader = buildingId == DepotLoaderConfig.id;
    final key = _getConnectionKey(buildingId, portConnections);

    var picture = _svgCache[key] ?? (isLoader ? _loaderPicture : _unloaderPicture);

    if (picture == null) return;
    final svgSize = picture.size;

    canvas.save();

    if (tintRed) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..colorFilter = const ColorFilter.mode(Color(0xFFFF4444), BlendMode.srcATop));
    } else if (tintBlue) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..colorFilter = const ColorFilter.mode(Color(0xFF44AAFF), BlendMode.srcATop));
    } else if (opacity < 1.0) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    final scaleX = w / svgSize.width;
    final scaleY = h / svgSize.height;
    canvas.scale(scaleX, scaleY);
    canvas.drawPicture(picture.picture);

    if (tintRed || tintBlue || opacity < 1.0) {
      canvas.restore();
    }

    canvas.restore();
  }

  /// 旧版 Canvas 绘制（SVG 未加载时的回退）
  static void _drawBodyFallback(Canvas canvas, double w, double h, String buildingId) {
    final isLoader = buildingId == DepotLoaderConfig.id;
    final bodyColor = isLoader ? _loaderBodyColor : _unloaderBodyColor;

    final fillPaint = Paint()..color = bodyColor.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fillPaint);

    final framePaint = Paint()
      ..color = _frameColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), framePaint);
  }

  static String _getConnectionKey(String buildingId, Map<String, int>? portConnections) {
    if (portConnections == null) {
      return buildingId == DepotLoaderConfig.id ? 'L0' : 'U0';
    }
    final isLoader = buildingId == DepotLoaderConfig.id;
    if (isLoader) {
      // 存货口只有 1 个输入端口
      return 'L${portConnections['input_0'] ?? 0}';
    } else {
      // 取货口只有 1 个输出端口
      return 'U${portConnections['output_0'] ?? 0}';
    }
  }
}
