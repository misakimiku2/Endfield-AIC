import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  static void paintHud(Canvas canvas, Size size, double phase) {
    if (size.width <= 0 || size.height <= 0) return;

    final rail = math.min(16.0, math.max(10.0, size.shortestSide * 0.014));
    final topHeight =
        math.min(44.0, math.max(30.0, size.height * 0.058));
    final sideWidth =
        math.min(40.0, math.max(26.0, size.width * 0.019));
    final sideHeight =
        math.min(size.height * 0.62, size.height - topHeight);
    final s = rail + _gap;
    final gp = phase % 1.0; // global pattern phase

    // ── Solid rails ──────────────────────────────────────────
    _drawSolidRails(canvas, size, rail, sideHeight + topHeight * 0.3);

    // ── Top stripes: `/` , same global phase as left ──────────
    _drawTopStripes(
      canvas,
      Rect.fromLTWH(s, s, size.width - 2 * s, topHeight - s),
      gp,
    );

    // ── Left side stripes: `/` , same global phase ─────────────
    _drawLeftStripes(
      canvas,
      Rect.fromLTWH(s, s, sideWidth, sideHeight),
      gp,
    );

    // ── Right side stripes: `\` , phase aligned at top-right ───
    // Offset so that `\` pattern meets `/` pattern at the corner.
    final cornerX = size.width - s;
    final cornerY = topHeight;
    // At corner: (cx-cy)/s + gp ≡ (cx+cy)/s – rightP + C  ⇒  rightP = 2*cy/s + C
    final rightPhase = (gp + 2.0 * cornerY / _spacing) % 1.0;

    _drawRightStripes(
      canvas,
      Rect.fromLTWH(cornerX - sideWidth, cornerY, sideWidth, sideHeight - (topHeight - s)),
      rightPhase,
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

    // y derived from pattern: y = −rect.left + rp*spacing + k*spacing
    final yBase = -rect.left + rp * _spacing;
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
