import '../../models/building.dart';
import 'logistics_unit_renderer.dart';

class SplitterConfig {
  static const String id = LogisticsUnitRenderer.splitterId;
  static const String name = '分流器';
  static const int gridWidth = 1;
  static const int gridHeight = 1;
  static const String color = '#F5A623';
  static const String category = 'logistics_units';
  static const int maxInputs = 1;
  static const int maxOutputs = 3;
  static const double transferRate = 0.5;
  static const String svgAssetPath = 'assets/svg/Splitter.svg';

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
    PortDefinition(
      relativeX: 0.0,
      relativeY: 0.5,
      direction: 'left',
      portType: 'solid',
    ),
    PortDefinition(
      relativeX: 1.0,
      relativeY: 0.5,
      direction: 'right',
      portType: 'solid',
    ),
  ];
}
