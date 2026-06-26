import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:endfield_aic_planner/AIC/Logistics Units/transport_belt.dart';
import 'package:endfield_aic_planner/models/building.dart';
import 'package:endfield_aic_planner/models/project.dart';

void main() {
  const testBuilding = Building(
    id: 'test_processor',
    name: 'Test Processor',
    gridWidth: 1,
    gridHeight: 1,
    color: Colors.orange,
    category: 'test',
    maxInputs: 1,
    maxOutputs: 1,
    ports: PortsLayout(
      inputs: [
        PortDefinition(relativeX: 0.5, relativeY: 1.0, direction: 'down'),
      ],
      outputs: [
        PortDefinition(relativeX: 0.5, relativeY: 0.0, direction: 'up'),
      ],
    ),
  );

  const testBeltBridge = Building(
    id: 'belt_bridge_1x1',
    name: 'Belt Bridge',
    gridWidth: 1,
    gridHeight: 1,
    color: Colors.blue,
    category: 'logistics_units',
    maxInputs: 4,
    maxOutputs: 4,
    ports: PortsLayout(
      inputs: [
        PortDefinition(relativeX: 0.5, relativeY: 0.0, direction: 'up'),
        PortDefinition(relativeX: 0.5, relativeY: 1.0, direction: 'down'),
        PortDefinition(relativeX: 0.0, relativeY: 0.5, direction: 'left'),
        PortDefinition(relativeX: 1.0, relativeY: 0.5, direction: 'right'),
      ],
      outputs: [
        PortDefinition(relativeX: 0.5, relativeY: 0.0, direction: 'up'),
        PortDefinition(relativeX: 0.5, relativeY: 1.0, direction: 'down'),
        PortDefinition(relativeX: 0.0, relativeY: 0.5, direction: 'left'),
        PortDefinition(relativeX: 1.0, relativeY: 0.5, direction: 'right'),
      ],
    ),
  );

  const testSplitter = Building(
    id: 'splitter_1x1',
    name: 'Splitter',
    gridWidth: 1,
    gridHeight: 1,
    color: Colors.green,
    category: 'logistics_units',
    maxInputs: 1,
    maxOutputs: 3,
    ports: PortsLayout(
      inputs: [
        PortDefinition(relativeX: 0.5, relativeY: 0.0, direction: 'up'),
      ],
      outputs: [
        PortDefinition(relativeX: 0.0, relativeY: 0.5, direction: 'left'),
        PortDefinition(relativeX: 0.5, relativeY: 1.0, direction: 'down'),
        PortDefinition(relativeX: 1.0, relativeY: 0.5, direction: 'right'),
      ],
    ),
  );

  const testConverger = Building(
    id: 'converger_1x1',
    name: 'Converger',
    gridWidth: 1,
    gridHeight: 1,
    color: Colors.purple,
    category: 'logistics_units',
    maxInputs: 3,
    maxOutputs: 1,
    ports: PortsLayout(
      inputs: [
        PortDefinition(relativeX: 0.0, relativeY: 0.5, direction: 'left'),
        PortDefinition(relativeX: 0.5, relativeY: 0.0, direction: 'up'),
        PortDefinition(relativeX: 1.0, relativeY: 0.5, direction: 'right'),
      ],
      outputs: [
        PortDefinition(relativeX: 0.5, relativeY: 1.0, direction: 'down'),
      ],
    ),
  );

  group('PlacedBuilding input inventory', () {
    test('accepts only one item type up to 50 items', () {
      final building = PlacedBuilding(
        id: 'processor',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
      );

      for (int i = 0; i < PlacedBuilding.maxInputItemCount; i++) {
        expect(building.acceptInputItem('item_a'), true);
      }

      expect(building.inputItemId, 'item_a');
      expect(building.inputItemCount, 50);
      expect(building.acceptInputItem('item_a'), false);
      expect(building.acceptInputItem('item_b'), false);
    });

    test('consumes input items and clears the slot when empty', () {
      final building = PlacedBuilding(
        id: 'processor',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
        inputItemId: 'item_a',
        inputItemCount: 2,
      );

      expect(building.consumeInputItems('item_a', 1), true);
      expect(building.inputItemId, 'item_a');
      expect(building.inputItemCount, 1);

      expect(building.consumeInputItems('item_a', 1), true);
      expect(building.inputItemId, isNull);
      expect(building.inputItemCount, 0);
    });

    test('input port disconnects when only the port cell remains after split',
        () {
      const threeByThreeProcessor = Building(
        id: 'three_by_three_processor',
        name: 'Three By Three Processor',
        gridWidth: 3,
        gridHeight: 3,
        color: Colors.orange,
        category: 'test',
        maxInputs: 1,
        maxOutputs: 1,
        ports: PortsLayout(
          inputs: [
            PortDefinition(relativeX: 0.833, relativeY: 1.0, direction: 'down'),
          ],
          outputs: [
            PortDefinition(relativeX: 0.833, relativeY: 0.0, direction: 'up'),
          ],
        ),
      );
      final building = PlacedBuilding(
        id: 'processor',
        building: threeByThreeProcessor,
        gridX: 0,
        gridY: 0,
      );

      final connectedBelt = ConveyorBelt(
        id: 'connected_belt',
        path: const [
          Offset(2, 3),
          Offset(2, 2),
        ],
        itemId: '',
      );

      expect(
        building.conveyorPortConnections([connectedBelt])['input_0'],
        true,
      );

      final portCellRemainder = ConveyorBelt(
        id: 'port_cell_remainder',
        path: const [Offset(2, 2)],
        itemId: '',
        forcedDirection: 'up',
      );
      final upstreamRemainder = ConveyorBelt(
        id: 'upstream_remainder',
        path: const [Offset(2, 3)],
        itemId: '',
        forcedDirection: 'up',
      );

      expect(
        building.conveyorPortConnections(
          [portCellRemainder, upstreamRemainder],
        )['input_0'],
        isNull,
      );
    });

    test('output port requires a conveyor start cell to be connected', () {
      const threeByThreeProcessor = Building(
        id: 'three_by_three_processor',
        name: 'Three By Three Processor',
        gridWidth: 3,
        gridHeight: 3,
        color: Colors.orange,
        category: 'test',
        maxInputs: 1,
        maxOutputs: 1,
        ports: PortsLayout(
          inputs: [
            PortDefinition(relativeX: 0.833, relativeY: 1.0, direction: 'down'),
          ],
          outputs: [
            PortDefinition(relativeX: 0.833, relativeY: 0.0, direction: 'up'),
          ],
        ),
      );
      final building = PlacedBuilding(
        id: 'processor',
        building: threeByThreeProcessor,
        gridX: 0,
        gridY: 0,
      );

      final connectedBelt = ConveyorBelt(
        id: 'output_belt',
        path: const [
          Offset(2, 0),
          Offset(2, -1),
        ],
        itemId: '',
      );
      final endingAtOutput = ConveyorBelt(
        id: 'ending_at_output',
        path: const [
          Offset(2, -1),
          Offset(2, 0),
        ],
        itemId: '',
      );

      expect(
        building.conveyorPortConnections([connectedBelt])['output_0'],
        true,
      );
      expect(
        building.conveyorPortConnections([endingAtOutput])['output_0'],
        isNull,
      );
    });

    test('belt bridge keeps each output direction in an independent lane', () {
      final bridge = PlacedBuilding(
        id: 'bridge',
        building: testBeltBridge,
        gridX: 0,
        gridY: 0,
      );

      expect(bridge.acceptBridgeInputItem('item_up', 'up'), true);
      expect(bridge.acceptBridgeInputItem('item_right', 'right'), true);

      expect(bridge.bridgeItemIdForOutputDirection('up'), 'item_up');
      expect(bridge.bridgeItemIdForOutputDirection('right'), 'item_right');
      expect(bridge.bridgeItemIdForOutputDirection('down'), isNull);

      expect(bridge.consumeBridgeOutputItem('item_up', 'right'), false);
      expect(bridge.consumeBridgeOutputItem('item_up', 'up'), true);
      expect(bridge.bridgeItemIdForOutputDirection('up'), isNull);
      expect(bridge.bridgeItemIdForOutputDirection('right'), 'item_right');
    });
  });

  group('PlacedBuilding output inventory', () {
    test('addOutputItem accumulates counts per item', () {
      final pb = PlacedBuilding(
        id: 'p',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
      );
      expect(pb.totalOutputCount, 0);
      pb.addOutputItem('item_a', 3);
      pb.addOutputItem('item_a', 2);
      pb.addOutputItem('item_b', 1);
      expect(pb.totalOutputCount, 6);
      expect(pb.outputItems['item_a'], 5);
      expect(pb.outputItems['item_b'], 1);
    });

    test('canAcceptOutputItem respects the 50-item cap', () {
      final pb = PlacedBuilding(
        id: 'p',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
        outputItems: {'item_a': 49},
      );
      expect(pb.canAcceptOutputItem('item_a'), isTrue);
      pb.addOutputItem('item_a', 1);
      expect(pb.canAcceptOutputItem('item_a'), isFalse);
    });

    test('consumeOutputItem decrements and clears when reaching zero', () {
      final pb = PlacedBuilding(
        id: 'p',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
        outputItems: {'item_a': 2},
      );
      expect(pb.hasOutputItem('item_a'), isTrue);
      expect(pb.consumeOutputItem('item_a', 1), isTrue);
      expect(pb.outputItems['item_a'], 1);
      expect(pb.consumeOutputItem('item_a', 1), isTrue);
      // 全部消耗后键被移除
      expect(pb.outputItems.containsKey('item_a'), isFalse);
      expect(pb.hasOutputItem('item_a'), isFalse);
    });

    test('consumeOutputItem returns false when item absent', () {
      final pb = PlacedBuilding(
        id: 'p',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
      );
      expect(pb.consumeOutputItem('item_a', 1), isFalse);
    });
  });

  group('PlacedBuilding splitter buffer', () {
    PlacedBuilding makeSplitter() => PlacedBuilding(
          id: 's',
          building: testSplitter,
          gridX: 0,
          gridY: 0,
        );

    test('acceptIntoBuffer fills the slot and reports occupation', () {
      final s = makeSplitter();
      expect(s.splitterBufferOccupied, isFalse);
      expect(s.acceptIntoBuffer('item_iron', 'left'), isTrue);
      expect(s.splitterBufferOccupied, isTrue);
      expect(s.splitterBufferedItemId, 'item_iron');
      expect(s.splitterBufferedDirection, 'left');
    });

    test('acceptIntoBuffer rejects when slot already occupied', () {
      final s = makeSplitter();
      expect(s.acceptIntoBuffer('item_iron', 'left'), isTrue);
      // 槽位已满，第二次放入失败，原物品不变
      expect(s.acceptIntoBuffer('item_copper', 'right'), isFalse);
      expect(s.splitterBufferedItemId, 'item_iron');
    });

    test('consumeFromBuffer empties the slot', () {
      final s = makeSplitter();
      s.acceptIntoBuffer('item_iron', 'left');
      s.consumeFromBuffer();
      expect(s.splitterBufferOccupied, isFalse);
      expect(s.splitterBufferedItemId, isNull);
      expect(s.splitterBufferedDirection, isNull);
    });

    test('non-splitter building ignores buffer operations', () {
      final pb = PlacedBuilding(
        id: 'p',
        building: testBuilding,
        gridX: 0,
        gridY: 0,
      );
      expect(pb.acceptIntoBuffer('item_iron', 'left'), isFalse);
      expect(pb.splitterBufferOccupied, isFalse);
      // consumeFromBuffer 在非分流器上为空操作，不应抛异常
      pb.consumeFromBuffer();
    });
  });

  group('PlacedBuilding type predicates and geometry', () {
    test('isSplitter / isConverger / isBeltBridge by building id', () {
      final splitter = PlacedBuilding(
          id: 's', building: testSplitter, gridX: 0, gridY: 0);
      final converger = PlacedBuilding(
          id: 'c', building: testConverger, gridX: 0, gridY: 0);
      final bridge = PlacedBuilding(
          id: 'b', building: testBeltBridge, gridX: 0, gridY: 0);
      final processor = PlacedBuilding(
          id: 'p', building: testBuilding, gridX: 0, gridY: 0);
      expect(splitter.isSplitter, isTrue);
      expect(converger.isConverger, isTrue);
      expect(bridge.isBeltBridge, isTrue);
      // 非物流设备这三个谓词都应为 false
      expect(processor.isSplitter, isFalse);
      expect(processor.isConverger, isFalse);
      expect(processor.isBeltBridge, isFalse);
    });

    test('overlaps detects overlapping bounds', () {
      const cellSize = 48.0;
      final a = PlacedBuilding(
          id: 'a', building: testBuilding, gridX: 0, gridY: 0);
      // 同位置 → 重叠
      expect(a.overlaps(a.getBounds(cellSize), cellSize), isTrue);
      // 移开一格 → 不重叠
      final b = PlacedBuilding(
          id: 'b', building: testBuilding, gridX: 1, gridY: 0);
      expect(a.overlaps(b.getBounds(cellSize), cellSize), isFalse);
    });
  });

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

    test('constructor copies immutable item segment lists before sorting', () {
      final belt = ConveyorBelt(
        id: 'immutable_segments_belt',
        path: const [Offset(0, 0), Offset(1, 0)],
        itemId: '',
        itemSegments: const [],
      );

      belt.ensureItemSegmentsFromLegacy();

      expect(belt.itemSegments, isEmpty);
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

    test('queued segments stop before a blocked terminal limit', () {
      final belt = ConveyorBelt(
        id: 'blocked_input_belt',
        path: const [
          Offset(0, 1),
          Offset(0, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_b', fillCount: 1, drainCount: 0),
        ],
      );

      expect(
        belt.advanceItemSegments(
          isDeadEnd: true,
          activeSourceItemId: null,
          terminalLimit: 1,
        ),
        false,
      );
      expect(belt.itemSegments.single.fillCount, 1);
      expect(belt.itemSegments.single.drainCount, 0);
      expect(belt.outputReadyItemId(), isNull);
    });

    test('clipped segments include item on fork cell for new belt ownership',
        () {
      final belt = ConveyorBelt(
        id: 'forked_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
          Offset(3, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 2, drainCount: 1),
          ConveyorItemSegment(itemId: 'item_b', fillCount: 4, drainCount: 3),
        ],
      );

      final newBeltSegments = belt.clippedItemSegments(0, 2);
      final downstreamSegments = belt.clippedItemSegments(2, belt.path.length);

      expect(newBeltSegments.map((s) => s.itemId), ['item_a']);
      expect(newBeltSegments.single.fillCount, 2);
      expect(newBeltSegments.single.drainCount, 1);

      expect(downstreamSegments.map((s) => s.itemId), ['item_b']);
      expect(downstreamSegments.single.fillCount, 2);
      expect(downstreamSegments.single.drainCount, 1);
    });

    test('clipped segments can clear stale freeze when reassigned', () {
      final belt = ConveyorBelt(
        id: 'stopped_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(
            itemId: 'item_a',
            fillCount: 3,
            drainCount: 0,
            freezeProgress: 0.5,
          ),
        ],
      );

      final reassignedSegments = belt.clippedItemSegments(
        0,
        2,
        clearFreezeProgress: true,
      );

      expect(reassignedSegments.single.freezeProgress, isNull);
    });

    test('a frozen source stack rejects new items until unfrozen', () {
      final belt = ConveyorBelt(
        id: 'extended_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(
            itemId: 'item_a',
            fillCount: 1,
            drainCount: 0,
            freezeProgress: 0.5,
          ),
        ],
      );

      // 冻结段（freezeProgress 非 null 且非哨兵 -3.0）不能接收新物品。
      expect(belt.pushSourceItem('item_a'), false);
      expect(belt.itemSegments.single.fillCount, 1);
      expect(belt.itemSegments.single.freezeProgress, 0.5);

      // 解除冻结后才能继续压入。
      belt.itemSegments.single.freezeProgress = null;
      expect(belt.pushSourceItem('item_a'), true);
      expect(belt.itemSegments.single.fillCount, 2);
      expect(belt.itemSegments.single.freezeProgress, isNull);
    });

    test('removes one ready output item while preserving queued items', () {
      final belt = ConveyorBelt(
        id: 'queued_belt',
        path: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
        ],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_b', fillCount: 2, drainCount: 0),
          ConveyorItemSegment(itemId: 'item_a', fillCount: 3, drainCount: 2),
        ],
      );

      expect(belt.outputReadyItemId(), 'item_a');
      expect(belt.removeOutputReadyItem(), true);
      expect(belt.itemSegments.map((s) => s.itemId), ['item_b']);
      expect(belt.itemSegments.single.fillCount, 2);
      expect(belt.itemSegments.single.drainCount, 0);
    });

    test('animationProgress subtracts phase offset and wraps modulo 1', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0)],
        itemId: '',
        phaseOffset: 0.25,
      );
      expect(belt.animationProgress(0.25), closeTo(0.0, 1e-9));
      expect(belt.animationProgress(0.5), closeTo(0.25, 1e-9));
      // 跨越一周后回绕
      expect(belt.animationProgress(1.25), closeTo(0.0, 1e-9));
    });

    test('canAcceptNewItemFromStart rejects when belt is full', () {
      // 长度 3 的带子，单段已填满到末端 → 不可再接收
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0), Offset(2, 0)],
        itemId: 'item_a',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 3, drainCount: 0),
        ],
      );
      expect(belt.canAcceptNewItemFromStart('item_a'), isFalse);
    });

    test('canAcceptNewItemFromStart accepts same item with room left', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0), Offset(2, 0)],
        itemId: 'item_a',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 1, drainCount: 0),
        ],
      );
      expect(belt.canAcceptNewItemFromStart('item_a'), isTrue);
    });

    test('canAcceptNewItemFromStart rejects when first segment is frozen', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0), Offset(2, 0)],
        itemId: 'item_a',
        itemSegments: [
          ConveyorItemSegment(
            itemId: 'item_a',
            fillCount: 1,
            drainCount: 0,
            freezeProgress: 0.5,
          ),
        ],
      );
      // 冻结段不能接收新物品（与 pushSourceItem 语义一致）
      expect(belt.canAcceptNewItemFromStart('item_a'), isFalse);
    });

    test('canAcceptNewItemFromStart accepts on empty belt', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0)],
        itemId: '',
      );
      expect(belt.canAcceptNewItemFromStart('item_a'), isTrue);
    });

    test('shiftedItemSegments drops empty segments after shift', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0), Offset(2, 0)],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 2, drainCount: 1),
          ConveyorItemSegment(itemId: 'item_b', fillCount: 1, drainCount: 1),
        ],
      );
      // item_b: fill 1, drain 1 → 无物品，平移后应被剔除
      final shifted = belt.shiftedItemSegments(0);
      expect(shifted.length, 1);
      expect(shifted.single.itemId, 'item_a');
    });

    test('downstreamItemId returns the last segment item id', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0), Offset(2, 0)],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 1, drainCount: 0),
          ConveyorItemSegment(itemId: 'item_b', fillCount: 3, drainCount: 2),
        ],
      );
      expect(belt.downstreamItemId(), 'item_b');
    });

    test('downstreamItemId returns null when no segments have items', () {
      final belt = ConveyorBelt(
        id: 'b',
        path: const [Offset(0, 0), Offset(1, 0)],
        itemId: '',
        itemSegments: [
          ConveyorItemSegment(itemId: 'item_a', fillCount: 1, drainCount: 1),
        ],
      );
      expect(belt.downstreamItemId(), isNull);
    });
  });

  group('TransportBeltController', () {
    test('split creation removes dangling input port stub', () {
      const threeByThreeProcessor = Building(
        id: 'three_by_three_processor',
        name: 'Three By Three Processor',
        gridWidth: 3,
        gridHeight: 3,
        color: Colors.orange,
        category: 'test',
        maxInputs: 1,
        maxOutputs: 1,
        ports: PortsLayout(
          inputs: [
            PortDefinition(relativeX: 0.833, relativeY: 1.0, direction: 'down'),
          ],
          outputs: [
            PortDefinition(relativeX: 0.833, relativeY: 0.0, direction: 'up'),
          ],
        ),
      );
      final project = ProjectState(
        buildings: [
          PlacedBuilding(
            id: 'processor',
            building: threeByThreeProcessor,
            gridX: 0,
            gridY: 0,
          ),
        ],
        conveyors: [
          ConveyorBelt(
            id: 'old_input_belt',
            path: const [
              Offset(2, 4),
              Offset(2, 3),
              Offset(2, 2),
            ],
            itemId: '',
          ),
        ],
      );

      final controller = TransportBeltController(
        project: project,
        onProjectChanged: (_) {},
        onRebuildCache: () {},
        notifyListeners: () {},
      );

      expect(controller.handleTap(const Offset(2, 3)), true);
      expect(controller.handleTap(const Offset(3, 3)), true);
      controller.handleRightClick();

      expect(
        project.conveyors.any((belt) =>
            belt.path.length == 1 && belt.path.single == const Offset(2, 2)),
        false,
      );
      expect(
        project.buildings.single
            .conveyorPortConnections(project.conveyors)['input_0'],
        isNull,
      );
    });

    test('split segment commits immediately and keeps creation active', () {
      final project = ProjectState(
        conveyors: [
          ConveyorBelt(
            id: 'old_belt',
            path: const [
              Offset(0, 3),
              Offset(0, 2),
              Offset(0, 1),
              Offset(0, 0),
            ],
            itemId: '',
            phaseOffset: 0.42,
            itemSegments: [
              ConveyorItemSegment(
                itemId: 'item_a',
                fillCount: 3,
                drainCount: 0,
              ),
            ],
          ),
        ],
      );

      final controller = TransportBeltController(
        project: project,
        onProjectChanged: (_) {},
        onRebuildCache: () {},
        notifyListeners: () {},
        currentPhase: () => 0.87,
      );

      expect(controller.handleTap(const Offset(0, 2)), true);
      expect(controller.handleTap(const Offset(1, 2)), true);

      expect(controller.hasCommittedPath, true);
      expect(controller.anchors, [
        const Offset(0, 2),
        const Offset(1, 2),
      ]);
      expect(project.conveyors, hasLength(2));

      final newBelt = project.conveyors.singleWhere(
        (belt) => belt.path.contains(const Offset(1, 2)),
      );
      expect(newBelt.path, [
        const Offset(0, 3),
        const Offset(0, 2),
        const Offset(1, 2),
      ]);
      expect(newBelt.itemSegments.single.itemId, 'item_a');
      expect(newBelt.itemSegments.single.fillCount, 2);
      expect(newBelt.itemSegments.single.drainCount, 0);
      expect(newBelt.phaseOffset, 0.42);
      expect(newBelt.pushSourceItem('item_a'), true);
      expect(newBelt.itemSegments.single.fillCount, 3);

      final downstream = project.conveyors.singleWhere(
        (belt) => belt.path.first == const Offset(0, 1),
      );
      expect(downstream.itemSegments.single.itemId, 'item_a');
      expect(downstream.itemSegments.single.fillCount, 1);
      expect(downstream.itemSegments.single.drainCount, 0);
      expect(downstream.phaseOffset, 0.42);
    });

    test('bridge continuation only joins matching lane', () {
      final project = ProjectState(
        buildings: [
          PlacedBuilding(
            id: 'bridge',
            building: testBeltBridge,
            gridX: 0,
            gridY: 0,
          ),
        ],
        conveyors: [
          ConveyorBelt(
            id: 'vertical_belt',
            path: const [
              Offset(0, -2),
              Offset(0, -1),
              Offset(0, 0),
              Offset(0, 1),
              Offset(0, 2),
            ],
            itemId: '',
          ),
          ConveyorBelt(
            id: 'left_belt',
            path: const [
              Offset(-2, 0),
              Offset(-1, 0),
              Offset(0, 0),
            ],
            itemId: '',
          ),
        ],
      );

      final controller = TransportBeltController(
        project: project,
        onProjectChanged: (_) {},
        onRebuildCache: () {},
        notifyListeners: () {},
      );

      expect(controller.handleTap(const Offset(0, 0)), true);
      expect(controller.handleTap(const Offset(1, 0)), true);
      controller.handleRightClick();

      expect(
        project.conveyors.any((belt) => belt.id == 'vertical_belt'),
        true,
      );
      expect(
        project.conveyors.any((belt) => belt.id == 'left_belt'),
        false,
      );
      expect(
        project.conveyors.any((belt) =>
            belt.path.length == 4 &&
            belt.path[0] == const Offset(-2, 0) &&
            belt.path[1] == const Offset(-1, 0) &&
            belt.path[2] == const Offset(0, 0) &&
            belt.path[3] == const Offset(1, 0)),
        true,
      );
    });

    test('bridge start begins creation and tracks preview path', () {
      final project = ProjectState(
        buildings: [
          PlacedBuilding(
            id: 'bridge',
            building: testBeltBridge,
            gridX: 0,
            gridY: 0,
          ),
        ],
        conveyors: [],
      );

      final controller = TransportBeltController(
        project: project,
        onProjectChanged: (_) {},
        onRebuildCache: () {},
        notifyListeners: () {},
      );

      // 在物流桥上开始创建：点击成功，进入创建态。
      expect(controller.handleTap(const Offset(0, 0)), true);
      // 悬停到相邻空格应生成预览路径而不抛异常。
      controller.handleHover(const Offset(1, 0));
      expect(controller.previewPath, isNotNull);
      // 右键取消后退出创建态，预览清空。
      controller.handleRightClick();
      expect(controller.previewPath, isNull);
    });
  });
}
