import 'package:flutter_test/flutter_test.dart';
import 'package:endfield_aic_planner/models/project.dart';

void main() {
  group('ConveyorBelt', () {
    test('start and end positions are calculated correctly', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, 1),
        ],
        itemId: '',
      );

      expect(belt.path.length, 3);
      expect(belt.start.dx, 24.0);
      expect(belt.start.dy, 24.0);
      expect(belt.end.dx, 72.0);
      expect(belt.end.dy, 72.0);
    });

    test('length is calculated correctly for L-shaped path', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, 1),
        ],
        itemId: '',
      );

      expect(belt.length, 96.0);
    });

    test('single cell path has zero length', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [const Offset(0, 0)],
        itemId: '',
      );

      expect(belt.length, 0.0);
    });
  });
}
