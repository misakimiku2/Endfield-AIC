class RecipeIO {
  final String itemId;
  final int amount;

  const RecipeIO({required this.itemId, required this.amount});

  factory RecipeIO.fromJson(Map<String, dynamic> json) {
    return RecipeIO(
      itemId: json['item_id'] as String,
      amount: json['amount'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'item_id': itemId, 'amount': amount};
}

class Recipe {
  final String id;
  final String name;
  final List<String> allowedBuildings;
  final double processTimeSeconds;
  final List<RecipeIO> inputs;
  final List<RecipeIO> outputs;

  const Recipe({
    required this.id,
    required this.name,
    required this.allowedBuildings,
    required this.processTimeSeconds,
    required this.inputs,
    required this.outputs,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      name: (json['name'] as String).replaceAll('精炼', ''),
      allowedBuildings: List<String>.from(json['allowed_buildings'] as List),
      processTimeSeconds: (json['process_time_seconds'] as num).toDouble(),
      inputs: (json['inputs'] as List)
          .map((e) => RecipeIO.fromJson(e as Map<String, dynamic>))
          .toList(),
      outputs: (json['outputs'] as List)
          .map((e) => RecipeIO.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'allowed_buildings': allowedBuildings,
        'process_time_seconds': processTimeSeconds,
        'inputs': inputs.map((e) => e.toJson()).toList(),
        'outputs': outputs.map((e) => e.toJson()).toList(),
      };
}