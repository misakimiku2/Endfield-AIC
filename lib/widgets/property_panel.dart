import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';

class PropertyPanel extends StatelessWidget {
  final PlacedBuilding? selectedBuilding;
  final DataLoader dataLoader;
  final ValueChanged<String?>? onRecipeChanged;
  final VoidCallback? onRotate;
  final VoidCallback? onDelete;

  const PropertyPanel({
    super.key,
    this.selectedBuilding,
    required this.dataLoader,
    this.onRecipeChanged,
    this.onRotate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border:
            Border(left: BorderSide(color: Color(0xFF444444), width: 1)),
      ),
      child: selectedBuilding == null
          ? _buildEmptyState()
          : _buildPropertyContent(),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, color: Color(0xFF555555), size: 32),
          SizedBox(height: 8),
          Text(
            '双击设备查看属性',
            style: TextStyle(color: Color(0xFF666666), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyContent() {
    final pb = selectedBuilding!;
    final recipes = dataLoader.getRecipesForBuilding(pb.building.id);
    final activeRecipe =
        pb.activeRecipeId != null ? dataLoader.getRecipe(pb.activeRecipeId!) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('设备属性'),
          const SizedBox(height: 8),
          _propertyRow('名称', pb.building.name),
          _propertyRow('类型', pb.building.category),
          _propertyRow('尺寸', '${pb.building.gridWidth}x${pb.building.gridHeight}'),
          _propertyRow('位置', '(${pb.gridX.toInt()}, ${pb.gridY.toInt()})'),
          const Divider(color: Color(0xFF444444), height: 24),

          _sectionHeader('操作'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _actionButton('旋转', Icons.rotate_right, () => onRotate?.call()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  '删除',
                  Icons.delete_outline,
                  () => onDelete?.call(),
                  isDestructive: true,
                ),
              ),
            ],
          ),

          if (recipes.isNotEmpty) ...[
            const Divider(color: Color(0xFF444444), height: 24),
            _sectionHeader('生产配方'),
            const SizedBox(height: 8),
            ...recipes.map((r) => _recipeOption(r, activeRecipe)),
          ],

          if (activeRecipe != null) ...[
            const Divider(color: Color(0xFF444444), height: 24),
            _sectionHeader('配方详情'),
            const SizedBox(height: 8),
            _sectionSubHeader('输入'),
            ...activeRecipe.inputs.map((io) {
              final item = dataLoader.getItem(io.itemId);
              return _ioRow(item?.name ?? io.itemId, io.amount, item?.color);
            }),
            const SizedBox(height: 6),
            _sectionSubHeader('输出'),
            ...activeRecipe.outputs.map((io) {
              final item = dataLoader.getItem(io.itemId);
              return _ioRow(item?.name ?? io.itemId, io.amount, item?.color);
            }),
            const SizedBox(height: 6),
            _propertyRow(
              '周期',
              '${activeRecipe.processTimeSeconds.toStringAsFixed(1)}s',
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFCCCCCC),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _sectionSubHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _propertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback? onTap,
      {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFFF4444) : const Color(0xFF888888);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _recipeOption(Recipe recipe, Recipe? activeRecipe) {
    final isActive = activeRecipe?.id == recipe.id;
    return GestureDetector(
      onTap: () => onRecipeChanged?.call(isActive ? null : recipe.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0x30FFCC00)
              : const Color(0xFF1E1E1E),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFFCC00)
                : const Color(0xFF444444),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                recipe.name,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFFFFCC00)
                      : const Color(0xFFCCCCCC),
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              '${recipe.processTimeSeconds.toStringAsFixed(1)}s',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ioRow(String name, int amount, Color? color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color?.withAlpha((0.8 * 255).round()) ?? const Color(0xFF888888),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 11),
            ),
          ),
          Text(
            'x$amount',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ],
      ),
    );
  }
}