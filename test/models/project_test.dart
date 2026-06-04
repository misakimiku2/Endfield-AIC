import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:endfield_aic_planner/models/building.dart';

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
      );

      expect(belt.length, 96.0);
    });

    test('single cell path has zero length', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [const Offset(0, 0)],
      );

      expect(belt.length, 0.0);
    });

    test('maxPosition returns correct value', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, 1),
        ],
      );

      expect(belt.maxPosition, 2.0);
    });

    test('items can be added and accessed', () {
      final belt = ConveyorBelt(
        id: 'test_belt',
        path: [
          const Offset(0, 0),
          const Offset(1, 0),
        ],
        items: [
          ConveyorItem(itemId: 'originium_ore', position: 0.0),
          ConveyorItem(itemId: 'ferrium_ore', position: 0.5),
        ],
      );

      expect(belt.items.length, 2);
      expect(belt.items[0].itemId, 'originium_ore');
      expect(belt.items[1].position, 0.5);
    });
  });

  group('PlacedBuilding', () {
    test('inputInventory and outputInventory are empty by default', () {
      final building = PlacedBuilding(
        id: 'test_building',
        building: Building(
          id: 'test',
          name: 'Test',
          gridWidth: 1,
          gridHeight: 1,
          color: const Color(0xFF000000),
          category: 'test',
          maxInputs: 0,
          maxOutputs: 0,
          ports: const PortsLayout(inputs: [], outputs: []),
        ),
        gridX: 0,
        gridY: 0,
      );

      expect(building.inputInventory.isEmpty, true);
      expect(building.outputInventory.isEmpty, true);
      expect(building.outputItemId, isNull);
    });
  });
}
