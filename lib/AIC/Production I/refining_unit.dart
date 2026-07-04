import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/building.dart';
import '../../models/recipe.dart';
import '../../constants/building_ids.dart';
import '../../canvas/building_renderer.dart';
import '../../utils/error_handler.dart';

/// 精炼炉配置常量
class RefiningUnitConfig {
  static const String id = BuildingIds.refiningUnit3x3;
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
/// 模块化组合：基础3x3单元 + 左侧出水口 + 右侧进水口 + 中央Logo
/// Logo 单独绘制，始终不随设备/画布旋转
class RefiningUnitRenderer {
  // 颜色常量
  static const Color _frameColor = Color(0xFF333333);
  static const Color _cellBorderColor = Color(0xFF555555);
  static const Color _bodyColor = Color(0xFFE8751A);

  // 尺寸常量
  static const double _frameStrokeWidth = 3.0;
  static const double _cellBorderStrokeWidth = 0.8;

  // 模块定位常量（基于原始 50.8mm 坐标系的相对比例）
  static const double _baseSvgSize = 50.8;

  // 左侧出水口（liquid_export）在基础坐标系中的位置
  static const double _liquidExportRelX = 1.8520834 / _baseSvgSize;
  static const double _liquidExportRelY = 16.933333 / _baseSvgSize;
  static const double _liquidExportRelW = 8.466666 / _baseSvgSize;
  static const double _liquidExportRelH = 16.933332 / _baseSvgSize;

  // 右侧进水口（liquid_import）在基础坐标系中的位置
  static const double _liquidImportRelX =
      (50.8 - 1.8520834 - 8.466666) / _baseSvgSize;
  static const double _liquidImportRelY = 16.933333 / _baseSvgSize;
  static const double _liquidImportRelW = 8.466666 / _baseSvgSize;
  static const double _liquidImportRelH = 16.933332 / _baseSvgSize;

  // 中央Logo在基础坐标系中的位置
  static const double _logoRelX = 19.594412 / _baseSvgSize;
  static const double _logoRelY = 17.617273 / _baseSvgSize;
  static const double _logoRelW = 13.664799 / _baseSvgSize;
  static const double _logoRelH = 15.145328 / _baseSvgSize;

  // SVG 源字符串（各模块）
  static String? _baseSvgStr;
  static String? _liquidExportSvgStr;
  static String? _liquidImportSvgStr;
  static String? _logoSvgStr;

  // 默认 PictureInfo（各模块）
  static PictureInfo? _baseSvgPicture;
  static PictureInfo? _liquidExportSvgPicture;
  static PictureInfo? _liquidImportSvgPicture;
  static PictureInfo? _logoSvgPicture;

  // 各模块的 SVG 缓存
  static final Map<String, PictureInfo> _baseSvgCache = {};
  static final Map<String, PictureInfo> _liquidExportCache = {};
  static final Map<String, PictureInfo> _liquidImportCache = {};

  static bool _initialized = false;
  static bool _initializing = false;
  static VoidCallback? _onReadyCallback;

  /// 预加载精炼炉 SVG 资源（模块化：基础单元 + 液体端口 + Logo）
  /// [onReady] 加载完成后的回调，用于通知外部刷新缓存和重绘
  static Future<void> init({VoidCallback? onReady}) async {
    _onReadyCallback = onReady;
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // 1. 加载各模块原始 SVG 字符串
      _baseSvgStr =
          await rootBundle.loadString('assets/svg/3x3_unit.svg');
      _liquidExportSvgStr =
          await rootBundle.loadString('assets/svg/liquid_export.svg');
      _liquidImportSvgStr =
          await rootBundle.loadString('assets/svg/liquid_import.svg');
      _logoSvgStr = await rootBundle.loadString(
          'assets/svg/LOGO/Refining_Unit_Logo.svg');

      // 2. 生成默认状态 SVG 并清理 Inkscape
      final baseDefaultSvg = _cleanInkscapeSvg(
          _generateBaseModifiedSvg(_baseSvgStr!, '000000'));
      final exportDefaultSvg = _cleanInkscapeSvg(
          _generateLiquidExportModifiedSvg(_liquidExportSvgStr!, '0'));
      final importDefaultSvg = _cleanInkscapeSvg(
          _generateLiquidImportModifiedSvg(_liquidImportSvgStr!, '0'));
      final logoSvg = _cleanInkscapeSvg(_logoSvgStr!);

      // 3. 解析为 PictureInfo 并缓存
      _baseSvgPicture =
          await vg.loadPicture(SvgStringLoader(baseDefaultSvg), null);
      _baseSvgCache['000000'] = _baseSvgPicture!;

      _liquidExportSvgPicture =
          await vg.loadPicture(SvgStringLoader(exportDefaultSvg), null);
      _liquidExportCache['0'] = _liquidExportSvgPicture!;

      _liquidImportSvgPicture =
          await vg.loadPicture(SvgStringLoader(importDefaultSvg), null);
      _liquidImportCache['0'] = _liquidImportSvgPicture!;

      _logoSvgPicture =
          await vg.loadPicture(SvgStringLoader(logoSvg), null);

      _initialized = true;

      // 4. 通知外部刷新
      onReady?.call();
    } catch (e, stackTrace) {
      AppError(
        message: 'Failed to load refining unit SVGs: $e',
        severity: ErrorSeverity.warning,
        code: 'REFINING_SVG_INIT_FAILED',
        stackTrace: stackTrace,
      ).report();
    } finally {
      _initializing = false;
    }
  }

  /// 清理 Inkscape SVG 中 flutter_svg 不兼容的元素，使其可正常加载
  static String _cleanInkscapeSvg(String svg) {
    var result = svg;

    // 移除 <sodipodi:namedview> 块
    result = result.replaceAll(
      RegExp(r'<sodipodi:namedview[\s\S]*?</sodipodi:namedview>',
          multiLine: true),
      '',
    );

    // 移除 <inkscape:path-effect> 自闭合标签
    result = result.replaceAll(
      RegExp(r'<inkscape:path-effect[\s\S]*?/>', multiLine: true),
      '',
    );

    // 移除 <image> 元素（引用本地文件）
    result = result.replaceAll(
      RegExp(r'<image[\s\S]*?/>', multiLine: true),
      '',
    );

    // 移除 Inkscape/Sodipodi 特有属性
    result =
        result.replaceAll(RegExp(r'\s+inkscape:[a-zA-Z-]+="[^"]*"'), '');
    result =
        result.replaceAll(RegExp(r'\s+sodipodi:[a-zA-Z-]+="[^"]*"'), '');

    // 移除 Inkscape 命名空间声明
    result = result.replaceAll(RegExp(r'\s+xmlns:inkscape="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+xmlns:sodipodi="[^"]*"'), '');

    // 移除空的 <defs></defs>
    result = result.replaceAll(RegExp(r'<defs\s*>\s*</defs>'), '');

    return result;
  }

  /// SVG 是否已加载完成
  static bool get isReady =>
      _initialized &&
      _baseSvgPicture != null &&
      _liquidExportSvgPicture != null &&
      _liquidImportSvgPicture != null &&
      _logoSvgPicture != null;

  /// 渲染精炼炉（不含 Logo，Logo 需通过 [renderLogo] 单独绘制）
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
      _drawSvgBody(canvas, w, h, portConnections: portConnections);
    } else {
      _drawBodyFallback(canvas, w, h);
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
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.translate(-w / 2, -h / 2);
      _drawSvgBody(canvas, w, h,
          opacity: opacity * 0.5,
          portConnections: null,
          tintBlue: !isBlocked,
          tintRed: isBlocked);
      canvas.restore();
    } else {
      // 碰撞时红色，否则蓝色
      final previewColor =
          isBlocked ? const Color(0xFFFF4444) : const Color(0xFF44AAFF);
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
        canvas, x, y, w, h, rotation, canvasRotation,
        opacity: opacity * 0.5,
        tintBlue: !isBlocked,
        tintRed: isBlocked,
      );
    }
  }

  /// 单独渲染 Logo，始终不随设备旋转和画布旋转
  /// [x], [y] 建筑在画布坐标系中的左上角位置
  /// [w], [h] 建筑的像素尺寸
  /// [buildingRotation] 建筑自身的旋转（0/1/2/3）
  /// [canvasRotation] 画布/视图旋转角度（弧度）
  static void renderLogo(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    int buildingRotation,
    double canvasRotation, {
    double opacity = 1.0,
    bool tintBlue = false,
    bool tintRed = false,
  }) {
    final logoPicture = _logoSvgPicture;
    if (logoPicture == null) return;

    final buildingAngle = buildingRotation * math.pi / 2;
    final counterAngle = -(buildingAngle + canvasRotation);

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(buildingAngle);
    canvas.translate(-w / 2, -h / 2);

    final logoCx = _logoRelX * w + _logoRelW * w / 2;
    final logoCy = _logoRelY * h + _logoRelH * h / 2;

    if (tintRed) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter =
                const ColorFilter.mode(Color(0xFFFF4444), BlendMode.srcATop));
    } else if (tintBlue) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter =
                const ColorFilter.mode(Color(0xFF44AAFF), BlendMode.srcATop));
    } else if (opacity < 1.0) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    // Logo背景层（150%缩放，40%透明度）
    const bgScale = 1.5;
    final bgLogoW = _logoRelW * w * bgScale;
    final bgLogoH = _logoRelH * h * bgScale;
    final bgLogoX = logoCx - bgLogoW / 2;
    final bgLogoY = logoCy - bgLogoH / 2;

    canvas.save();
    canvas.translate(logoCx, logoCy);
    canvas.rotate(counterAngle);
    canvas.translate(-logoCx, -logoCy);
    canvas.saveLayer(
        Rect.fromLTWH(bgLogoX, bgLogoY, bgLogoW, bgLogoH),
        Paint()..color = const Color.fromRGBO(255, 255, 255, 0.4));
    _drawPictureScaled(canvas, logoPicture, bgLogoX, bgLogoY, bgLogoW, bgLogoH);
    canvas.restore();
    canvas.restore();

    // Logo前景层（原始大小）
    canvas.save();
    canvas.translate(logoCx, logoCy);
    canvas.rotate(counterAngle);
    canvas.translate(-logoCx, -logoCy);
    _drawPictureScaled(
      canvas,
      logoPicture,
      _logoRelX * w,
      _logoRelY * h,
      _logoRelW * w,
      _logoRelH * h,
    );
    canvas.restore();

    if (tintRed || tintBlue || opacity < 1.0) {
      canvas.restore();
    }

    canvas.restore();
  }

  // ==================== 连接键生成 ====================

  /// 生成固体端口的连接键（6位：out0 out1 out2 in0 in1 in2）
  static String _getSolidConnectionKey(Map<String, int>? portConnections) {
    if (portConnections == null) return '000000';
    final sb = StringBuffer();
    sb.write(portConnections['output_0']?.toString() ?? '0');
    sb.write(portConnections['output_1']?.toString() ?? '0');
    sb.write(portConnections['output_2']?.toString() ?? '0');
    sb.write(portConnections['input_0']?.toString() ?? '0');
    sb.write(portConnections['input_1']?.toString() ?? '0');
    sb.write(portConnections['input_2']?.toString() ?? '0');
    return sb.toString();
  }

  /// 生成左侧出水口的连接键（1位：input_3）
  static String _getLiquidExportKey(Map<String, int>? portConnections) {
    if (portConnections == null) return '0';
    return portConnections['input_3']?.toString() ?? '0';
  }

  /// 生成右侧进水口的连接键（1位：output_3）
  static String _getLiquidImportKey(Map<String, int>? portConnections) {
    if (portConnections == null) return '0';
    return portConnections['output_3']?.toString() ?? '0';
  }

  // ==================== SVG 预加载 ====================

  static void _preloadBaseSvgForState(String solidKey) async {
    if (_baseSvgStr == null || _baseSvgCache.containsKey(solidKey)) return;
    _baseSvgCache[solidKey] = _baseSvgPicture!;

    try {
      final modifiedSvg =
          _generateBaseModifiedSvg(_baseSvgStr!, solidKey);
      final cleanedSvg = _cleanInkscapeSvg(modifiedSvg);
      final PictureInfo picture =
          await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _baseSvgCache[solidKey] = picture;
      _onReadyCallback?.call();
    } catch (e, stackTrace) {
      AppError(
        message: 'Failed to preload base SVG for state $solidKey: $e',
        severity: ErrorSeverity.warning,
        code: 'REFINING_SVG_BASE_FAILED',
        stackTrace: stackTrace,
        context: {'stateKey': solidKey},
      ).report();
      _baseSvgCache.remove(solidKey);
    }
  }

  static void _preloadLiquidExportSvgForState(String exportKey) async {
    if (_liquidExportSvgStr == null ||
        _liquidExportCache.containsKey(exportKey)) {
      return;
    }
    _liquidExportCache[exportKey] = _liquidExportSvgPicture!;

    try {
      final modifiedSvg =
          _generateLiquidExportModifiedSvg(_liquidExportSvgStr!, exportKey);
      final cleanedSvg = _cleanInkscapeSvg(modifiedSvg);
      final PictureInfo picture =
          await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _liquidExportCache[exportKey] = picture;
      _onReadyCallback?.call();
    } catch (e, stackTrace) {
      AppError(
        message: 'Failed to preload liquid export SVG for state $exportKey: $e',
        severity: ErrorSeverity.warning,
        code: 'REFINING_SVG_EXPORT_FAILED',
        stackTrace: stackTrace,
        context: {'stateKey': exportKey},
      ).report();
      _liquidExportCache.remove(exportKey);
    }
  }

  static void _preloadLiquidImportSvgForState(String importKey) async {
    if (_liquidImportSvgStr == null ||
        _liquidImportCache.containsKey(importKey)) {
      return;
    }
    _liquidImportCache[importKey] = _liquidImportSvgPicture!;

    try {
      final modifiedSvg =
          _generateLiquidImportModifiedSvg(_liquidImportSvgStr!, importKey);
      final cleanedSvg = _cleanInkscapeSvg(modifiedSvg);
      final PictureInfo picture =
          await vg.loadPicture(SvgStringLoader(cleanedSvg), null);
      _liquidImportCache[importKey] = picture;
      _onReadyCallback?.call();
    } catch (e, stackTrace) {
      AppError(
        message: 'Failed to preload liquid import SVG for state $importKey: $e',
        severity: ErrorSeverity.warning,
        code: 'REFINING_SVG_IMPORT_FAILED',
        stackTrace: stackTrace,
        context: {'stateKey': importKey},
      ).report();
      _liquidImportCache.remove(importKey);
    }
  }

  // ==================== SVG 动态颜色修改 ====================

  /// 修改基础单元 SVG 的固体端口颜色
  /// key 格式：6位 "OOOIII"（out0 out1 out2 in0 in1 in2）
  static String _generateBaseModifiedSvg(String baseSvg, String key) {
    var svgText = baseSvg;

    // output_0 (顶左): rect9 (#cbc9c9), rect68 (#e0dede)
    final out0ColorBg =
        (key[0] == '1') ? '#ffef00' : ((key[0] == '2') ? '#44aaff' : '#cbc9c9');
    final out0ColorFg =
        (key[0] == '1') ? '#ffef00' : ((key[0] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect9', '#cbc9c9', out0ColorBg);
    svgText = _setElementColor(svgText, 'rect68', '#e0dede', out0ColorFg);

    // output_1 (顶中): rect11 (#cbc9c9), rect66 (#e0dede)
    final out1ColorBg =
        (key[1] == '1') ? '#ffef00' : ((key[1] == '2') ? '#44aaff' : '#cbc9c9');
    final out1ColorFg =
        (key[1] == '1') ? '#ffef00' : ((key[1] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect11', '#cbc9c9', out1ColorBg);
    svgText = _setElementColor(svgText, 'rect66', '#e0dede', out1ColorFg);

    // output_2 (顶右): rect7 (#cbc9c9), rect70 (#e0dede)
    final out2ColorBg =
        (key[2] == '1') ? '#ffef00' : ((key[2] == '2') ? '#44aaff' : '#cbc9c9');
    final out2ColorFg =
        (key[2] == '1') ? '#ffef00' : ((key[2] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect7', '#cbc9c9', out2ColorBg);
    svgText = _setElementColor(svgText, 'rect70', '#e0dede', out2ColorFg);

    // input_0 (底左): rect1 (#cbc9c9), rect61 (#e0dede)
    final in0ColorBg =
        (key[3] == '1') ? '#ffef00' : ((key[3] == '2') ? '#44aaff' : '#cbc9c9');
    final in0ColorFg =
        (key[3] == '1') ? '#ffef00' : ((key[3] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect1', '#cbc9c9', in0ColorBg);
    svgText = _setElementColor(svgText, 'rect61', '#e0dede', in0ColorFg);

    // input_1 (底中): rect3 (#cbc9c9), rect59 (#e0dede)
    final in1ColorBg =
        (key[4] == '1') ? '#ffef00' : ((key[4] == '2') ? '#44aaff' : '#cbc9c9');
    final in1ColorFg =
        (key[4] == '1') ? '#ffef00' : ((key[4] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect3', '#cbc9c9', in1ColorBg);
    svgText = _setElementColor(svgText, 'rect59', '#e0dede', in1ColorFg);

    // input_2 (底右): rect5 (#cbc9c9), rect63 (#e0dede)
    final in2ColorBg =
        (key[5] == '1') ? '#ffef00' : ((key[5] == '2') ? '#44aaff' : '#cbc9c9');
    final in2ColorFg =
        (key[5] == '1') ? '#ffef00' : ((key[5] == '2') ? '#44aaff' : '#e0dede');
    svgText = _setElementColor(svgText, 'rect5', '#cbc9c9', in2ColorBg);
    svgText = _setElementColor(svgText, 'rect63', '#e0dede', in2ColorFg);

    return svgText;
  }

  /// 修改左侧出水口 SVG 的颜色
  /// key: input_3 的状态（0=默认, 1=连接, 2=预览蓝）
  static String _generateLiquidExportModifiedSvg(String svg, String key) {
    var svgText = svg;
    // input_3 (液体左): circle73 (#ffef00)
    final color = (key == '2') ? '#44aaff' : '#ffef00';
    svgText = _setElementColor(svgText, 'circle73', '#ffef00', color);
    return svgText;
  }

  /// 修改右侧进水口 SVG 的颜色
  /// key: output_3 的状态（0=默认, 1=连接, 2=预览蓝）
  static String _generateLiquidImportModifiedSvg(String svg, String key) {
    var svgText = svg;
    // output_3 (液体右): path79 (#ffffff)
    final color =
        (key == '1') ? '#ffef00' : ((key == '2') ? '#44aaff' : '#ffffff');
    svgText = _setElementColor(svgText, 'path79', '#ffffff', color);
    return svgText;
  }

  static String _setElementColor(
      String svg, String elementId, String oldColor, String newColor) {
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

  // ==================== SVG 组合渲染 ====================

  /// 将 PictureInfo 缩放绘制到指定矩形区域
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

  /// 使用模块化 SVG 组合绘制精炼炉主体（不含 Logo）
  static void _drawSvgBody(Canvas canvas, double w, double h,
      {double opacity = 1.0,
      Map<String, int>? portConnections,
      bool tintBlue = false,
      bool tintRed = false}) {
    final solidKey = _getSolidConnectionKey(portConnections);
    final exportKey = _getLiquidExportKey(portConnections);
    final importKey = _getLiquidImportKey(portConnections);

    var basePicture = _baseSvgCache[solidKey];
    if (basePicture == null) {
      _preloadBaseSvgForState(solidKey);
      basePicture = _baseSvgPicture;
    }

    var exportPicture = _liquidExportCache[exportKey];
    if (exportPicture == null) {
      _preloadLiquidExportSvgForState(exportKey);
      exportPicture = _liquidExportSvgPicture;
    }

    var importPicture = _liquidImportCache[importKey];
    if (importPicture == null) {
      _preloadLiquidImportSvgForState(importKey);
      importPicture = _liquidImportSvgPicture;
    }

    if (basePicture == null ||
        exportPicture == null ||
        importPicture == null) {
      return;
    }

    canvas.save();

    if (tintRed) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter =
                const ColorFilter.mode(Color(0xFFFF4444), BlendMode.srcATop));
    } else if (tintBlue) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity)
            ..colorFilter =
                const ColorFilter.mode(Color(0xFF44AAFF), BlendMode.srcATop));
    } else if (opacity < 1.0) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    // 1. 基础3x3单元（填充整个区域）
    _drawPictureScaled(canvas, basePicture, 0, 0, w, h);

    // 2. 左侧出水口
    _drawPictureScaled(
      canvas,
      exportPicture,
      _liquidExportRelX * w,
      _liquidExportRelY * h,
      _liquidExportRelW * w,
      _liquidExportRelH * h,
    );

    // 3. 右侧进水口
    _drawPictureScaled(
      canvas,
      importPicture,
      _liquidImportRelX * w,
      _liquidImportRelY * h,
      _liquidImportRelW * w,
      _liquidImportRelH * h,
    );

    if (tintRed || tintBlue || opacity < 1.0) {
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
}
