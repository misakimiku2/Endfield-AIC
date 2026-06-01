import 'dart:ui';

class Item {
  final String id;
  final String name;
  final String category;
  final String subType;
  final Color color;
  final String iconSvg;
  final String imageAssetPath;
  final int level;

  const Item({
    required this.id,
    required this.name,
    required this.category,
    required this.subType,
    required this.color,
    required this.iconSvg,
    required this.imageAssetPath,
    required this.level,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    final hex = json['color'] as String;
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    return Item(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      subType: json['sub_type'] as String,
      color: Color.fromARGB(255, r, g, b),
      iconSvg: json['icon_svg'] as String? ?? '',
      imageAssetPath: json['image_asset_path'] as String? ?? '',
      level: json['level'] as int? ?? 1,
    );
  }
}
