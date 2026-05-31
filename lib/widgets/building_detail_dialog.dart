import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';

class BuildingDetailDialog extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const BuildingDetailDialog({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.onMove,
    this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required PlacedBuilding placedBuilding,
    required DataLoader dataLoader,
    VoidCallback? onMove,
    VoidCallback? onDelete,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => BuildingDetailDialog(
        placedBuilding: placedBuilding,
        dataLoader: dataLoader,
        onMove: onMove,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<BuildingDetailDialog> createState() => _BuildingDetailDialogState();
}

class _BuildingDetailDialogState extends State<BuildingDetailDialog> {
  int _resourceTabIndex = 0;
  static const List<String> _tabLabels = ['矿物', '植物', '产物'];

  late final List<_ResourceItem> _allItems;
  String? _logoSvgString;

  @override
  void initState() {
    super.initState();
    _allItems = _buildResourceList();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    final logoPath = widget.placedBuilding.building.logoAssetPath;
    if (logoPath.isEmpty) return;
    try {
      final raw = await rootBundle.loadString(logoPath);
      final white = raw
          .replaceAllMapped(
            RegExp(r'fill:\s*#[0-9a-fA-F]+'),
            (_) => 'fill:#ffffff',
          )
          .replaceAllMapped(
            RegExp(r'fill-opacity:\s*[\d.]+'),
            (_) => 'fill-opacity:1',
          );
      if (mounted) {
        setState(() => _logoSvgString = white);
      }
    } catch (_) {}
  }

  List<_ResourceItem> _buildResourceList() {
    final items = <_ResourceItem>[];
    final seenNames = <String>{};

    for (final item in widget.dataLoader.items.values) {
      if (!seenNames.contains(item.name)) {
        seenNames.add(item.name);
        String category;
        if (_isMineral(item)) {
          category = '矿物';
        } else if (_isPlant(item)) {
          category = '植物';
        } else {
          category = '产物';
        }
        items.add(_ResourceItem(
          id: item.id,
          name: item.name,
          category: category,
          color: item.color,
        ));
      }
    }
    return items;
  }

  bool _isMineral(dynamic item) {
    final name = item.name;
    const minerals = ['源矿', '紫晶矿', '蓝铁矿', '赤铜矿'];
    return minerals.any((m) => name.contains(m));
  }

  bool _isPlant(dynamic item) {
    final subType = item.subType.toString().toLowerCase();
    return subType == 'plant' ||
        ['荞花', '柑实', '酮化灌木', '砂叶', '锦草', '芽针']
            .any((p) => item.name.contains(p));
  }

  List<_ResourceItem> get _filteredItems {
    final tabCategory = _tabLabels[_resourceTabIndex];
    return _allItems.where((item) => item.category == tabCategory).toList();
  }

  Recipe? get _activeRecipe {
    if (widget.placedBuilding.activeRecipeId == null) return null;
    return widget.dataLoader.getRecipe(widget.placedBuilding.activeRecipeId!);
  }

  @override
  Widget build(BuildContext context) {
    final pb = widget.placedBuilding;
    final recipes =
        widget.dataLoader.getRecipesForBuilding(pb.building.id);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = (screenWidth - 48).clamp(1280.0, 1460.0);

          return Container(
            width: dialogWidth,
            height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF444444)),
        ),
        child: Column(
          children: [
            _buildWindowInfoBar(),
            _buildSeparator(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: _buildResourcePanel(),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 4,
                          child: _buildSynthesisPanel(recipes),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
        },
      ),
    );
  }

  Widget _buildWindowInfoBar() {
    final building = widget.placedBuilding.building;
    return SizedBox(
      height: 77,
      child: Row(
        children: [
          const SizedBox(width: 16),
          _buildLogo(),
          _buildSeparatorVertical(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                building.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _buildSeparatorVertical(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '耗电功率值：${building.powerConsumption.toStringAsFixed(0)}W',
                style: const TextStyle(
                  color: Color(0xFFA6A6A6),
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const Spacer(),
          _buildCloseButton(),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildSeparatorVertical() {
    return Container(
      width: 2,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF444444),
    );
  }

  Widget _buildLogo() {
    if (_logoSvgString != null) {
      return SizedBox(
        width: 42,
        height: 42,
        child: SvgPicture.string(
          _logoSvgString!,
          fit: BoxFit.contain,
        ),
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: widget.placedBuilding.building.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.placedBuilding.building.color.withValues(alpha: 0.4),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.factory,
          size: 32,
          color: widget.placedBuilding.building.color.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: SizedBox(
        width: 26,
        height: 26,
        child: SvgPicture.asset(
          'assets/png/window/Close_button.svg',
          width: 26,
          height: 26,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      height: 1,
      color: const Color(0xFF444444),
    );
  }

  Widget _buildResourcePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final isActive = index == _resourceTabIndex;
            return Padding(
              padding: EdgeInsets.only(left: index > 0 ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _resourceTabIndex = index),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFFFFCC00)
                          : const Color(0xFF3A3A3A),
                    ),
                  ),
                  child: Text(
                    _tabLabels[index],
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFFFFCC00)
                          : const Color(0xFF999999),
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: GridView.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return _ResourceGridTile(item: item);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSynthesisPanel(List<Recipe> recipes) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              icon: Icons.open_with,
              label: '移动',
              onTap: () {
                Navigator.of(context).pop();
                widget.onMove?.call();
              },
            ),
            const SizedBox(width: 12),
            _ActionButton(
              icon: Icons.inventory_2_outlined,
              label: '收纳',
              onTap: () {
                Navigator.of(context).pop();
                widget.onDelete?.call();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          widget.placedBuilding.building.name,
          style: const TextStyle(
            color: Color(0xFFDDDDDD),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.placedBuilding.building.gridWidth}x${widget.placedBuilding.building.gridHeight}',
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SynthesisSlot(
                      label: '输入',
                      items: _activeRecipe?.inputs ?? [],
                      isInput: true,
                      dataLoader: widget.dataLoader,
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.arrow_forward,
                      size: 22,
                      color: Color(0xFF666666),
                    ),
                    const SizedBox(width: 12),
                    _SynthesisSlot(
                      label: '输出',
                      items: _activeRecipe?.outputs ?? [],
                      isInput: false,
                      dataLoader: widget.dataLoader,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF444444)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.list_alt_outlined,
                  size: 16,
                  color: Color(0xFF888888),
                ),
                SizedBox(width: 8),
                Text(
                  '本设备可自动生产的配方一览',
                  style: TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResourceItem {
  final String id;
  final String name;
  final String category;
  final Color color;

  _ResourceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
  });
}

class _ResourceGridTile extends StatelessWidget {
  final _ResourceItem item;

  const _ResourceGridTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.name,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: item.color.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.name.length > 5
                    ? '${item.name.substring(0, 5)}...'
                    : item.name,
                style: const TextStyle(
                  color: Color(0xFFBBBBBB),
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SynthesisSlot extends StatelessWidget {
  final String label;
  final List<RecipeIO> items;
  final bool isInput;
  final DataLoader dataLoader;

  const _SynthesisSlot({
    required this.label,
    required this.items,
    required this.isInput,
    required this.dataLoader,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 120,
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF404040)),
          ),
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '空',
                    style: TextStyle(
                      color: const Color(0xFF555555).withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final io = items[index];
                      final item = dataLoader.getItem(io.itemId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: item?.color.withValues(alpha: 0.2) ??
                                    const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: item?.color.withValues(alpha: 0.4) ??
                                      const Color(0xFF555555),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item?.name ?? io.itemId,
                                style: const TextStyle(
                                  color: Color(0xFFBBBBBB),
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'x${io.amount}',
                              style: const TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF444444)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFAAAAAA)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}