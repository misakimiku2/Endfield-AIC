import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../models/item.dart';
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
  static const List<String> _tabLabels = ['植物', '矿物', '可用物品', '产物'];
  static const Map<String, String> _categoryToTabLabel = {
    'plant': '植物',
    'mineral_ore': '矿物',
    'usable': '可用物品',
    'product': '产物',
  };

  late final List<_ResourceItem> _allItems;
  String? _logoSvgString;
  final ScrollController _gridScrollController = ScrollController();
  final GlobalKey _gridContainerKey = GlobalKey();
  bool _scrollbarVisible = false;
  Timer? _scrollbarFadeTimer;
  bool _isDraggingScrollbar = false;
  double _dragStartY = 0;
  double _dragStartOffset = 0;

  // 仓库取货口专用状态
  bool _isAddMode = false;
  String? _selectedOutputItemId;

  bool get _isDepotUnloader =>
      widget.placedBuilding.building.id == 'depot_unloader_3x1';

  bool get _isDepotLoader =>
      widget.placedBuilding.building.id == 'depot_loader_3x1';

  bool get _isDepotAccess => _isDepotUnloader || _isDepotLoader;

  @override
  void initState() {
    super.initState();
    _allItems = _buildResourceList();
    _loadLogo();
  }

  @override
  void dispose() {
    _scrollbarFadeTimer?.cancel();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onGridScrolled() {
    _scrollbarFadeTimer?.cancel();
    if (!_scrollbarVisible) setState(() => _scrollbarVisible = true);
    _scrollbarFadeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _scrollbarVisible = false);
    });
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
        final category = _categoryToTabLabel[item.category] ?? '产物';
        items.add(_ResourceItem(
          id: item.id,
          name: item.name,
          category: category,
          color: item.color,
          imageAssetPath: item.imageAssetPath,
          level: item.level,
        ));
      }
    }
    return items;
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResourcePanel(),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildSynthesisPanel(recipes),
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
    return Container(
      width: 440,
      height: 520,
      decoration: BoxDecoration(
        color: const Color(0xFF373737),
        borderRadius: BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 24),
              _buildTabBar(),
              const SizedBox(height: 24),
              _buildGridArea(),
            ],
          ),
          Positioned(
            right: 6.085,
            top: 72,
            bottom: 0,
            child: Center(
              child: _buildGridScrollbar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    const tabIcons = [
      'assets/svg/Plant_icon.svg',
      'assets/svg/Mineral_Ore_icon.svg',
      'assets/svg/Usable_Items_icon.svg',
      'assets/svg/Products_icon.svg',
    ];

    const tabWidth = 93.75;
    const totalWidth = 375.0;

    return Center(
      child: SizedBox(
        width: totalWidth,
        height: 32,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF6E6E6E),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: _resourceTabIndex * tabWidth,
              top: 0,
              child: Container(
                width: tabWidth,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Row(
              children: List.generate(4, (index) {
                final isSelected = index == _resourceTabIndex;
                return SizedBox(
                  width: tabWidth,
                  height: 32,
                  child: GestureDetector(
                    onTap: () => setState(() => _resourceTabIndex = index),
                    behavior: HitTestBehavior.opaque,
                    child: isSelected
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                tabIcons[index],
                                width: 18,
                                height: 18,
                                colorFilter: const ColorFilter.mode(
                                  Color(0xFF212121),
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _tabLabels[index],
                                style: const TextStyle(
                                  color: Color(0xFF212121),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: SvgPicture.asset(
                              tabIcons[index],
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF929292),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridArea() {
    return Center(
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && _gridScrollController.hasClients) {
            final maxExtent = _gridScrollController.position.maxScrollExtent;
            final target = (_gridScrollController.offset + event.scrollDelta.dy * 1.5)
                .clamp(0.0, maxExtent);
            _gridScrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
            );
            _onGridScrolled();
          }
        },
        child: Container(
          key: _gridContainerKey,
          width: 395.66,
          height: 438,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.95),
          ),
          clipBehavior: Clip.antiAlias,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: GridView.builder(
              controller: _gridScrollController,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 7.3,
                crossAxisSpacing: 7.3,
                childAspectRatio: 93.44 / 93.62,
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return _ResourceGridTile(
                  item: item,
                  gridContainerKey: _gridContainerKey,
                  showAddIcon: _isDepotUnloader && _isAddMode,
                  onAddItem: _isDepotUnloader && _isAddMode
                      ? () {
                          setState(() {
                            _selectedOutputItemId = item.id;
                            _isAddMode = false;
                          });
                        }
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridScrollbar() {
    return SizedBox(
      width: 10,
      height: 438,
      child: AnimatedOpacity(
        opacity: (_scrollbarVisible || _isDraggingScrollbar) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ListenableBuilder(
          listenable: _gridScrollController,
          builder: (context, _) {
            if (!_gridScrollController.hasClients) return const SizedBox.shrink();
            final position = _gridScrollController.position;
            final maxExtent = position.maxScrollExtent;
            if (maxExtent <= 0) return const SizedBox.shrink();

            const trackHeight = 438.0;
            final thumbHeight =
                (trackHeight * trackHeight / (trackHeight + maxExtent)).clamp(30.0, trackHeight);
            final scrollFraction = position.pixels / maxExtent;
            final thumbTop = scrollFraction * (trackHeight - thumbHeight);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: thumbTop,
                  left: 0,
                  right: 0,
                  height: thumbHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (details) {
                      _dragStartY = details.globalPosition.dy;
                      _dragStartOffset = position.pixels;
                      _scrollbarFadeTimer?.cancel();
                      setState(() => _isDraggingScrollbar = true);
                    },
                    onVerticalDragUpdate: (details) {
                      final delta = details.globalPosition.dy - _dragStartY;
                      final scrollDelta = delta * (maxExtent / (trackHeight - thumbHeight));
                      final target = (_dragStartOffset + scrollDelta).clamp(0.0, maxExtent);
                      _gridScrollController.jumpTo(target);
                    },
                    onVerticalDragEnd: (_) {
                      setState(() => _isDraggingScrollbar = false);
                      _onGridScrolled();
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: _isDraggingScrollbar ? 0.7 : 0.5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSynthesisPanel(List<Recipe> recipes) {
    if (_isDepotUnloader) {
      return _buildDepotUnloaderPanel();
    }
    if (_isDepotLoader) {
      return _buildDepotLoaderPanel();
    }
    return _buildDefaultSynthesisPanel(recipes);
  }

  Widget _buildDepotLoaderPanel() {
    // 仓库存货口：只有输入网格，无添加按钮
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
            child: Center(
              child: _DepotGridTile(
                item: null,
                isInput: true,
                showNoIcon: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildDepotUnloaderPanel() {
    final selectedItem = _selectedOutputItemId != null
        ? widget.dataLoader.getItem(_selectedOutputItemId!)
        : null;

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
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DepotGridTile(
                    item: selectedItem,
                    isInput: false,
                    showNoIcon: false,
                  ),
                  const SizedBox(height: 16),
                  _DepotCapsuleButton(
                    hasItem: _selectedOutputItemId != null,
                    isAddMode: _isAddMode,
                    onToggleAddMode: () {
                      setState(() {
                        if (_selectedOutputItemId != null) {
                          // 移除物品
                          _selectedOutputItemId = null;
                          _isAddMode = false;
                        } else {
                          _isAddMode = !_isAddMode;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildDefaultSynthesisPanel(List<Recipe> recipes) {
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
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SynthesisGrid(
                    items: _activeRecipe?.inputs ?? [],
                    isInput: true,
                    dataLoader: widget.dataLoader,
                  ),
                  const SizedBox(width: 11),
                  _ProcessingIndicator(isRunning: widget.placedBuilding.productionProgress > 0),
                  const SizedBox(width: 11),
                  _SynthesisGrid(
                    items: _activeRecipe?.outputs ?? [],
                    isInput: false,
                    dataLoader: widget.dataLoader,
                  ),
                ],
              ),
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
  final String imageAssetPath;
  final int level;

  _ResourceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imageAssetPath,
    required this.level,
  });
}

class _ResourceGridTile extends StatefulWidget {
  final _ResourceItem item;
  final GlobalKey gridContainerKey;
  final bool showAddIcon;
  final VoidCallback? onAddItem;

  const _ResourceGridTile({
    required this.item,
    required this.gridContainerKey,
    this.showAddIcon = false,
    this.onAddItem,
  });

  @override
  State<_ResourceGridTile> createState() => _ResourceGridTileState();
}

String _gridTileSvg(int level) {
  const gradientEndColors = {
    2: '#93e8a4',
    3: '#6d9bf1',
    4: '#b73cc5',
  };
  const tagColors = {
    2: '#44aa00',
    3: '#0082ea',
    4: '#b73cc5',
  };
  final endColor = gradientEndColors[level] ?? '#dddddd';
  final tagColor = tagColors[level] ?? '#ebebeb';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="93.44" height="93.621" viewBox="0 0 93.44 93.621">'
      '<defs><linearGradient id="g" x1="902.412" y1="521.936" x2="902.412" y2="649.936" gradientUnits="userSpaceOnUse">'
      '<stop offset="0" stop-color="#696969"/>'
      '<stop offset="0.7" stop-color="#696969"/>'
      '<stop offset="1" stop-color="$endColor"/>'
      '</linearGradient></defs>'
      '<g transform="matrix(0.73,0,0,0.73,-610.056,-380.923)">'
      '<rect x="838.412" y="521.812" width="128" height="128.249" rx="15" ry="15" fill="url(#g)"/>'
      '<path d="m 839.26,640.061 c 2.048,5.831 7.585,9.991 14.131,10 h 98.043 c 6.546,-0.009 12.083,-4.169 14.131,-10 z" fill="$tagColor"/>'
      '</g></svg>';
}

class _ResourceGridTileState extends State<_ResourceGridTile> {
  bool _hovering = false;
  double _tooltipBottomOffset = 8.0;

  void _onEnter(PointerEnterEvent _) {
    double bottomOffset = 8.0;

    final tileBox = context.findRenderObject() as RenderBox;
    final gridBox =
        widget.gridContainerKey.currentContext?.findRenderObject() as RenderBox?;

    if (gridBox != null) {
      final tilePos = tileBox.localToGlobal(Offset.zero, ancestor: gridBox);
      final tileSize = tileBox.size;
      final gridSize = gridBox.size;

      final tooltipBottomInGrid = tilePos.dy + tileSize.height - 8.0;

      if (tooltipBottomInGrid > gridSize.height) {
        bottomOffset =
            (tileSize.height - (gridSize.height - tilePos.dy)).clamp(0.0, tileSize.height);
      }
    }

    setState(() {
      _tooltipBottomOffset = bottomOffset;
      _hovering = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.string(
            _gridTileSvg(widget.item.level),
            fit: BoxFit.fill,
          ),
          Center(
            child: widget.item.imageAssetPath.isNotEmpty
                ? Image.asset(
                    widget.item.imageAssetPath,
                    width: 93,
                    height: 93,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.item.color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.item.color.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.item.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.item.color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
          ),
          if (widget.showAddIcon)
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: widget.onAddItem,
                child: Container(
                  width: 21.9,
                  height: 21.9,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/svg/add.svg',
                      width: 12,
                      height: 12,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF212121),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_hovering)
            Positioned(
              bottom: _tooltipBottomOffset,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey[900]?.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SynthesisGrid extends StatefulWidget {
  final List<RecipeIO> items;
  final bool isInput;
  final DataLoader dataLoader;

  const _SynthesisGrid({
    required this.items,
    required this.isInput,
    required this.dataLoader,
  });

  @override
  State<_SynthesisGrid> createState() => _SynthesisGridState();
}

class _SynthesisGridState extends State<_SynthesisGrid> with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getGridSvg(int? level) {
    const gradientEndColors = {
      2: '#93e8a4',
      3: '#6d9bf1',
      4: '#b73cc5',
    };
    const tagColors = {
      2: '#44aa00',
      3: '#0082ea',
      4: '#b73cc5',
    };
    final endColor = gradientEndColors[level] ?? '#dddddd';
    final tagColor = tagColors[level] ?? '#ebebeb';
    final hasItem = level != null;
    
    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">'
        '<stop offset="0" stop-color="#696969"/>'
        '<stop offset="0.7" stop-color="#696969"/>'
        '<stop offset="1" stop-color="$endColor"/>'
        '</linearGradient></defs>'
        '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="${hasItem ? "url(#g)" : "#696969"}"/>'
        '${hasItem ? '<path d="m 1,118 c 2,5.8 7.6,10 14,10 h 98 c 6.4,0 12,-4.2 14,-10 z" fill="$tagColor"/>' : ''}'
        '</svg>';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items.isNotEmpty ? widget.items.first : null;
    final dataItem = item != null ? widget.dataLoader.getItem(item.itemId) : null;
    final level = dataItem?.level;
    final totalAmount = widget.items.fold<int>(0, (sum, io) => sum + io.amount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 128,
          height: 128,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.string(
                _getGridSvg(level),
                fit: BoxFit.fill,
              ),
              if (dataItem != null && dataItem.imageAssetPath.isNotEmpty)
                Center(
                  child: Image.asset(
                    dataItem.imageAssetPath,
                    width: 128,
                    height: 128,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    errorBuilder: (_, __, ___) => _buildItemPlaceholder(dataItem),
                  ),
                )
              else if (dataItem != null)
                Center(child: _buildItemPlaceholder(dataItem)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (totalAmount > 0)
          Text(
            '$totalAmount',
            style: const TextStyle(
              color: Color(0xFFDDDDDD),
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _buildItemPlaceholder(Item dataItem) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: dataItem.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: dataItem.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _ProcessingIndicator extends StatefulWidget {
  final bool isRunning;

  const _ProcessingIndicator({required this.isRunning});

  @override
  State<_ProcessingIndicator> createState() => _ProcessingIndicatorState();
}

class _ProcessingIndicatorState extends State<_ProcessingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
    });
    
    // 启动动画
    if (widget.isRunning) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted && widget.isRunning) {
          _controllers[i].repeat();
        }
      });
    }
  }

  @override
  void didUpdateWidget(_ProcessingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning != oldWidget.isRunning) {
      if (widget.isRunning) {
        _startAnimations();
      } else {
        for (final controller in _controllers) {
          controller.stop();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controllers[index],
            builder: (context, child) {
              final value = _controllers[index].value;
              // 使用正弦波实现闪烁效果：20% → 100% → 20% 循环
              final opacity = 0.2 + 0.8 * (0.5 + 0.5 * math.sin(value * 2 * math.pi));
              return Opacity(
                opacity: widget.isRunning ? opacity : 0.2,
                child: child,
              );
            },
            child: SizedBox(
              width: 16,
              height: 36,
              child: SvgPicture.asset(
                'assets/svg/Directional.svg',
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          );
        }).expand((widget) => [widget, const SizedBox(width: 4)]).toList()..removeLast(),
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

/// 仓库存取口 - 网格+轨道+箭头动画
/// [isInput] true=输入网格(存货口)，false=输出网格(取货口)
/// [showNoIcon] true=空网格显示No.svg
class _DepotGridTile extends StatefulWidget {
  final Item? item;
  final bool isInput;
  final bool showNoIcon;

  const _DepotGridTile({
    required this.item,
    required this.isInput,
    this.showNoIcon = false,
  });

  @override
  State<_DepotGridTile> createState() => _DepotGridTileState();
}

class _DepotGridTileState extends State<_DepotGridTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _arrowController;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _arrowController.dispose();
    super.dispose();
  }

  String _getGridSvg(int? level) {
    const gradientEndColors = {
      2: '#93e8a4',
      3: '#6d9bf1',
      4: '#b73cc5',
    };
    const tagColors = {
      2: '#44aa00',
      3: '#0082ea',
      4: '#b73cc5',
    };
    final endColor = gradientEndColors[level] ?? '#dddddd';
    final tagColor = tagColors[level] ?? '#ebebeb';
    final hasItem = level != null;

    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">'
        '<stop offset="0" stop-color="#696969"/>'
        '<stop offset="0.7" stop-color="#696969"/>'
        '<stop offset="1" stop-color="$endColor"/>'
        '</linearGradient></defs>'
        '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="${hasItem ? "url(#g)" : "#696969"}"/>'
        '${hasItem ? '<path d="m 1,118 c 2,5.8 7.6,10 14,10 h 98 c 6.4,0 12,-4.2 14,-10 z" fill="$tagColor"/>' : ''}'
        '</svg>';
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.item?.level;
    final hasItem = widget.item != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 网格 + 5px边框（圆角与SVG rx=15 完全对齐）
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFF7F7F7F),
              width: 5,
            ),
            borderRadius: BorderRadius.circular(15),
            color: const Color(0xFF696969),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.string(
                _getGridSvg(level),
                fit: BoxFit.fill,
              ),
              if (hasItem && widget.item!.imageAssetPath.isNotEmpty)
                Center(
                  child: Image.asset(
                    widget.item!.imageAssetPath,
                    width: 128,
                    height: 128,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    errorBuilder: (_, __, ___) => _buildItemPlaceholder(),
                  ),
                )
              else if (hasItem)
                Center(child: _buildItemPlaceholder())
              else if (widget.showNoIcon)
                Center(
                  child: SvgPicture.asset(
                    'assets/svg/No.svg',
                    width: 60,
                    height: 60,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF808080),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 轨道 + 箭头动画 + 遮罩
        _DepotTrackWithArrows(
          controller: _arrowController,
          isInput: widget.isInput,
        ),
      ],
    );
  }

  Widget _buildItemPlaceholder() {
    if (widget.item == null) return const SizedBox.shrink();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: widget.item!.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.item!.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 仓库存取口 - 轨道 + 箭头动画 + 遮罩蒙版
/// 轨道使用 dialog_track.svg，箭头从轨道外部开始循环移动
/// 存货口(isInput=true)：箭头指向左，从右向左移动
/// 取货口(isInput=false)：箭头指向右，从左向右移动
/// 遮罩：左边不透明，右边完全透明，覆盖整个轨道包括箭头
class _DepotTrackWithArrows extends StatelessWidget {
  final AnimationController controller;
  final bool isInput;

  const _DepotTrackWithArrows({
    required this.controller,
    required this.isInput,
  });

  /// 覆盖层渐变背景色，与弹窗内 Grid Tile 容器背景一致
  static const _overlayBgColor = Color(0xFF1E1E1E);

  @override
  Widget build(BuildContext context) {
    const trackWidth = 168.0;
    const trackHeight = 55.0;
    const arrowSize = 20.0;
    const arrowCount = 3;
    // 箭头从 -arrowSize 移动到 trackWidth+arrowSize，全程都在轨道外循环
    final totalTravel = trackWidth + arrowSize * 2;

    return SizedBox(
      width: trackWidth,
      height: trackHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 轨道背景（上下边缘向内收缩 1.0 像素，确保被渐变遮罩完全覆盖）
              Positioned(
                left: 0,
                right: 0,
                top: 1.0,
                bottom: 1.0,
                child: SvgPicture.asset(
                  'assets/svg/dialog_track.svg',
                  fit: BoxFit.fill,
                ),
              ),
              // 箭头
              ...List.generate(arrowCount, (index) {
                // 让 3 个箭头在时间上均匀错开，形成连续流
                final progress = (controller.value + index / arrowCount) % 1.0;
                // 存货口：从右向左；取货口：从左向右
                // 起点都是 -arrowSize（轨道外左侧），终点是 trackWidth+arrowSize（轨道外右侧）
                final x = isInput
                    ? -arrowSize + (1.0 - progress) * totalTravel
                    : -arrowSize + progress * totalTravel;
                // 箭头指向移动方向
                final pointRight = !isInput;

                return Positioned(
                  left: x,
                  top: (trackHeight - arrowSize) / 2,
                  child: CustomPaint(
                    size: const Size(arrowSize, arrowSize),
                    painter: _TriangleArrowPainter(
                      color: Colors.white,
                      pointRight: pointRight,
                    ),
                  ),
                );
              }),
              // 渐变覆盖层：左边透明(轨道完全可见) → 右边为容器背景色(视觉淡出)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x00000000),
                          _overlayBgColor,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 白色三角箭头画笔
class _TriangleArrowPainter extends CustomPainter {
  final Color color;
  final bool pointRight;

  const _TriangleArrowPainter({
    required this.color,
    required this.pointRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TriangleArrowPainter oldDelegate) =>
      color != oldDelegate.color || pointRight != oldDelegate.pointRight;
}

/// 仓库取货口 - 白色胶囊按钮（添加物品 / 移除物品）
class _DepotCapsuleButton extends StatefulWidget {
  final bool hasItem;
  final bool isAddMode;
  final VoidCallback onToggleAddMode;

  const _DepotCapsuleButton({
    required this.hasItem,
    required this.isAddMode,
    required this.onToggleAddMode,
  });

  @override
  State<_DepotCapsuleButton> createState() => _DepotCapsuleButtonState();
}

class _DepotCapsuleButtonState extends State<_DepotCapsuleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _iconRotationController;

  @override
  void initState() {
    super.initState();
    _iconRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.hasItem) {
      _iconRotationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_DepotCapsuleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasItem != oldWidget.hasItem) {
      if (widget.hasItem) {
        _iconRotationController.forward();
      } else {
        _iconRotationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _iconRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.hasItem ? '移除物品' : '添加物品';

    return GestureDetector(
      onTap: widget.onToggleAddMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF212121),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            RotationTransition(
              turns: Tween<double>(begin: 0.0, end: 0.125).animate(
                _iconRotationController,
              ),
              child: SvgPicture.asset(
                'assets/svg/add.svg',
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF212121),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}