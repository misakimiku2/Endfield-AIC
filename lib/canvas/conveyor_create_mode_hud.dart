import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Screen-space HUD shown while drawing conveyor belts.
///
/// All three sides share a **single global pattern function** so that stripes
/// align seamlessly at every corner — no matter the screen size or phase.
///
///   Left side  → `/` stripes moving UP     pattern: (x – y)/spacing + gp
///   Top        → `/` stripes moving RIGHT   pattern: (x – y)/spacing + gp
///   Right side → `\` stripes moving DOWN    pattern: (x + y)/spacing – gp + c
class ConveyorCreateModeHudPainter {
  static const Color _yellow = Color(0xFFFFC400);
  static const Color _red = Color(0xFFFF3B30);
  static const Color _softEdge = Color(0x33FFFFFF);
  static const double _gap = 5.0;

  /// Uniform spacing & thickness for all three sides.
  static const double _spacing = 28.0;
  static const double _thickness = 10.0;
  static const double _stripeBand = 32.0;
  static const double _createModuleStripeCount = 3.15;
  static const double _createModuleGapCount = 2.7;

  static PictureInfo? _createTextPicture;
  static PictureInfo? _errorTextPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  // ── Error animation state ──────────────────────────────────
  static bool _isError = false;
  static int? _errorStartTimeUs; // microseconds since epoch

  // Error animation timing (microseconds)
  static const int _flashHalfUs = 150000; // 150ms per half-flash
  static const int _holdUs = 400000; // 400ms hold after flash
  static const int _transitionUs = 500000; // 500ms transition back to normal
  // Total flash: 4 half-flashes × 150ms = 600ms
  // Total error: 600 + 400 + 500 = 1500ms

  // Per-frame computed state (set at beginning of paintHud)
  static Color _frameColor = _yellow;
  static double _frameOpacity = 1.0;
  static double _frameSvgBlend = 0.0; // 0.0 = create SVG, 1.0 = error SVG

  static Future<void> init({VoidCallback? onReady}) async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      _createTextPicture = await vg.loadPicture(
        const SvgAssetLoader('assets/svg/HUD_create_text.svg'),
        null,
      );
      _errorTextPicture = await vg.loadPicture(
        const SvgAssetLoader('assets/svg/HUD_error_text.svg'),
        null,
      );
      _initialized = true;
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load HUD SVG: $e');
    } finally {
      _initializing = false;
    }
  }

  /// 触发 HUD 错误动画：闪烁两次后自然恢复
  static void triggerError() {
    _isError = true;
    _errorStartTimeUs = DateTime.now().microsecondsSinceEpoch;
  }

  /// 计算当前帧的错误动画状态，更新 _frameColor / _frameOpacity / _frameSvgBlend
  static void _updateErrorState() {
    if (!_isError || _errorStartTimeUs == null) {
      _frameColor = _yellow;
      _frameOpacity = 1.0;
      _frameSvgBlend = 0.0;
      return;
    }

    final elapsed = DateTime.now().microsecondsSinceEpoch - _errorStartTimeUs!;

    // Phase 1: Flash (4 half-flashes = 600ms)
    const flashTotal = _flashHalfUs * 4;
    if (elapsed < flashTotal) {
      final halfIndex = elapsed ~/ _flashHalfUs;
      final withinHalf = (elapsed % _flashHalfUs) / _flashHalfUs;
      // even half-index → fading out, odd → fading in
      if (halfIndex.isEven) {
        _frameOpacity = 1.0 - withinHalf;
      } else {
        _frameOpacity = withinHalf;
      }
      _frameColor = _red;
      _frameSvgBlend = 1.0;
      return;
    }

    // Phase 2: Hold error (400ms)
    const holdEnd = flashTotal + _holdUs;
    if (elapsed < holdEnd) {
      _frameOpacity = 1.0;
      _frameColor = _red;
      _frameSvgBlend = 1.0;
      return;
    }

    // Phase 3: Transition back to normal (500ms)
    const transitionEnd = holdEnd + _transitionUs;
    if (elapsed < transitionEnd) {
      final t = (elapsed - holdEnd) / _transitionUs;
      _frameOpacity = 1.0;
      _frameColor = Color.lerp(_red, _yellow, t)!;
      _frameSvgBlend = 1.0 - t;
      return;
    }

    // Animation complete
    _isError = false;
    _errorStartTimeUs = null;
    _frameColor = _yellow;
    _frameOpacity = 1.0;
    _frameSvgBlend = 0.0;
  }

  static void paintHud(Canvas canvas, Size size, double phase) {
    if (size.width <= 0 || size.height <= 0) return;

    _updateErrorState();

    // Apply flash opacity via saveLayer
    final needOpacityLayer = _frameOpacity < 1.0;
    if (needOpacityLayer) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color.fromRGBO(255, 255, 255, _frameOpacity),
      );
    }

    final rail = math.min(16.0, math.max(10.0, size.shortestSide * 0.014));
    final topHeight = rail + _gap + _stripeBand;
    const sideWidth = _stripeBand;
    final sideHeight = math.min(size.height * 0.62, size.height - topHeight);
    final s = rail + _gap;
    final sideStripeTop = topHeight;
    final sideStripeHeight = math.max(0.0, sideHeight - (topHeight - s));
    final topStripeRect = Rect.fromLTWH(s, s, size.width - 2 * s, _stripeBand);
    final leftStripeRect =
        Rect.fromLTWH(s, sideStripeTop, sideWidth, sideStripeHeight);
    final gp = phase % 1.0; // global pattern phase
    final leftPhase = (gp + _thickness / _spacing) % 1.0;

    // ── Solid rails ──────────────────────────────────────────
    _drawSolidRails(canvas, size, rail, sideHeight + topHeight * 0.3);

    // ── Top stripes: `/` , same global phase as left ──────────
    _drawTopStripes(
      canvas,
      topStripeRect,
      gp,
    );

    // ── Left side stripes: `/` , same global phase ─────────────
    _drawLeftStripes(
      canvas,
      leftStripeRect,
      leftPhase,
    );

    // ── Right side stripes: `\` , phase aligned at top-right ───
    // Offset so that `\` pattern meets `/` pattern at the corner.
    final cornerX = size.width - s;
    final cornerY = topHeight;
    final rightStripeRect = Rect.fromLTWH(
        cornerX - sideWidth, cornerY, sideWidth, sideStripeHeight);
    // At corner: (cx-cy)/s + gp ≡ (cx+cy)/s – rightP + C  ⇒  rightP = 2*cy/s + C
    final rightPhase = (gp + 2.0 * cornerY / _spacing) % 1.0;

    _drawRightStripes(
      canvas,
      rightStripeRect,
      rightPhase,
    );

    _drawCreateModules(
      canvas,
      topStripeRect,
      Rect.fromLTWH(s, s, sideWidth, sideHeight),
      Rect.fromLTWH(cornerX - sideWidth, s, sideWidth, sideHeight),
      phase,
    );

    if (needOpacityLayer) {
      canvas.restore();
    }
  }

  // ════════════════════════════════════════════════════════════
  // Solid rails
  // ════════════════════════════════════════════════════════════

  static void _drawSolidRails(
    Canvas canvas,
    Size size,
    double rail,
    double sideHeight,
  ) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, rail),
      Paint()..color = _frameColor,
    );
    _drawGradientRail(canvas, Rect.fromLTWH(0, 0, rail, sideHeight));
    _drawGradientRail(
      canvas,
      Rect.fromLTWH(size.width - rail, 0, rail, sideHeight),
    );
  }

  static void _drawGradientRail(Canvas canvas, Rect rect) {
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = _frameColor);
    final maskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        const [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawRect(rect, maskPaint);
    canvas.restore();
  }

  // ════════════════════════════════════════════════════════════
  // Top stripes: `/` direction, moving RIGHT
  //
  // Pattern: (x − y) / spacing + gp
  // At y = rect.top → x = rect.top − spacing·(k − gp)
  // As gp increases, x_start increases → stripes shift RIGHT ✓
  // ════════════════════════════════════════════════════════════

  static void _drawTopStripes(Canvas canvas, Rect rect, double gp) {
    canvas.save();
    canvas.clipRect(rect);

    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 2),
      Paint()..color = _softEdge,
    );

    // x derived from pattern: x = rect.top + gp*spacing − k*spacing
    final xBase = rect.top + gp * _spacing;
    final paint = Paint()
      ..color = _frameColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    for (double x = xBase - _spacing * 2;
        x < rect.right + _spacing * 2;
        x += _spacing) {
      final path = Path()
        ..moveTo(x, rect.top)
        ..lineTo(x + _thickness, rect.top)
        ..lineTo(x + _thickness + rect.height, rect.bottom)
        ..lineTo(x + rect.height, rect.bottom)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  // ════════════════════════════════════════════════════════════
  // Left side stripes: `/` direction, moving UP
  //
  // Pattern: (x − y) / spacing + gp
  // At x = rect.left → y = rect.left − spacing·(k − gp)
  // As gp increases, y_base decreases → stripes shift UP ✓
  // ════════════════════════════════════════════════════════════

  static void _drawLeftStripes(Canvas canvas, Rect rect, double gp) {
    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);

    // y derived from pattern: y = rect.left − gp*spacing + k*spacing
    final yBase = rect.left - gp * _spacing;
    final paint = Paint()
      ..color = _frameColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    for (double y = yBase - _spacing * 2;
        y < rect.bottom + _spacing * 2;
        y += _spacing) {
      final path = Path()
        ..moveTo(rect.left, y)
        ..lineTo(rect.right, y + rect.width)
        ..lineTo(rect.right, y + rect.width + _thickness)
        ..lineTo(rect.left, y + _thickness)
        ..close();
      canvas.drawPath(path, paint);
    }

    _applyVerticalFade(canvas, rect);
    canvas.restore();
  }

  // ════════════════════════════════════════════════════════════
  // Right side stripes: `\` direction, moving DOWN
  //
  // Pattern: (x + y) / spacing − rp   (rp = right-side phase)
  // At x = rect.left → y = −rect.left + spacing·(k + rp)
  // As rp increases, y_base increases → stripes shift DOWN ✓
  // ════════════════════════════════════════════════════════════

  static void _drawRightStripes(Canvas canvas, Rect rect, double rp) {
    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);

    // Mirror the right edge so the top-right corner reads like one
    // clockwise turn instead of two overlapping stripe fields.
    final yBase = -rect.right + rp * _spacing;
    final paint = Paint()
      ..color = _frameColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    for (double y = yBase - _spacing * 2;
        y < rect.bottom + _spacing * 2;
        y += _spacing) {
      final path = Path()
        ..moveTo(rect.right, y)
        ..lineTo(rect.left, y + rect.width)
        ..lineTo(rect.left, y + rect.width + _thickness)
        ..lineTo(rect.right, y + _thickness)
        ..close();
      canvas.drawPath(path, paint);
    }

    _applyVerticalFade(canvas, rect);
    canvas.restore();
  }

  // ════════════════════════════════════════════════════════════

  static void _drawCreateModules(
    Canvas canvas,
    Rect topRect,
    Rect leftRect,
    Rect rightRect,
    double phase,
  ) {
    _drawTopCreateModules(canvas, topRect, phase);
    _drawSideCreateModules(
      canvas,
      leftRect,
      phase,
      reverse: true,
      mirrorShape: true,
    );
    _drawSideCreateModules(canvas, rightRect, phase, reverse: false);
  }

  static void _drawTopCreateModules(Canvas canvas, Rect rect, double gp) {
    canvas.save();
    canvas.clipPath(_topCreateAreaPath(rect));
    _drawHorizontalCreateModules(canvas, rect, gp);
    canvas.restore();
  }

  static void _drawSideCreateModules(
    Canvas canvas,
    Rect rect,
    double phase, {
    required bool reverse,
    bool mirrorShape = false,
  }) {
    canvas.saveLayer(rect, Paint());
    canvas.clipPath(
      reverse ? _leftCreateAreaPath(rect) : _rightCreateAreaPath(rect),
    );
    canvas.save();
    canvas.translate(rect.right, rect.top);
    canvas.rotate(math.pi / 2);
    _drawHorizontalCreateModules(
      canvas,
      Rect.fromLTWH(0, 0, rect.height, rect.width),
      phase,
      reverse: reverse,
      mirrorShape: mirrorShape,
    );
    canvas.restore();
    _applyVerticalFade(canvas, rect);
    canvas.restore();
  }

  static Path _topCreateAreaPath(Rect rect) {
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - rect.height, rect.bottom)
      ..lineTo(rect.left + rect.height, rect.bottom)
      ..close();
  }

  static Path _leftCreateAreaPath(Rect rect) {
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top + rect.width)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
  }

  static Path _rightCreateAreaPath(Rect rect) {
    return Path()
      ..moveTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + rect.width)
      ..close();
  }

  static void _drawHorizontalCreateModules(
    Canvas canvas,
    Rect rect,
    double phase, {
    bool reverse = false,
    bool mirrorShape = false,
  }) {
    if (rect.width <= 0 || rect.height <= 0) return;

    final moduleWidth = math.max(
      _spacing * _createModuleStripeCount,
      rect.height * 3.6,
    );
    final visualModuleWidth = moduleWidth + rect.height;
    const moduleGap = _spacing * _createModuleGapCount;
    final modulePeriod = visualModuleWidth + moduleGap;
    final travel = phase * _spacing * (reverse ? -1.0 : 1.0);
    final wrappedTravel =
        travel - (travel / modulePeriod).floor() * modulePeriod;
    final xBase = rect.left + wrappedTravel;
    final modulePaint = Paint()..color = _frameColor;

    for (double x = xBase - modulePeriod * 2;
        x < rect.right + modulePeriod * 2;
        x += modulePeriod) {
      final path = mirrorShape
          ? (Path()
            ..moveTo(x + rect.height, rect.top)
            ..lineTo(x + rect.height + moduleWidth, rect.top)
            ..lineTo(x + moduleWidth, rect.bottom)
            ..lineTo(x, rect.bottom)
            ..close())
          : (Path()
            ..moveTo(x, rect.top)
            ..lineTo(x + moduleWidth, rect.top)
            ..lineTo(x + moduleWidth + rect.height, rect.bottom)
            ..lineTo(x + rect.height, rect.bottom)
            ..close());
      canvas.drawPath(path, modulePaint);

      final visualRect = Rect.fromLTWH(
        x,
        rect.top,
        visualModuleWidth,
        rect.height,
      );
      final textRect = Rect.fromLTWH(
        visualRect.left + visualRect.width * 0.18,
        visualRect.top + visualRect.height * 0.13,
        visualRect.width * 0.64,
        visualRect.height * 0.74,
      );

      // 根据 _frameSvgBlend 绘制 SVG（支持交叉淡入淡出）
      final blend = _frameSvgBlend;
      if (blend > 0.0 && _errorTextPicture != null) {
        _drawPictureScaled(
          canvas,
          _errorTextPicture!,
          textRect,
          tintColor: const Color(0xFFFFFFFF),
          opacity: blend,
        );
      }
      if (blend < 1.0 && _createTextPicture != null) {
        _drawPictureScaled(
          canvas,
          _createTextPicture!,
          textRect,
          opacity: 1.0 - blend,
        );
      }
    }
  }

  static void _drawPictureScaled(
    Canvas canvas,
    PictureInfo picture,
    Rect targetRect, {
    Color? tintColor,
    double opacity = 1.0,
  }) {
    if (targetRect.width <= 0 || targetRect.height <= 0) return;

    final pictureSize = picture.size;
    if (pictureSize.width <= 0 || pictureSize.height <= 0) return;

    final scale = math.min(
      targetRect.width / pictureSize.width,
      targetRect.height / pictureSize.height,
    );
    final dx =
        targetRect.left + (targetRect.width - pictureSize.width * scale) / 2;
    final dy =
        targetRect.top + (targetRect.height - pictureSize.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final needsLayer = tintColor != null || opacity < 1.0;
    if (needsLayer) {
      final bounds =
          Rect.fromLTWH(0, 0, pictureSize.width, pictureSize.height);
      final layerPaint = Paint();
      if (opacity < 1.0) {
        layerPaint.color = Color.fromRGBO(255, 255, 255, opacity);
      }
      canvas.saveLayer(bounds, layerPaint);
      canvas.drawPicture(picture.picture);
      if (tintColor != null) {
        canvas.drawRect(
          bounds,
          Paint()
            ..color = tintColor
            ..blendMode = BlendMode.srcIn,
        );
      }
      canvas.restore();
    } else {
      canvas.drawPicture(picture.picture);
    }

    canvas.restore();
  }

  static void _applyVerticalFade(Canvas canvas, Rect rect) {
    final maskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        const [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawRect(rect, maskPaint);
  }
}
