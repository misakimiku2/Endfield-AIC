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

    test(
        'queued segments preserve stopped downstream items when new source is attached',
        () {
      final belt = ConveyorBelt(
        id: 'queued_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
          Offset(3, 0),
          Offset(4, 0),
          Offset(5, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_b', fillCount: 4, drainCount: 0),
          ConveyorItemSegment(itemId: 'item_a', fillCount: 6, drainCount: 4),
        ],
      );

      expect(belt.itemId, 'item_b');
      expect(belt.lastItemId, 'item_a');

      expect(belt.pushSourceItem('item_c'), false);
      expect(belt.itemSegments.map((s) => s.itemId), ['item_b', 'item_a']);

      belt.itemSegments.first.drainCount = 2;
      expect(belt.pushSourceItem('item_c'), true);
      expect(belt.itemSegments.map((s) => s.itemId), [
        'item_c',
        'item_b',
        'item_a',
      ]);
    });

    test('queued segments stop behind downstream queue on dead-end belts', () {
      final belt = ConveyorBelt(
        id: 'queued_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
          Offset(3, 0),
          Offset(4, 0),
          Offset(5, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_b', fillCount: 3, drainCount: 0),
          ConveyorItemSegment(itemId: 'item_a', fillCount: 6, drainCount: 4),
        ],
      );

      expect(
        belt.advanceItemSegments(isDeadEnd: true, activeSourceItemId: null),
        true,
      );
      expect(belt.itemSegments[0].itemId, 'item_b');
      expect(belt.itemSegments[0].fillCount, 4);
      expect(belt.itemSegments[0].drainCount, 1);

      expect(
        belt.advanceItemSegments(isDeadEnd: true, activeSourceItemId: null),
        false,
      );
      expect(belt.itemSegments.map((s) => s.itemId), ['item_b', 'item_a']);
      expect(belt.itemSegments[0].fillCount, 4);
      expect(belt.itemSegments[0].drainCount, 1);
      expect(belt.itemSegments[1].fillCount, 6);
      expect(belt.itemSegments[1].drainCount, 4);
    });
  });
}
