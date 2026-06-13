import '../../models/building.dart';
import 'logistics_unit_renderer.dart';

class ItemControlPortConfig {
  static const String id = LogisticsUnitRenderer.itemControlPortId;
  static const String name = '物品准入口';
  static const int gridWidth = 1;
  static const int gridHeight = 1;
  static const String color = '#8D6EFA';
  static const String category = 'logistics_units';
  static const int maxInputs = 1;
  static const int maxOutputs = 1;
  static const double transferRate = 0.0;
  static const String svgAssetPath = 'assets/svg/Item_Control_Port.svg';

  static const List<PortDefinition> inputPorts = [
    PortDefinition(
      relativeX: 0.5,
      relativeY: 1.0,
      direction: 'down',
      portType: 'solid',
    ),
  ];

  static const List<PortDefinition> outputPorts = [
    PortDefinition(
      relativeX: 0.5,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
  ];
}
