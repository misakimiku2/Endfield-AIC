import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/building.dart';
import '../../models/recipe.dart';
import '../../canvas/building_renderer.dart';

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

/// 仓库存取货口共用渲染器（模块化：基础单元 + Logo）
/// Logo 单独绘制，始终不随设备/画布旋转
class DepotAccessRenderer {
  // 颜色常量
  static const Color _frameColor = Color(0xFF333333);
  static const Color _blockedOverlayColor = Color(0x40FF0000);
  static const Color _loaderBodyColor = Color(0xFF44AA88);
  static const Color _unloaderBodyColor = Color(0xFFAA8844);

  // 模块定位常量（基于原始 50.8×16.933333 坐标系的相对比例）
  static const double _baseSvgW = 50.8;
  static const double _baseSvgH = 16.933333;

  // Loader Logo 在基础坐标系中的位置
  static const double _loaderLogoRelX = 20.058723 / _baseSvgW;
  static const double _loaderLogoRelY = 3.3388142 / _baseSvgH;
  static const double _loaderLogoRelW = 9.3906411 / _baseSvgW;
  static const double _loaderLogoRelH = 12.213725 / _baseSvgH;

  // Unloader Logo 在基础坐标系中的位置
  static const double _unloaderLogoRelX = 20.704502 / _baseSvgW;
  static const double _unloaderLogoRelY = 3.3385737 / _baseSvgH;
  static const double _unloaderLogoRelW = 9.3909903 / _baseSvgW;
  static const double _unloaderLogoRelH = 12.214105 / _baseSvgH;

  // SVG 源字符串
  static String? _baseSvgStr;

  // 基础单元 PictureInfo 和缓存
  static PictureInfo? _baseSvgPicture;
  static final Map<String, PictureInfo> _baseSvgCache = {};

  // Logo PictureInfo
  static PictureInfo? _loaderLogoPicture;
  static PictureInfo? _unloaderLogoPicture;

  static bool _initialized = false;
  static bool _initializing = false;
  static VoidCallback? _onReadyCallback;

  /// 预加载仓库存取口 SVG 资源（模块化：基础单元 + Logo）
  /// [onReady] 加载完成后的回调，用于通知外部刷新缓存和重绘
  static Future<void> init({VoidCallback? onReady}) async {
    _onReadyCallback = onReady;
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // 1. 加载各模块原始 SVG 字符串
      _baseSvgStr = await rootBundle.loadString('assets/svg/Depot.svg');
      final loaderLogoSvgStr = await rootBundle.loadString('assets/svg/LOGO/Depot_Loader_logo.svg');
      final unloaderLogoSvgStr = await rootBundle.loadString('assets/svg/LOGO/Depot_Unloader_logo.svg');

      // 2. 生成默认状态 SVG 并清理 Inkscape
      final baseDefaultSvg = _cleanInkscapeSvg(_generateBaseModifiedSvg(_baseSvgStr!, '0'));
      final loaderLogoSvg = _cleanInkscapeSvg(loaderLogoSvgStr);
      final unloaderLogoSvg = _cleanInkscapeSvg(unloaderLogoSvgStr);

      // 3. 解析为 PictureInfo 并缓存
      _baseSvgPicture = await vg.loadPicture(SvgStringLoader(baseDefaultSvg), null);
      _baseSvgCache['0'] = _baseSvgPicture!;

      _loaderLogoPicture = await vg.loadPicture(SvgStringLoader(loaderLogoSvg), null);
      _unloaderLogoPicture = await vg.loadPicture(SvgStringLoader(unloaderLogoSvg), null);

      _initialized = true;

      // 4. 通知外部刷新
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load depot access SVGs: $e');
    } finally {
      _initializing = false;
    }
  }

  /// 清理 Inkscape SVG 中 flutter_svg 不兼容的元素
  static String _cleanInkscapeSvg(String svg) {
    var result = svg;

    result = result.replaceAll(
      RegExp(r'<sodipodi:namedview[\s\S]*?</sodipodi:namedview>', multiLine: true), '',
    );
    result = result.replaceAll(
      RegExp(r'<inkscape:path-effect[\s\S]*?/>', multiLine: true), '',
    );
    result = result.replaceAll(
      RegExp(r'<image[\s\S]*?/>', multiLine: true), '',
    );
    result = result.replaceAll(RegExp(r'\s+inkscape:[a-zA-Z-]+="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+sodipodi:[a-zA-Z-]+="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+xmlns:inkscape="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+xmlns:sodipodi="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'<defs\s*>\s*</defs>'), '');

    return result;
  }

  /// SVG 是否已加载完成
  static bool get isReady =>
      _initialized &&
      _baseSvgPicture != null &&
      _loaderLogoPicture != null &&
      _unloaderLogoPicture != null;

  /// 渲染仓库存取货口（不含 Logo，Logo 需通过 [renderLogo] 单独绘制）
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

    // 1. 绘制设备主体（不含 Logo）
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

  /// 渲染放置预览（半透明，不含 Logo，Logo 需单独绘制）
  static void renderPlaceholder(
    Canvas canvas,
    Building building,
    double gridX,
    double gridY,
    double cellSize,
    double opacity, {
    int rotation = 0,
    bool isBlocked = false,
    double canvasRotation = 0.0,
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
      _drawSvgBody(canvas, w, h, building.id,
          opacity: opacity * 0.5,
          portConnections: null,
          tintBlue: !isBlocked,
          tintRed: isBlocked);
    } else {
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

    BuildingRenderer.drawPortArrows(canvas, building, w, h, cellSize, opacity: opacity);

    canvas.restore();

    // Logo 单独绘制，反旋转抵消设备旋转 + 画布旋转
    if (isReady) {
      renderLogo(
        canvas, x, y, w, h, building.id, rotation, canvasRotation,
        opacity: opacity * 0.5,
        tintBlue: !isBlocked,
        tintRed: isBlocked,
      );
    }
  }

  /// 单独渲染 Logo，始终不随设备旋转和画布旋转
  /// [x], [y] 建筑在画布坐标系中的左上角位置
  /// [w], [h] 建筑的像素尺寸
  /// [buildingId] 建筑ID，用于选择对应的 Logo
  /// [buildingRotation] 建筑自身的旋转（0/1/2/3）
  /// [canvasRotation] 画布/视图旋转角度（弧度）
  static void renderLogo(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    String buildingId,
    int buildingRotation,
    double canvasRotation, {
    double opacity = 1.0,
    bool tintBlue = false,
    bool tintRed = false,
  }) {
    final isLoader = buildingId == DepotLoaderConfig.id;
    final logoPicture = isLoader ? _loaderLogoPicture : _unloaderLogoPicture;
    if (logoPicture == null) return;

    final buildingAngle = buildingRotation * math.pi / 2;
    final counterAngle = -(buildingAngle + canvasRotation);

    final logoRelX = isLoader ? _loaderLogoRelX : _unloaderLogoRelX;
    final logoRelY = isLoader ? _loaderLogoRelY : _unloaderLogoRelY;
    final logoRelW = isLoader ? _loaderLogoRelW : _unloaderLogoRelW;
    final logoRelH = isLoader ? _loaderLogoRelH : _unloaderLogoRelH;

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(buildingAngle);
    canvas.translate(-w / 2, -h / 2);

    final logoCx = logoRelX * w + logoRelW * w / 2;
    final logoCy = logoRelY * h + logoRelH * h / 2;

    if (tintRed) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter = const ColorFilter.mode(Color(0xFFFF4444), BlendMode.srcATop));
    } else if (tintBlue) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter = const ColorFilter.mode(Color(0xFF44AAFF), BlendMode.srcATop));
    } else if (opacity < 1.0) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    canvas.save();
    canvas.translate(logoCx, logoCy);
    canvas.rotate(counterAngle);
    canvas.translate(-logoCx, -logoCy);
    _drawPictureScaled(
      canvas,
      logoPicture,
      logoRelX * w,
      logoRelY * h,
      logoRelW * w,
      logoRelH * h,
    );
    canvas.restore();

    if (tintRed || tintBlue || opacity < 1.0) {
      canvas.restore();
    }

    canvas.restore();
  }

  // ==================== SVG 预加载 ====================

  static void _preloadBaseSvgForState(String stateKey) async {
    if (_baseSvgStr == null || _baseSvgCache.containsKey(stateKey)) return;
    _baseSvgCache[stateKey] = _baseSvgPicture!;

    try {
      final modifiedSvg = _generateBaseModifiedSvg(_baseSvgStr!, stateKey);
      final cleanedSvg = _cleanInkscapeSvg(modifiedSvg);
      final PictureInfo picture = await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _baseSvgCache[stateKey] = picture;
      _onReadyCallback?.call();
    } catch (e) {
      debugPrint('Failed to preload base depot SVG for state $stateKey: $e');
      _baseSvgCache.remove(stateKey);
    }
  }

  // ==================== SVG 动态颜色修改 ====================

  /// 修改基础单元 SVG 的端口颜色
  /// state: '0'=未连接, '1'=已连接(黄色), '2'=预览(蓝色)
  static String _generateBaseModifiedSvg(String baseSvg, String state) {
    var svgText = baseSvg;
    final portColor = (state == '1') ? '#ffef00' : ((state == '2') ? '#44aaff' : '#d3d3d3');
    svgText = _setElementColor(svgText, 'rect1', '#d3d3d3', portColor);
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

  // ==================== 连接键生成 ====================

  static String _getConnectionKey(String buildingId, Map<String, int>? portConnections) {
    if (portConnections == null) return '0';

    final isLoader = buildingId == DepotLoaderConfig.id;
    if (isLoader) {
      return portConnections['input_0']?.toString() ?? '0';
    } else {
      return portConnections['output_0']?.toString() ?? '0';
    }
  }

  // ==================== SVG 渲染 ====================

  static void _drawPictureScaled(Canvas canvas, PictureInfo picture,
      double x, double y, double width, double height) {
    canvas.save();
    canvas.translate(x, y);
    final scaleX = width / picture.size.width;
    final scaleY = height / picture.size.height;
    canvas.scale(scaleX, scaleY);
    canvas.drawPicture(picture.picture);
    canvas.restore();
  }

  /// 使用 SVG 绘制仓库存取口主体（不含 Logo）
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
    final stateKey = _getConnectionKey(buildingId, portConnections);

    var picture = _baseSvgCache[stateKey];
    if (picture == null) {
      _preloadBaseSvgForState(stateKey);
      picture = _baseSvgPicture;
    }

    if (picture == null) return;

    canvas.save();

    if (tintRed) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter = const ColorFilter.mode(Color(0xFFFF4444), BlendMode.srcATop));
    } else if (tintBlue) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter = const ColorFilter.mode(Color(0xFF44AAFF), BlendMode.srcATop));
    } else if (opacity < 1.0) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    _drawPictureScaled(canvas, picture, 0, 0, w, h);

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
}
