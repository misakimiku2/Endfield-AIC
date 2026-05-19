import 'dart:ui';
import 'building.dart';

class PortState {
  final int index;
  final String type;
  final PortDefinition definition;
  bool connected;
  String? linkedItemId;

  PortState({
    required this.index,
    required this.type,
    required this.definition,
    this.connected = false,
    this.linkedItemId,
  });

  Offset worldPosition(
      double gridX, double gridY, double cellSize, int gridWidth, int gridHeight) {
    return Offset(
      (gridX + definition.relativeX * gridWidth) * cellSize,
      (gridY + definition.relativeY * gridHeight) * cellSize,
    );
  }
}

class PlacedBuilding {
  final String id;
  final Building building;
  double gridX;
  double gridY;
  int rotation;
  String? activeRecipeId;
  List<PortState> inputPorts;
  List<PortState> outputPorts;
  bool isBlocked;
  double productionProgress;

  PlacedBuilding({
    required this.id,
    required this.building,
    required this.gridX,
    required this.gridY,
    this.rotation = 0,
    this.activeRecipeId,
    this.isBlocked = false,
    this.productionProgress = 0.0,
  })  : inputPorts = List.generate(
          building.ports.inputs.length,
          (i) => PortState(
            index: i,
            type: 'input',
            definition: building.ports.inputs[i],
          ),
        ),
        outputPorts = List.generate(
          building.ports.outputs.length,
          (i) => PortState(
            index: i,
            type: 'output',
            definition: building.ports.outputs[i],
          ),
        );

  Rect getBounds(double cellSize) {
    return Rect.fromLTWH(
      gridX * cellSize,
      gridY * cellSize,
      building.gridWidth * cellSize,
      building.gridHeight * cellSize,
    );
  }

  bool overlaps(Rect other, double cellSize) {
    return getBounds(cellSize).overlaps(other);
  }
}

class ConveyorBelt {
  final String id;
  final List<Offset> path;
  String itemId;
  List<Offset> particles;
  double flowProgress;
  bool isBlocked;

  ConveyorBelt({
    required this.id,
    required this.path,
    required this.itemId,
    List<Offset>? particles,
    this.flowProgress = 0.0,
    this.isBlocked = false,
  }) : particles = particles ?? [];

  static const double _cellSize = 48.0;

  Offset get start => path.isNotEmpty
      ? Offset(path.first.dx * _cellSize + _cellSize / 2,
          path.first.dy * _cellSize + _cellSize / 2)
      : Offset.zero;

  Offset get end => path.isNotEmpty
      ? Offset(path.last.dx * _cellSize + _cellSize / 2,
          path.last.dy * _cellSize + _cellSize / 2)
      : Offset.zero;

  double get length => path.length > 1 ? (path.length - 1) * _cellSize : 0.0;
}

class ProjectState {
  final List<PlacedBuilding> buildings;
  final List<ConveyorBelt> conveyors;
  double offsetX;
  double offsetY;
  double scale;

  ProjectState({
    List<PlacedBuilding>? buildings,
    List<ConveyorBelt>? conveyors,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
  })  : buildings = buildings ?? [],
        conveyors = conveyors ?? [];
}
