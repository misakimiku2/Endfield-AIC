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
  static const Color _softEdge = Color(0x33FFFFFF);
  static const double _gap = 2.0;

  /// Uniform spacing & thickness for all three sides.
  static const double _spacing = 28.0;
  static const double _thickness = 10.0;
  static const double _stripeBand = 32.0;
  static const double _createModuleStripeCount = 3.15;
  static const double _createModuleGapCount = 2.7;

  static PictureInfo? _createTextPicture;
  static bool _initialized = false;
  static bool _initializing = false;

  static Future<void> init({VoidCallback? onReady}) async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      _createTextPicture = await vg.loadPicture(
        const SvgAssetLoader('assets/svg/HUD_create_text.svg'),
        null,
      );
      _initialized = true;
      onReady?.call();
    } catch (e) {
      debugPrint('Failed to load HUD create SVG: $e');
    } finally {
      _initializing = false;
    }
  }

  static void paintHud(Canvas canvas, Size size, double phase) {
    if (size.width <= 0 || size.height <= 0) return;

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
      Paint()..color = _yellow,
    );
    _drawGradientRail(canvas, Rect.fromLTWH(0, 0, rail, sideHeight));
    _drawGradientRail(
      canvas,
      Rect.fromLTWH(size.width - rail, 0, rail, sideHeight),
    );
  }

  static void _drawGradientRail(Canvas canvas, Rect rect) {
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = _yellow);
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
      ..color = _yellow.withValues(alpha: 0.95)
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
      ..color = _yellow.withValues(alpha: 0.9)
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
      ..color = _yellow.withValues(alpha: 0.9)
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
    final picture = _createTextPicture;
    if (picture == null || rect.width <= 0 || rect.height <= 0) return;

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
    final modulePaint = Paint()..color = _yellow;

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
      _drawPictureScaled(canvas, picture, textRect);
    }
  }

  static void _drawPictureScaled(
    Canvas canvas,
    PictureInfo picture,
    Rect targetRect,
  ) {
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
    canvas.drawPicture(picture.picture);
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
