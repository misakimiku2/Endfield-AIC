import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/item.dart';
import '../models/recipe.dart';
import '../models/building.dart';

class DataLoader {
  Map<String, Item> _items = {};
  Map<String, Recipe> _recipes = {};
  Map<String, Building> _buildings = {};

  Map<String, Item> get items => _items;
  Map<String, Recipe> get recipes => _recipes;
  Map<String, Building> get buildings => _buildings;

  List<Item> get mineralOreItems =>
      _items.values.where((i) => i.category == 'mineral_ore').toList();
  List<Item> get plantItems =>
      _items.values.where((i) => i.category == 'plant').toList();
  List<Item> get usableItems =>
      _items.values.where((i) => i.category == 'usable').toList();
  List<Item> get productItems =>
      _items.values.where((i) => i.category == 'product').toList();

  List<Recipe> getRecipesForBuilding(String buildingId) {
    return _recipes.values
        .where((r) => r.allowedBuildings.contains(buildingId))
        .toList();
  }

  Item? getItem(String id) => _items[id];
  Recipe? getRecipe(String id) => _recipes[id];
  Building? getBuilding(String id) => _buildings[id];

  Future<void> loadAll() async {
    await Future.wait([
      loadItems(),
      loadRecipes(),
      loadBuildings(),
    ]);
  }

  Future<void> loadItems() async {
    final jsonStr =
        await rootBundle.loadString('assets/data/items_db.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final itemsMap = data['items'] as Map<String, dynamic>;
    _items = itemsMap.map(
      (k, v) => MapEntry(k, Item.fromJson(v as Map<String, dynamic>)),
    );
    await _loadItemDescriptions();
  }

  Future<void> _loadItemDescriptions() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/data/item_descriptions.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final descriptions = data['descriptions'] as Map<String, dynamic>;
      final updated = <String, Item>{};
      _items.forEach((id, item) {
        final desc = descriptions[id] as Map<String, dynamic>?;
        if (desc != null) {
          updated[id] = item.copyWith(
            description: desc['description'] as String? ?? '',
            secondaryDescription: desc['secondary_description'] as String? ?? '',
          );
        } else {
          updated[id] = item;
        }
      });
      _items = updated;
    } catch (_) {
      // 描述文件不存在时静默忽略，物品描述默认为空
    }
  }

  Future<void> loadRecipes() async {
    final jsonStr =
        await rootBundle.loadString('assets/data/recipes_db.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final recipesMap = data['recipes'] as Map<String, dynamic>;
    _recipes = recipesMap.map(
      (k, v) => MapEntry(k, Recipe.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> loadBuildings() async {
    final jsonStr =
        await rootBundle.loadString('assets/data/buildings_db.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final buildingsMap = data['buildings'] as Map<String, dynamic>;
    _buildings = buildingsMap.map(
      (k, v) => MapEntry(k, Building.fromJson(v as Map<String, dynamic>)),
    );
  }
}