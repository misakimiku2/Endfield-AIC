import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';
import 'building_resource_panel.dart';
import 'building_depot_panel.dart';
import 'building_synthesis_panel.dart';

class BuildingDetailDialog extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final List<ConveyorBelt>? conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback? onInventoryChanged;
  final ValueChanged<String?>? onOutputItemSelected;

  const BuildingDetailDialog({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    this.onMove,
    this.onDelete,
    this.onInventoryChanged,
    this.onOutputItemSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required PlacedBuilding placedBuilding,
    required DataLoader dataLoader,
    List<ConveyorBelt>? conveyors,
    VoidCallback? onMove,
    VoidCallback? onDelete,
    VoidCallback? onInventoryChanged,
    ValueChanged<String?>? onOutputItemSelected,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => BuildingDetailDialog(
        placedBuilding: placedBuilding,
        dataLoader: dataLoader,
        conveyors: conveyors,
        onMove: onMove,
        onDelete: onDelete,
        onInventoryChanged: onInventoryChanged,
        onOutputItemSelected: onOutputItemSelected,
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

  late final List<ResourceItem> _allItems;
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
  Timer? _simTimer;

  bool get _isDepotUnloader =>
      widget.placedBuilding.building.id == 'depot_unloader_3x1';

  bool get _isDepotLoader =>
      widget.placedBuilding.building.id == 'depot_loader_3x1';

  void _toggleDepotAddMode() {
    setState(() {
      if (_selectedOutputItemId != null) {
        _selectedOutputItemId = null;
        _isAddMode = false;
        widget.placedBuilding.depotOutputItemId = null;
        widget.onOutputItemSelected?.call(null);
      } else {
        _isAddMode = !_isAddMode;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedOutputItemId = widget.placedBuilding.depotOutputItemId;
    _allItems = _buildResourceList();
    _loadLogo();
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
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

  List<ResourceItem> _buildResourceList() {
    final items = <ResourceItem>[];
    final seenNames = <String>{};

    for (final item in widget.dataLoader.items.values) {
      if (!seenNames.contains(item.name)) {
        seenNames.add(item.name);
        final category = _categoryToTabLabel[item.category] ?? '产物';
        items.add(ResourceItem(
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

  List<ResourceItem> get _filteredItems {
    final tabCategory = _tabLabels[_resourceTabIndex];
    return _allItems.where((item) => item.category == tabCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pb = widget.placedBuilding;
    final recipes = widget.dataLoader.getRecipesForBuilding(pb.building.id);

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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, top: 8, bottom: 4),
                    child: _buildPowerSwitch(),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildResourcePanel(),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _isDepotUnloader
                              ? DepotUnloaderPanel(
                                  placedBuilding: widget.placedBuilding,
                                  dataLoader: widget.dataLoader,
                                  onMove: widget.onMove,
                                  onDelete: widget.onDelete,
                                  onOutputItemSelected: widget.onOutputItemSelected,
                                  isAddMode: _isAddMode,
                                  selectedOutputItemId: _selectedOutputItemId,
                                  onToggleAddMode: _toggleDepotAddMode,
                                )
                              : _isDepotLoader
                                  ? DepotLoaderPanel(
                                      onMove: widget.onMove,
                                      onDelete: widget.onDelete,
                                    )
                                  : DefaultSynthesisPanel(
                                      placedBuilding: widget.placedBuilding,
                                      dataLoader: widget.dataLoader,
                                      conveyors: widget.conveyors,
                                      recipes: recipes,
                                      onMove: widget.onMove,
                                      onDelete: widget.onDelete,
                                      onInventoryChanged: widget.onInventoryChanged,
                                    ),
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
    return HoverCloseButton(
      onTap: () => Navigator.of(context).pop(),
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

  Widget _buildPowerSwitch() {
    const switchWidth = 120.0;
    const tabWidth = 60.0;
    final isOn = !widget.placedBuilding.isPaused;

    return SizedBox(
      width: switchWidth,
      height: 28,
      child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF6E6E6E),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: isOn ? 0 : tabWidth,
              top: 0,
              child: Container(
                width: tabWidth,
                height: 28,
                decoration: BoxDecoration(
                  color: isOn ? Colors.white : const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: tabWidth,
                  height: 28,
                  child: GestureDetector(
                    onTap: isOn
                        ? null
                        : () {
                            setState(() {
                              widget.placedBuilding.isPaused = false;
                            });
                          },
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        '开',
                        style: TextStyle(
                          color: isOn ? const Color(0xFF212121) : const Color(0xFF929292),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: tabWidth,
                  height: 28,
                  child: GestureDetector(
                    onTap: isOn
                        ? () {
                            setState(() {
                              widget.placedBuilding.isPaused = true;
                              widget.placedBuilding.productionProgress = 0.0;
                            });
                          }
                        : null,
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        '关',
                        style: TextStyle(
                          color: !isOn ? Colors.white : const Color(0xFF929292),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
                        : Tooltip(
                            message: _tabLabels[index],
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFF444444), width: 1),
                            ),
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            child: Center(
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
            final target =
                (_gridScrollController.offset + event.scrollDelta.dy * 1.5)
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
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
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
                return ResourceGridTile(
                  item: item,
                  gridContainerKey: _gridContainerKey,
                  showAddIcon: _isDepotUnloader && _isAddMode,
                  onAddItem: _isDepotUnloader && _isAddMode
                      ? () {
                          setState(() {
                            _selectedOutputItemId = item.id;
                            _isAddMode = false;
                          });
                          widget.placedBuilding.depotOutputItemId = item.id;
                          widget.onOutputItemSelected?.call(item.id);
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
            if (!_gridScrollController.hasClients)
              return const SizedBox.shrink();
            final position = _gridScrollController.position;
            final maxExtent = position.maxScrollExtent;
            if (maxExtent <= 0) return const SizedBox.shrink();

            const trackHeight = 438.0;
            final thumbHeight =
                (trackHeight * trackHeight / (trackHeight + maxExtent))
                    .clamp(30.0, trackHeight);
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
                      final scrollDelta =
                          delta * (maxExtent / (trackHeight - thumbHeight));
                      final target = (_dragStartOffset + scrollDelta)
                          .clamp(0.0, maxExtent);
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
                          color: Colors.white.withValues(
                              alpha: _isDraggingScrollbar ? 0.7 : 0.5),
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
}

