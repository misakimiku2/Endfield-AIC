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

  List<Item> get rawItems =>
      _items.values.where((i) => i.isRaw).toList();
  List<Item> get intermediateItems =>
      _items.values.where((i) => i.isIntermediate).toList();
  List<Item> get finalItems =>
      _items.values.where((i) => i.isFinal).toList();

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