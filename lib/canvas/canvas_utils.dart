import 'package:flutter/material.dart';
import '../models/building.dart';
import '../models/project.dart';
import '../AIC/equipment.dart';

bool isBeltBridgeBuilding(Building building) {
  return building.id == LogisticsUnitRenderer.beltBridgeId;
}

String gridCellKey(Offset cell) {
  return '${cell.dx.round()}_${cell.dy.round()}';
}

Offset normalizedGridCell(Offset cell) {
  return Offset(cell.dx.roundToDouble(), cell.dy.roundToDouble());
}

String? directionBetweenGridCells(Offset from, Offset to) {
  final dx = to.dx.round() - from.dx.round();
  final dy = to.dy.round() - from.dy.round();
  if (dx == 1 && dy == 0) return 'right';
  if (dx == -1 && dy == 0) return 'left';
  if (dx == 0 && dy == 1) return 'down';
  if (dx == 0 && dy == -1) return 'up';
  return null;
}

bool isStraightBeltCell(ConveyorBelt belt, int cellIndex) {
  if (cellIndex < 0 || cellIndex >= belt.path.length) return false;
  if (belt.path.length == 1) {
    return belt.incomingDirection == null ||
        belt.forcedDirection == null ||
        belt.incomingDirection == belt.forcedDirection;
  }
  if (cellIndex == 0) {
    final outgoing = directionBetweenGridCells(belt.path[0], belt.path[1]);
    return belt.incomingDirection == null ||
        outgoing == null ||
        belt.incomingDirection == outgoing;
  }
  if (cellIndex == belt.path.length - 1) return true;

  final previous = belt.path[cellIndex - 1];
  final current = belt.path[cellIndex];
  final next = belt.path[cellIndex + 1];
  final incomingDx = current.dx.round() - previous.dx.round();
  final incomingDy = current.dy.round() - previous.dy.round();
  final outgoingDx = next.dx.round() - current.dx.round();
  final outgoingDy = next.dy.round() - current.dy.round();

  return incomingDx == outgoingDx && incomingDy == outgoingDy;
}

bool canBuildingOverlapBeltCell(
  Building building,
  ConveyorBelt belt,
  int cellIndex,
) {
  return isBeltBridgeBuilding(building) &&
      isStraightBeltCell(belt, cellIndex);
}
