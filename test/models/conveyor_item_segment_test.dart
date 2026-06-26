import 'package:flutter_test/flutter_test.dart';
import 'package:endfield_aic_planner/models/project.dart';

void main() {
  group('ConveyorItemSegment.hasItems', () {
    test('true when itemId present and fillCount > drainCount', () {
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 3, drainCount: 1);
      expect(seg.hasItems, isTrue);
    });

    test('false when fillCount equals drainCount', () {
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 2, drainCount: 2);
      expect(seg.hasItems, isFalse);
    });

    test('false when itemId is empty', () {
      final seg = ConveyorItemSegment(itemId: '', fillCount: 3, drainCount: 0);
      expect(seg.hasItems, isFalse);
    });
  });

  group('ConveyorItemSegment.copyWith', () {
    test('copies all fields when all provided', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 2,
        drainCount: 1,
        freezeProgress: 0.5,
        skipAdvanceOnce: true,
      );
      final copy = seg.copyWith(
        itemId: 'item_b',
        fillCount: 5,
        drainCount: 3,
        freezeProgress: 0.8,
        skipAdvanceOnce: false,
      );
      expect(copy.itemId, 'item_b');
      expect(copy.fillCount, 5);
      expect(copy.drainCount, 3);
      expect(copy.freezeProgress, 0.8);
      expect(copy.skipAdvanceOnce, isFalse);
    });

    test('keeps original fields when none provided', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 2,
        drainCount: 1,
        freezeProgress: 0.5,
      );
      final copy = seg.copyWith();
      expect(copy.itemId, 'item_a');
      expect(copy.fillCount, 2);
      expect(copy.drainCount, 1);
      expect(copy.freezeProgress, 0.5);
      // 不修改原对象
      expect(identical(seg, copy), isFalse);
    });
  });

  group('ConveyorItemSegment.shifted', () {
    test('shifts fillCount and drainCount by offset', () {
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 4, drainCount: 1);
      final shifted = seg.shifted(2);
      expect(shifted.fillCount, 6);
      expect(shifted.drainCount, 3);
    });

    test('keeps freezeProgress by default', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 4,
        freezeProgress: 0.5,
      );
      expect(seg.shifted(1).freezeProgress, 0.5);
    });

    test('clears freezeProgress when requested', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 4,
        freezeProgress: 0.5,
      );
      expect(seg.shifted(1, clearFreezeProgress: true).freezeProgress, isNull);
    });
  });

  group('ConveyorItemSegment.clipped', () {
    test('clips to window and rebases by start', () {
      // fillCount=8 超过 end=6，触发 min 分支：newFill=min(8,6)=6
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 8, drainCount: 1);
      final clipped = seg.clipped(2, 6);
      // newFill = min(8,6)=6, newDrain = max(1,2)=2; rebase by start=2 → fill 4, drain 0
      expect(clipped, isNotNull);
      expect(clipped!.fillCount, 4);
      expect(clipped.drainCount, 0);
    });

    test('returns null when nothing remains after clip (newFill == newDrain)', () {
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 3, drainCount: 3);
      // newFill=3, newDrain=3 → newFill <= newDrain → null
      expect(seg.clipped(0, 5), isNull);
    });

    test('returns null when window is entirely before segment', () {
      final seg = ConveyorItemSegment(itemId: 'item_a', fillCount: 5, drainCount: 2);
      // newFill=min(5,1)=1, newDrain=max(2,0)=2 → 1<=2 → null
      expect(seg.clipped(0, 1), isNull);
    });

    test('keeps freezeProgress when length positive and not cleared', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 5,
        drainCount: 1,
        freezeProgress: 0.5,
      );
      expect(seg.clipped(0, 4)!.freezeProgress, 0.5);
    });

    test('clears freezeProgress when explicitly requested', () {
      final seg = ConveyorItemSegment(
        itemId: 'item_a',
        fillCount: 5,
        drainCount: 1,
        freezeProgress: 0.5,
      );
      expect(seg.clipped(0, 4, clearFreezeProgress: true)!.freezeProgress, isNull);
    });
  });
}
