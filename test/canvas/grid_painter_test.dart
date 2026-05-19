import 'package:flutter_test/flutter_test.dart';
import 'package:endfield_aic_planner/canvas/grid_painter.dart';

void main() {
  group('GridPainter', () {
    test('grid is fully opaque at scale >= 0.5', () {
      final painter = GridPainter(
        offsetX: 0,
        offsetY: 0,
        scale: 0.5,
      );

      expect(painter.shouldRepaint(GridPainter(offsetX: 0, offsetY: 0, scale: 0.5)), false);
    });

    test('grid should repaint when scale changes', () {
      final painter1 = GridPainter(offsetX: 0, offsetY: 0, scale: 1.0);
      final painter2 = GridPainter(offsetX: 0, offsetY: 0, scale: 0.5);

      expect(painter1.shouldRepaint(painter2), true);
    });

    test('grid should repaint when offset changes', () {
      final painter1 = GridPainter(offsetX: 0, offsetY: 0, scale: 1.0);
      final painter2 = GridPainter(offsetX: 100, offsetY: 0, scale: 1.0);

      expect(painter1.shouldRepaint(painter2), true);
    });
  });
}
