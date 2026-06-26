import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:endfield_aic_planner/models/building.dart';
import 'package:endfield_aic_planner/models/project.dart';

void main() {
  // 一个 2x1 建筑，端口在右侧边缘（relativeX=1.0，relativeY=0.5）。
  // 用于验证旋转分支与 relativeX==1.0 边界处理。
  final port = PortState(
    index: 0,
    type: 'output',
    definition: const PortDefinition(
      relativeX: 1.0,
      relativeY: 0.5,
      direction: 'right',
    ),
  );
  // gridWidth=2, gridHeight=1, gridX=0, gridY=0（建筑左上角在原点）
  const gridW = 2;
  const gridH = 1;
  const gridX = 0.0;
  const gridY = 0.0;
  const cellSize = 48.0;

  group('PortState.worldPosition', () {
    test('rotation 0 keeps port at right edge', () {
      // localGridX = gridW-1 = 1, rx=1.5; localGridY=0, ry=0.5
      // cx = 1.5-1.0 = 0.5, cy = 0.5-0.5 = 0
      // rot0: rcx=0.5, rcy=0 → wx = 0+0.5+1.0 = 1.5, wy = 0+0+0.5 = 0.5
      final pos = port.worldPosition(gridX, gridY, cellSize, gridW, gridH);
      expect(pos, const Offset(1.5 * cellSize, 0.5 * cellSize));
    });

    test('rotation 1 rotates 90 degrees clockwise', () {
      // rot1: rcx=-cy=0, rcy=cx=0.5 → wx = 0+0+1.0 = 1.0, wy = 0+0.5+0.5 = 1.0
      final pos = port.worldPosition(gridX, gridY, cellSize, gridW, gridH, rotation: 1);
      expect(pos, const Offset(1.0 * cellSize, 1.0 * cellSize));
    });

    test('rotation 2 rotates 180 degrees', () {
      // rot2: rcx=-cx=-0.5, rcy=-cy=0 → wx = 0-0.5+1.0 = 0.5, wy = 0+0+0.5 = 0.5
      final pos = port.worldPosition(gridX, gridY, cellSize, gridW, gridH, rotation: 2);
      expect(pos, const Offset(0.5 * cellSize, 0.5 * cellSize));
    });

    test('rotation 3 rotates 270 degrees clockwise', () {
      // rot3: rcx=cy=0, rcy=-cx=-0.5 → wx = 0+0+1.0 = 1.0, wy = 0-0.5+0.5 = 0.0
      final pos = port.worldPosition(gridX, gridY, cellSize, gridW, gridH, rotation: 3);
      expect(pos, const Offset(1.0 * cellSize, 0.0 * cellSize));
    });
  });

  group('PortState.gridPosition', () {
    test('returns floored grid coordinates for rotation 0', () {
      final pos = port.gridPosition(gridX, gridY, gridW, gridH);
      // world (1.5, 0.5) → floor (1.0, 0.0)
      expect(pos, const Offset(1.0, 0.0));
    });

    test('returns floored grid coordinates for rotation 1', () {
      final pos = port.gridPosition(gridX, gridY, gridW, gridH, rotation: 1);
      // world (1.0, 1.0) → floor (1.0, 1.0)
      expect(pos, const Offset(1.0, 1.0));
    });
  });

  group('PortState.relativeY==1.0 boundary', () {
    test('treats relativeY of 1.0 as gridHeight-1 (not full height)', () {
      // 1x1 建筑，端口在底部边缘 relativeY=1.0：应取 gridHeight-1=0 而非 1.0*1=1
      final bottomPort = PortState(
        index: 0,
        type: 'input',
        definition: const PortDefinition(
          relativeX: 0.5,
          relativeY: 1.0,
          direction: 'down',
        ),
      );
      // localGridY = gridH-1 = 0, ry=0.5; cx=0, cy=0; rot0 → wy=0.5
      final pos = bottomPort.worldPosition(0.0, 0.0, cellSize, 1, 1);
      expect(pos, const Offset(0.5 * cellSize, 0.5 * cellSize));
    });
  });
}
