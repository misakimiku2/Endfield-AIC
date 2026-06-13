import '../../models/building.dart';
import 'logistics_unit_renderer.dart';

class ConvergerConfig {
  static const String id = LogisticsUnitRenderer.convergerId;
  static const String name = '汇流器';
  static const int gridWidth = 1;
  static const int gridHeight = 1;
  static const String color = '#49B675';
  static const String category = 'logistics_units';
  static const int maxInputs = 3;
  static const int maxOutputs = 1;
  static const double transferRate = 0.5;
  static const String svgAssetPath = 'assets/svg/Converger.svg';

  static const List<PortDefinition> inputPorts = [
    PortDefinition(
      relativeX: 0.5,
      relativeY: 1.0,
      direction: 'down',
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

  static const List<PortDefinition> outputPorts = [
    PortDefinition(
      relativeX: 0.5,
      relativeY: 0.0,
      direction: 'up',
      portType: 'solid',
    ),
  ];
}
