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
      double gridX, double gridY, double cellSize, int gridWidth, int gridHeight, {int rotation = 0}) {
    double rX = definition.relativeX;
    double rY = definition.relativeY;

    double localGridX = (rX == 1.0) ? (gridWidth - 1).toDouble() : (rX * gridWidth).floorToDouble();
    double localGridY = (rY == 1.0) ? (gridHeight - 1).toDouble() : (rY * gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - gridWidth / 2.0;
    double cy = ry - gridHeight / 2.0;

    double rcx, rcy;
    switch (rotation % 4) {
      case 1:
        rcx = -cy;
        rcy = cx;
        break;
      case 2:
        rcx = -cx;
        rcy = -cy;
        break;
      case 3:
        rcx = cy;
        rcy = -cx;
        break;
      case 0:
      default:
        rcx = cx;
        rcy = cy;
        break;
    }

    double wx = gridX + rcx + gridWidth / 2.0;
    double wy = gridY + rcy + gridHeight / 2.0;

    return Offset(wx * cellSize, wy * cellSize);
  }

  Offset gridPosition(
      double gridX, double gridY, int gridWidth, int gridHeight, {int rotation = 0}) {
    double rX = definition.relativeX;
    double rY = definition.relativeY;

    double localGridX = (rX == 1.0) ? (gridWidth - 1).toDouble() : (rX * gridWidth).floorToDouble();
    double localGridY = (rY == 1.0) ? (gridHeight - 1).toDouble() : (rY * gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - gridWidth / 2.0;
    double cy = ry - gridHeight / 2.0;

    double rcx, rcy;
    switch (rotation % 4) {
      case 1:
        rcx = -cy;
        rcy = cx;
        break;
      case 2:
        rcx = -cx;
        rcy = -cy;
        break;
      case 3:
        rcx = cy;
        rcy = -cx;
        break;
      case 0:
      default:
        rcx = cx;
        rcy = cy;
        break;
    }

    double wx = gridX + rcx + gridWidth / 2.0;
    double wy = gridY + rcy + gridHeight / 2.0;

    return Offset(wx.floorToDouble(), wy.floorToDouble());
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
  Map<String, int> inputInventory;
  Map<String, int> outputInventory;
  String? outputItemId; // 仓库取货口专用：选择的输出物品ID

  PlacedBuilding({
    required this.id,
    required this.building,
    required this.gridX,
    required this.gridY,
    this.rotation = 0,
    this.activeRecipeId,
    this.isBlocked = false,
    this.productionProgress = 0.0,
    Map<String, int>? inputInventory,
    Map<String, int>? outputInventory,
    this.outputItemId,
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
        ),
        inputInventory = inputInventory ?? {},
        outputInventory = outputInventory ?? {};

  /// 旋转后的有效宽度（90°/270° 时宽高互换）
  int get effectiveWidth => (rotation % 2 == 1) ? building.gridHeight : building.gridWidth;

  /// 旋转后的有效高度（90°/270° 时宽高互换）
  int get effectiveHeight => (rotation % 2 == 1) ? building.gridWidth : building.gridHeight;

  /// 旋转后的有效网格 X（调整原点使旋转后占地居中于同一中心点）
  double get effectiveGridX => gridX + (building.gridWidth - effectiveWidth) / 2.0;

  /// 旋转后的有效网格 Y（调整原点使旋转后占地居中于同一中心点）
  double get effectiveGridY => gridY + (building.gridHeight - effectiveHeight) / 2.0;

  Rect getBounds(double cellSize) {
    return Rect.fromLTWH(
      effectiveGridX * cellSize,
      effectiveGridY * cellSize,
      effectiveWidth * cellSize,
      effectiveHeight * cellSize,
    );
  }

  bool overlaps(Rect other, double cellSize) {
    return getBounds(cellSize).overlaps(other);
  }
}

class ConveyorItem {
  final String itemId;
  double position; // 在传送带路径上的位置，单位为格，0=起点

  ConveyorItem({
    required this.itemId,
    required this.position,
  });

  ConveyorItem copyWith({String? itemId, double? position}) => ConveyorItem(
        itemId: itemId ?? this.itemId,
        position: position ?? this.position,
      );
}

class ConveyorBelt {
  final String id;
  final List<Offset> path;
  List<ConveyorItem> items;
  double flowProgress;
  bool isBlocked;
  final String? forcedDirection;
  final String? incomingDirection;

  ConveyorBelt({
    required this.id,
    required this.path,
    List<ConveyorItem>? items,
    this.flowProgress = 0.0,
    this.isBlocked = false,
    this.forcedDirection,
    this.incomingDirection,
  }) : items = items ?? [];

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

  /// 传送带路径的最大位置值（格数）
  double get maxPosition => path.length > 1 ? (path.length - 1).toDouble() : 0.0;
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
