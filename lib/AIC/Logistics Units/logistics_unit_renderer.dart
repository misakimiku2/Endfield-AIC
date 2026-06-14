import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/building.dart';
import '../../models/recipe.dart';

class LogisticsUnitRenderer {
  static const String beltBridgeId = 'belt_bridge_1x1';
  static const String splitterId = 'splitter_1x1';
  static const String convergerId = 'converger_1x1';
  static const String itemControlPortId = 'item_control_port_1x1';

  static const Set<String> logisticsUnitIds = {
    beltBridgeId,
    splitterId,
    convergerId,
    itemControlPortId,
  };

  static const Map<String, String> _assetPaths = {
    beltBridgeId: 'assets/svg/Belt_Bridge.svg',
    splitterId: 'assets/svg/Splitter.svg',
    convergerId: 'assets/svg/Converger.svg',
    itemControlPortId: 'assets/svg/Item_Control_Port.svg',
  };

  static const Color _fallbackFrameColor = Color(0xFF333333);
  static const Color _fallbackFillColor = Color(0xFF4AA3B5);
  static const Color _blockedOverlayColor = Color(0x40FF0000);

  static final Map<String, PictureInfo> _pictures = {};
  static final Map<String, PictureInfo> _previewPictures = {};
  static bool _initialized = false;
  static bool _initializing = false;
  static int _cacheVersion = 0;

  static bool get isReady =>
      _initialized && _assetPaths.keys.every(_pictures.containsKey);
  static int get cacheVersion => _cacheVersion;

  static bool isLogisticsUnit(String buildingId) =>
      logisticsUnitIds.contains(buildingId);

  static Future<void> init({VoidCallback? onReady}) async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      for (final entry in _assetPaths.entries) {
        final raw = await rootBundle.loadString(entry.value);
        final cleaned = _cleanInkscapeSvg(raw);
        _pictures[entry.key] =
            await vg.loadPicture(SvgStringLoader(cleaned), null);
        final previewCleaned = _makePreviewSvg(cleaned);
        _previewPictures[entry.key] =
            await vg.loadPicture(SvgStringLoader(previewCleaned), null);
      }
      _initialized = true;
      _cacheVersion++;
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load logistics unit SVGs: $e');
    } finally {
      _initializing = false;
    }
  }

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

    final picture = _pictures[building.id];
    if (picture != null) {
      _drawPictureScaled(canvas, picture, 0, 0, w, h);
    } else {
      _drawFallback(canvas, w, h, building.color);
    }

    if (isBlocked) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _blockedOverlayColor,
      );
    }

    canvas.restore();
  }

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
    Color? previewColorOverride,
  }) {
    final x = gridX * cellSize;
    final y = gridY * cellSize;
    final w = building.gridWidth * cellSize;
    final h = building.gridHeight * cellSize;
    final previewColor = previewColorOverride ??
        (isBlocked ? const Color(0xFFFF4444) : const Color(0xFF44AAFF));

    canvas.save();
    canvas.translate(x + w / 2, y + h / 2);
    canvas.rotate(rotation * math.pi / 2);
    canvas.translate(-w / 2, -h / 2);

    final picture = _previewPictures[building.id] ?? _pictures[building.id];
    if (picture != null) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, opacity * 0.6)
          ..colorFilter = ColorFilter.mode(previewColor, BlendMode.srcATop),
      );
      _drawPictureScaled(canvas, picture, 0, 0, w, h);
      canvas.restore();
    } else {
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

  static void _drawPictureScaled(
    Canvas canvas,
    PictureInfo picture,
    double x,
    double y,
    double width,
    double height,
  ) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(width / picture.size.width, height / picture.size.height);
    canvas.drawPicture(picture.picture);
    canvas.restore();
  }

  static void _drawFallback(Canvas canvas, double w, double h, Color color) {
    final fillPaint = Paint()
      ..color = (color == const Color(0x00000000) ? _fallbackFillColor : color)
          .withValues(alpha: 0.2);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fillPaint);

    final framePaint = Paint()
      ..color = _fallbackFrameColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), framePaint);
  }

  static String _cleanInkscapeSvg(String svg) {
    var result = svg;

    // 1. Remove <sodipodi:namedview> blocks (may contain child elements)
    result = result.replaceAll(
      RegExp(r'<sodipodi:namedview[\s\S]*?</sodipodi:namedview>',
          multiLine: true),
      '',
    );

    // 2. Remove <defs> blocks (including content like patterns, path-effects)
    result = result.replaceAll(
      RegExp(r'<defs[\s>][\s\S]*?</defs>', multiLine: true),
      '',
    );

    // 3. Remove <inkscape:path-effect .../> self-closing tags
    result = result.replaceAll(
      RegExp(r'<inkscape:path-effect[\s\S]*?/>', multiLine: true),
      '',
    );

    // 4. Remove <image .../> tags
    result = result.replaceAll(
      RegExp(r'<image[\s\S]*?/>', multiLine: true),
      '',
    );

    // 5. Remove all inkscape: and sodipodi: attributes
    result = result.replaceAll(RegExp(r'\s+inkscape:[a-zA-Z-]+="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+sodipodi:[a-zA-Z-]+="[^"]*"'), '');

    // 6. Remove inkscape/sodipodi namespace declarations
    result = result.replaceAll(RegExp(r'\s+xmlns:inkscape="[^"]*"'), '');
    result = result.replaceAll(RegExp(r'\s+xmlns:sodipodi="[^"]*"'), '');

    // 7. Replace fill:url(#...) pattern/gradient references with solid color
    result = result.replaceAllMapped(
      RegExp(r'fill="url\([^)]*\)"'),
      (m) => 'fill="#555555"',
    );

    // 8. Remove stroke:url(#...) references
    result = result.replaceAllMapped(
      RegExp(r'stroke="url\([^)]*\)"'),
      (m) => 'stroke="none"',
    );

    // 9. Remove xlink namespace (used by pattern references)
    result = result.replaceAll(RegExp(r'\s+xmlns:xlink="[^"]*"'), '');

    return result;
  }

  /// 生成预览用 SVG：将 BG 元素（fill:#e4e4e4）的 fill-opacity 降为 0.2，
  /// 使预览时条纹/边框清晰可见而背景几乎透明。
  static String _makePreviewSvg(String cleanedSvg) {
    return cleanedSvg.replaceAll(
      'fill:#e4e4e4;fill-opacity:1',
      'fill:#e4e4e4;fill-opacity:0.2',
    );
  }
}
