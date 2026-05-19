import 'dart:ui';

class PortDefinition {
  final double relativeX;
  final double relativeY;
  final String direction;

  const PortDefinition({
    required this.relativeX,
    required this.relativeY,
    required this.direction,
  });

  factory PortDefinition.fromJson(Map<String, dynamic> json) {
    return PortDefinition(
      relativeX: (json['relative_x'] as num).toDouble(),
      relativeY: (json['relative_y'] as num).toDouble(),
      direction: json['direction'] as String,
    );
  }
}

class PortsLayout {
  final List<PortDefinition> inputs;
  final List<PortDefinition> outputs;

  const PortsLayout({required this.inputs, required this.outputs});

  factory PortsLayout.fromJson(Map<String, dynamic> json) {
    return PortsLayout(
      inputs: (json['inputs'] as List)
          .map((e) => PortDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      outputs: (json['outputs'] as List)
          .map((e) => PortDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Building {
  final String id;
  final String name;
  final int gridWidth;
  final int gridHeight;
  final Color color;
  final String category;
  final int maxInputs;
  final int maxOutputs;
  final PortsLayout ports;

  const Building({
    required this.id,
    required this.name,
    required this.gridWidth,
    required this.gridHeight,
    required this.color,
    required this.category,
    required this.maxInputs,
    required this.maxOutputs,
    required this.ports,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    final hex = json['color'] as String;
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      gridWidth: json['grid_width'] as int,
      gridHeight: json['grid_height'] as int,
      color: Color.fromARGB(255, r, g, b),
      category: json['category'] as String,
      maxInputs: json['max_inputs'] as int,
      maxOutputs: json['max_outputs'] as int,
      ports: PortsLayout.fromJson(json['ports'] as Map<String, dynamic>),
    );
  }
}