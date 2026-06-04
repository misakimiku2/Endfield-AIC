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
  final List<ConveyorBelt>? conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback? onConfigChanged;

  const BuildingDetailDialog({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    this.onMove,
    this.onDelete,
    this.onConfigChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required PlacedBuilding placedBuilding,
    required DataLoader dataLoader,
    List<ConveyorBelt>? conveyors,
    VoidCallback? onMove,
    VoidCallback? onDelete,
    VoidCallback? onConfigChanged,
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
        onConfigChanged: onConfigChanged,
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
  String? _liquidSwitchSvgString;
  String? _liquidSwitchOffSvgString;
  bool _isLiquidMode = false;
  bool _isLiquidHover = false;

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

  bool get _isDepotAccess => _isDepotUnloader || _isDepotLoader;

  @override
  void initState() {
    super.initState();
    _allItems = _buildResourceList();
    _loadLogo();
    _loadLiquidSwitch();
    _selectedOutputItemId = widget.placedBuilding.outputItemId;
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadLiquidSwitch() async {
    try {
      final raw = await rootBundle.loadString('assets/svg/liquid_icon_switch.svg');
      final off = raw.replaceAll('#03a9ff', '#b2b2b2');
      if (mounted) {
        setState(() {
          _liquidSwitchSvgString = raw;
          _liquidSwitchOffSvgString = off;
        });
      }
    } catch (_) {}
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
                              border: Border.all(color: const Color(0xFF444444), width: 1),
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
                            widget.placedBuilding.outputItemId = item.id;
                            _isAddMode = false;
                          });
                          widget.onConfigChanged?.call();
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

  Widget _buildLiquidModeSwitch() {
    if (_liquidSwitchSvgString == null) {
      return const SizedBox.shrink();
    }

    String currentSvg;
    if (_isLiquidMode) {
      if (_isLiquidHover) {
        currentSvg = _liquidSwitchSvgString!.replaceAll('#03a9ff', '#227aa8');
      } else {
        currentSvg = _liquidSwitchSvgString!;
      }
    } else {
      if (_isLiquidHover) {
        currentSvg = _liquidSwitchSvgString!.replaceAll('#03a9ff', '#636363');
      } else {
        currentSvg = _liquidSwitchSvgString!.replaceAll('#03a9ff', '#b2b2b2');
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isLiquidHover = true),
      onExit: (_) => setState(() => _isLiquidHover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isLiquidMode = !_isLiquidMode;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 150,
          height: 43,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SvgPicture.string(
                currentSvg,
                width: 150,
                height: 43,
                fit: BoxFit.contain,
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      _isLiquidMode ? '液体模式' : '关闭模式',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepotLoaderPanel() {
    // 仓库存货口：只有输入网格，无添加按钮
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              svgPath: 'assets/svg/Move.svg',
              label: '移动',
              onTap: () {
                Navigator.of(context).pop();
                widget.onMove?.call();
              },
            ),
            const SizedBox(width: 30),
            _ActionButton(
              svgPath: 'assets/svg/recycle.svg',
              label: '收纳',
              onTap: () {
                Navigator.of(context).pop();
                widget.onDelete?.call();
              },
            ),
          ],
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
              svgPath: 'assets/svg/Move.svg',
              label: '移动',
              onTap: () {
                Navigator.of(context).pop();
                widget.onMove?.call();
              },
            ),
            const SizedBox(width: 30),
            _ActionButton(
              svgPath: 'assets/svg/recycle.svg',
              label: '收纳',
              onTap: () {
                Navigator.of(context).pop();
                widget.onDelete?.call();
              },
            ),
          ],
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
                          widget.placedBuilding.outputItemId = null;
                          _isAddMode = false;
                        } else {
                          _isAddMode = !_isAddMode;
                        }
                      });
                      widget.onConfigChanged?.call();
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
    final solidInputPorts = widget.placedBuilding.inputPorts.where((p) => p.definition.portType == 'solid').toList();
    final solidOutputPorts = widget.placedBuilding.outputPorts.where((p) => p.definition.portType == 'solid').toList();
    final int maxPorts = math.max(solidInputPorts.length, solidOutputPorts.length);
    final double connectorHeight = maxPorts > 0 ? (maxPorts * 62.0) : 0.0;
    final double defaultGridBoxH = 128.0;
    final double defaultRowH = connectorHeight > defaultGridBoxH ? connectorHeight : defaultGridBoxH;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  svgPath: 'assets/svg/Move.svg',
                  label: '移动',
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onMove?.call();
                  },
                ),
                const SizedBox(width: 30),
                _ActionButton(
                  svgPath: 'assets/svg/recycle.svg',
                  label: '收纳',
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onDelete?.call();
                  },
                ),
              ],
            ),
            Positioned(
              right: 0,
              child: _buildLiquidModeSwitch(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double containerH = constraints.maxHeight;
                final double rowTop = (containerH / 2.0) - (defaultRowH / 2.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: rowTop,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SynthesisGrid(
                            items: _activeRecipe?.inputs ?? [],
                            isInput: true,
                            dataLoader: widget.dataLoader,
                            placedBuilding: widget.placedBuilding,
                            conveyors: widget.conveyors ?? [],
                            isLiquidMode: _isLiquidMode,
                            activeRecipe: _activeRecipe,
                          ),
                          const SizedBox(width: 11),
                          Container(
                            height: defaultRowH,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ProcessingIndicator(isRunning: widget.placedBuilding.productionProgress > 0),
                                if (widget.placedBuilding.productionProgress > 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_activeRecipe?.processTimeSeconds.toStringAsFixed(1) ?? "0.0"}s',
                                    style: const TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _ProductionProgressBar(
                                    progress: widget.placedBuilding.productionProgress,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 11),
                          _SynthesisGrid(
                            items: _activeRecipe?.outputs ?? [],
                            isInput: false,
                            dataLoader: widget.dataLoader,
                            placedBuilding: widget.placedBuilding,
                            conveyors: widget.conveyors ?? [],
                            isLiquidMode: _isLiquidMode,
                            activeRecipe: _activeRecipe,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        Builder(
          builder: (context) {
            final isProducing = _activeRecipe != null && widget.placedBuilding.productionProgress > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProducing)
                  const Padding(
                    padding: EdgeInsets.only(left: 30, bottom: 6),
                    child: Text(
                      '当前自动生产中的配方',
                      style: TextStyle(
                        color: Color(0xFF6E6E6E),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: SizedBox(
                      width: 369.92001,
                      height: 76.8,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            width: 348.16,
                            height: 76.8,
                            child: GestureDetector(
                              onTap: () => _showRecipeListDialog(context, recipes),
                              child: SvgPicture.asset(
                                'assets/svg/information_BG.svg',
                                width: 348.16,
                                height: 76.8,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            width: 348.16,
                            height: 76.8,
                            child: IgnorePointer(
                              child: Center(
                                child: isProducing
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              ...(_activeRecipe?.inputs.map((inp) {
                                                final item = widget.dataLoader.getItem(inp.itemId);
                                                if (item == null) return const SizedBox.shrink();
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: Image.asset(
                                                    item.imageAssetPath,
                                                    width: 24,
                                                    height: 24,
                                                    cacheWidth: 72,
                                                    cacheHeight: 72,
                                                    fit: BoxFit.contain,
                                                    filterQuality: FilterQuality.medium,
                                                    isAntiAlias: true,
                                                  ),
                                                );
                                              }) ?? []),
                                              const SizedBox(width: 48),
                                              ...(_activeRecipe?.outputs.map((out) {
                                                final item = widget.dataLoader.getItem(out.itemId);
                                                if (item == null) return const SizedBox.shrink();
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: Image.asset(
                                                    item.imageAssetPath,
                                                    width: 24,
                                                    height: 24,
                                                    cacheWidth: 72,
                                                    cacheHeight: 72,
                                                    fit: BoxFit.contain,
                                                    filterQuality: FilterQuality.medium,
                                                    isAntiAlias: true,
                                                  ),
                                                );
                                              }) ?? []),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          const _RecipeRunIndicator(),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.list_alt_outlined,
                                            size: 16,
                                            color: Color(0xFF888888),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            '本设备可自动生产的配方一览',
                                            style: TextStyle(
                                              color: Color(0xFFAAAAAA),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: (76.8 - 43.52002) / 2,
                            child: HoverSvgButton(
                              svgPath: 'assets/svg/Recipe_button.svg',
                              width: 43.52002,
                              height: 43.52002,
                              onTap: () => _showRecipeListDialog(context, recipes),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showRecipeListDialog(BuildContext context, List<Recipe> recipes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext dialogContext) {
        return _RecipeListDialog(
          recipes: recipes,
          placedBuilding: widget.placedBuilding,
          dataLoader: widget.dataLoader,
          onStateChanged: () {
            setState(() {});
          },
          onConfigChanged: widget.onConfigChanged,
        );
      },
    );
  }
}

class _RecipeListDialog extends StatefulWidget {
  final List<Recipe> recipes;
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final VoidCallback onStateChanged;
  final VoidCallback? onConfigChanged;

  const _RecipeListDialog({
    required this.recipes,
    required this.placedBuilding,
    required this.dataLoader,
    required this.onStateChanged,
    this.onConfigChanged,
  });

  @override
  State<_RecipeListDialog> createState() => _RecipeListDialogState();
}

class _RecipeListDialogState extends State<_RecipeListDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 960,
        height: 560,
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF444444)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '可自动生产的配方一览',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.placedBuilding.building.name,
                        style: const TextStyle(
                          color: Color(0xFFA6A6A6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                HoverCloseButton(
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && _scrollController.hasClients) {
                    final maxExtent = _scrollController.position.maxScrollExtent;
                    final target = (_scrollController.offset + event.scrollDelta.dy * 1.5)
                        .clamp(0.0, maxExtent);
                    _scrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: GridView.builder(
                    controller: _scrollController,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 3.5,
                    ),
                    itemCount: widget.recipes.length,
                    itemBuilder: (context, index) {
                      final recipe = widget.recipes[index];
                      final isPinned = widget.placedBuilding.activeRecipeId == recipe.id;
                      return _RecipeListItem(
                        recipe: recipe,
                        dataLoader: widget.dataLoader,
                        isPinned: isPinned,
                        onPin: () {
                          setState(() {
                            if (isPinned) {
                              widget.placedBuilding.activeRecipeId = null;
                            } else {
                              widget.placedBuilding.activeRecipeId = recipe.id;
                            }
                          });
                          widget.onStateChanged();
                          widget.onConfigChanged?.call();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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

String _gridTileSvg(int level, {bool isHovered = false}) {
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

  final stopColor = isHovered ? '#252525' : '#696969';

  return '<svg xmlns="http://www.w3.org/2000/svg" width="93.44" height="93.621" viewBox="0 0 93.44 93.621">'
      '<defs><linearGradient id="g" x1="902.412" y1="521.936" x2="902.412" y2="649.936" gradientUnits="userSpaceOnUse">'
      '<stop offset="0" stop-color="$stopColor"/>'
      '<stop offset="0.7" stop-color="$stopColor"/>'
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
      child: AnimatedScale(
        scale: _hovering ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            SvgPicture.string(
              _gridTileSvg(widget.item.level, isHovered: _hovering),
              fit: BoxFit.fill,
            ),
          Center(
            child: widget.item.imageAssetPath.isNotEmpty
                ? Image.asset(
                    widget.item.imageAssetPath,
                    width: 93,
                    height: 93,
                    cacheWidth: 279,
                    cacheHeight: 279,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
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
    ),
  );
}
}

class _SynthesisGrid extends StatefulWidget {
  final List<RecipeIO> items;
  final bool isInput;
  final DataLoader dataLoader;
  final PlacedBuilding placedBuilding;
  final List<ConveyorBelt> conveyors;
  final bool isLiquidMode;
  final Recipe? activeRecipe;

  const _SynthesisGrid({
    required this.items,
    required this.isInput,
    required this.dataLoader,
    required this.placedBuilding,
    required this.conveyors,
    this.isLiquidMode = false,
    this.activeRecipe,
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

  Widget _buildLiquidUnit(Item? dataItem, double scale) {
    final double w = 266.7 * scale;
    final double h = 141.7 * scale;
    final double cx = (widget.isInput ? 221.0 : 45.7) * scale;
    final double cy = 96.0 * scale;

    final svgWidget = SvgPicture.asset(
      'assets/svg/liquid.svg',
      width: w,
      height: h,
      fit: BoxFit.contain,
    );

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.isInput)
            svgWidget
          else
            Transform.scale(
              scaleX: -1,
              child: svgWidget,
            ),
          if (dataItem != null)
            Positioned(
              left: cx - 35,
              top: cy - 35,
              child: dataItem.imageAssetPath.isNotEmpty
                  ? Image.asset(
                      dataItem.imageAssetPath,
                      width: 70,
                      height: 70,
                      cacheWidth: 210,
                      cacheHeight: 210,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      isAntiAlias: true,
                      errorBuilder: (_, __, ___) => _buildItemPlaceholder(dataItem),
                    )
                  : _buildItemPlaceholder(dataItem),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取实际库存数据
    final inventory = widget.isInput
        ? widget.placedBuilding.inputInventory
        : widget.placedBuilding.outputInventory;

    // 构建配方需求映射（用于输入网格显示 "库存/需求" 格式）
    final Map<String, int> recipeRequirements = {};
    if (widget.isInput && widget.activeRecipe != null) {
      for (final input in widget.activeRecipe!.inputs) {
        recipeRequirements[input.itemId] = input.amount;
      }
    }

    // 合并库存中的物品和配方需求中的物品（确保配方需求但库存为0的物品也显示）
    final Set<String> allItemIds = {...inventory.keys};
    if (widget.isInput) {
      allItemIds.addAll(recipeRequirements.keys);
    }

    // 如果没有任何物品，显示配方原始内容（兼容无库存时的情况）
    final bool hasInventory = allItemIds.isNotEmpty;
    final List<String> displayItemIds;
    if (hasInventory) {
      displayItemIds = allItemIds.toList();
    } else {
      // 无库存时回退到配方数据
      displayItemIds = widget.items.map((io) => io.itemId).toList();
    }

    // 获取第一个物品用于网格显示（保持与原逻辑兼容）
    final item = widget.items.isNotEmpty ? widget.items.first : null;
    final dataItem = item != null ? widget.dataLoader.getItem(item.itemId) : null;

    // 计算显示的数量文本
    String countText;
    if (hasInventory && displayItemIds.isNotEmpty) {
      if (widget.isInput && widget.activeRecipe != null) {
        // 输入网格：显示 "库存/需求" 格式
        final firstId = displayItemIds.first;
        final invCount = inventory[firstId] ?? 0;
        final reqCount = recipeRequirements[firstId] ?? 0;
        if (displayItemIds.length == 1) {
          countText = reqCount > 0 ? '$invCount/$reqCount' : '$invCount';
        } else {
          // 多种物品时显示总数
          final totalInv = inventory.values.fold<int>(0, (sum, v) => sum + v);
          countText = '$totalInv';
        }
      } else {
        // 输出网格：显示库存数量
        final totalInv = inventory.values.fold<int>(0, (sum, v) => sum + v);
        countText = '$totalInv';
      }
    } else {
      final totalAmount = widget.items.fold<int>(0, (sum, io) => sum + io.amount);
      countText = '$totalAmount';
    }

    final solidPorts = (widget.isInput
            ? widget.placedBuilding.inputPorts
            : widget.placedBuilding.outputPorts)
        .where((p) => p.definition.portType == 'solid')
        .toList();

    // 如果有库存数据，使用库存中第一个有物品的条目来显示图标
    Item? displayItem = dataItem;
    if (hasInventory) {
      for (final id in displayItemIds) {
        final loaded = widget.dataLoader.getItem(id);
        if (loaded != null) {
          displayItem = loaded;
          break;
        }
      }
    }

    final gridBox = Container(
      width: 128,
      height: 128,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.string(
            _getGridSvg(displayItem?.level),
            fit: BoxFit.fill,
          ),
          if (displayItem != null && displayItem.imageAssetPath.isNotEmpty)
            Center(
              child: Image.asset(
                displayItem.imageAssetPath,
                width: 128,
                height: 128,
                cacheWidth: 384,
                cacheHeight: 384,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, __, ___) => _buildItemPlaceholder(displayItem!),
              ),
            )
          else if (displayItem != null)
            Center(child: _buildItemPlaceholder(displayItem)),
        ],
      ),
    );

    final double connectorHeight = solidPorts.isNotEmpty ? (solidPorts.length * 62.0) : 0.0;

    final double defaultGridBoxH = 128.0;
    final double defaultRowH = connectorHeight > defaultGridBoxH ? connectorHeight : defaultGridBoxH;
    final double originalGridBoxY = (defaultRowH - defaultGridBoxH) / 2.0;

    final double liquidScale = 1.10;
    final double liquidH = 141.7 * liquidScale;
    final double liquidGap = 10.0;
    final double downShift = widget.isLiquidMode ? (liquidH + liquidGap) : 0.0;
    final double upwardOffset = widget.isLiquidMode ? 75.0 : 0.0;

    final double finalLiquidY = originalGridBoxY - upwardOffset;
    final double finalGridBoxY = originalGridBoxY + downShift - upwardOffset;
    final double finalOffsetY = downShift - upwardOffset;

    final double newRowH = finalGridBoxY + defaultGridBoxH;
    final double finalHeight = newRowH > defaultRowH ? newRowH : defaultRowH;

    final double leftSizedBoxWidth = (widget.isInput && solidPorts.isNotEmpty) ? 288.0 : 0.0;
    final double rightSizedBoxWidth = (!widget.isInput && solidPorts.isNotEmpty) ? 288.0 : 0.0;
    final double gridBoxWidth = 128.0;
    final double totalWidth = leftSizedBoxWidth + gridBoxWidth + rightSizedBoxWidth;

    // Center of the gridBox horizontally
    final double gridBoxX = leftSizedBoxWidth;
    final double gridBoxCenterX = gridBoxX + gridBoxWidth / 2.0;

    // Calculate liquidBox X offset so its output/input "droplet" aligns with gridBox center
    final double liquidCx = (widget.isInput ? 221.0 : 45.7) * liquidScale;
    final double liquidBoxX = gridBoxCenterX - liquidCx;

    Widget mainGridContent = SizedBox(
      width: totalWidth,
      height: finalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.isLiquidMode)
            Positioned(
              left: liquidBoxX,
              top: finalLiquidY,
              child: _buildLiquidUnit(displayItem, liquidScale),
            ),
          Positioned(
            left: gridBoxX,
            top: finalGridBoxY,
            child: gridBox,
          ),
          if (widget.isInput && solidPorts.isNotEmpty)
            Positioned(
              left: 0,
              top: (defaultRowH - connectorHeight) / 2.0,
              child: _TrackJointsConnector(
                ports: solidPorts,
                conveyors: widget.conveyors,
                isInput: true,
                placedBuilding: widget.placedBuilding,
                offsetY: finalOffsetY,
              ),
            ),
          if (!widget.isInput && solidPorts.isNotEmpty)
            Positioned(
              right: 0,
              top: (defaultRowH - connectorHeight) / 2.0,
              child: _TrackJointsConnector(
                ports: solidPorts,
                conveyors: widget.conveyors,
                isInput: false,
                placedBuilding: widget.placedBuilding,
                offsetY: finalOffsetY,
              ),
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainGridContent,
        const SizedBox(height: 8),
        Text(
          countText,
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

class _TrackJointsConnector extends StatefulWidget {
  final List<PortState> ports;
  final List<ConveyorBelt> conveyors;
  final bool isInput;
  final PlacedBuilding placedBuilding;
  final double offsetY;

  const _TrackJointsConnector({
    required this.ports,
    required this.conveyors,
    required this.isInput,
    required this.placedBuilding,
    this.offsetY = 0.0,
  });

  @override
  State<_TrackJointsConnector> createState() => _TrackJointsConnectorState();
}

class _TrackJointsConnectorState extends State<_TrackJointsConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _isPortConnected(PortState port) {
    final portWorldPos = port.gridPosition(
      widget.placedBuilding.gridX,
      widget.placedBuilding.gridY,
      widget.placedBuilding.building.gridWidth,
      widget.placedBuilding.building.gridHeight,
      rotation: widget.placedBuilding.rotation,
    );
    for (final conveyor in widget.conveyors) {
      if (conveyor.path.isEmpty) continue;
      if (widget.isInput) {
        final last = conveyor.path.last;
        if (last.dx.round() == portWorldPos.dx.round() &&
            last.dy.round() == portWorldPos.dy.round()) {
          return true;
        }
      } else {
        final first = conveyor.path.first;
        if (first.dx.round() == portWorldPos.dx.round() &&
            first.dy.round() == portWorldPos.dy.round()) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final connections = widget.ports.map((p) => _isPortConnected(p)).toList();
    final int N = connections.length;
    final double height = N > 0 ? (N * 62.0) : 0;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(288, height > 0 ? height + widget.offsetY : 0),
          painter: _TrackJointsPainter(
            connections: connections,
            isInput: widget.isInput,
            animationValue: _animationController.value,
            offsetY: widget.offsetY,
          ),
        );
      },
    );
  }
}

class _TrackJointsPainter extends CustomPainter {
  final List<bool> connections;
  final bool isInput;
  final double animationValue;
  final double offsetY;

  const _TrackJointsPainter({
    required this.connections,
    required this.isInput,
    required this.animationValue,
    this.offsetY = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int N = connections.length;
    if (N == 0) return;

    // Define core styling paint objects according to interface.svg colors
    final Paint interfacePaint = Paint()..style = PaintingStyle.fill;
    final Paint linkPaint = Paint()..style = PaintingStyle.fill;
    final Paint inputCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint outputCirclePaint = Paint()
      ..color = const Color(0xFFEBAD26)
      ..style = PaintingStyle.fill;

    if (isInput) {
      interfacePaint.color = const Color(0xFF8D8C8C);
      linkPaint.color = const Color(0xFF6E6E6E);
    } else {
      interfacePaint.color = const Color(0xFFB38626);
      linkPaint.color = const Color(0xFF8D6E32);
    }

    final double blockHeight = 62.0;

    // ────────────────────────────────────────────────────────
    // 1. Draw static skeleton pieces according to interface.svg specs
    // ────────────────────────────────────────────────────────
    if (isInput) {
      final double devCenterY = N * blockHeight / 2.0 + offsetY;
      final double backboneBottom = N * blockHeight > (devCenterY + 3.3) 
          ? N * blockHeight 
          : (devCenterY + 3.3);

      // Draw concatenated 'interface_link_separate' (vertical backbone)
      canvas.drawRect(Rect.fromLTRB(207.5, 0, 212.5, backboneBottom), linkPaint);

      // Draw consolidated 'window_link' running from backbone to grid-box
      canvas.drawRect(Rect.fromLTRB(211.5, devCenterY - 3.3, size.width, devCenterY + 3.3), linkPaint);

      // Draw junction circle near grid-box
      canvas.drawCircle(Offset(size.width, devCenterY), 6.0, inputCirclePaint);

      for (int i = 0; i < N; i++) {
        final double centerY = i * blockHeight + blockHeight / 2.0;
        
        // Draw 'interface_link' block (overlaps to 174 and 209 to prevent anti-alias black line)
        canvas.drawRect(Rect.fromLTWH(174, centerY - 3.3, 35, 6.6), linkPaint);

        // Draw 'interface' block on top
        canvas.drawRect(Rect.fromLTWH(168, centerY - 27, 7, 54), interfacePaint);

        // Draw junction circle at interface link
        canvas.drawCircle(Offset(175, centerY), 6.0, inputCirclePaint);
      }
    } else {
      final double devCenterY = N * blockHeight / 2.0 + offsetY;
      final double backboneBottom = N * blockHeight > (devCenterY + 3.3) 
          ? N * blockHeight 
          : (devCenterY + 3.3);

      // Draw concatenated 'interface_link_separate' (vertical backbone)
      canvas.drawRect(Rect.fromLTRB(size.width - 212.5, 0, size.width - 207.5, backboneBottom), linkPaint);

      // Draw consolidated 'window_link' running from grid-box to backbone
      canvas.drawRect(Rect.fromLTRB(0, devCenterY - 3.3, size.width - 211.5, devCenterY + 3.3), linkPaint);

      // Draw junction circle near grid-box
      canvas.drawCircle(Offset(0, devCenterY), 6.0, outputCirclePaint);

      for (int i = 0; i < N; i++) {
        final double centerY = i * blockHeight + blockHeight / 2.0;

        // Draw 'interface_link' block
        canvas.drawRect(Rect.fromLTWH(size.width - 209, centerY - 3.3, 35, 6.6), linkPaint);

        // Draw 'interface' block
        canvas.drawRect(Rect.fromLTWH(size.width - 175, centerY - 27, 7, 54), interfacePaint);

        // Draw junction circle at interface link
        canvas.drawCircle(Offset(size.width - 175, centerY), 6.0, outputCirclePaint);
      }
    }

    // ────────────────────────────────────────────────────────
    // 2. Draw active flow belts with glowing borders & flow arrows on connected ports
    // ────────────────────────────────────────────────────────
    final Paint activeTrackPaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final Paint activeLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    if (isInput) {
      activeLinePaint.color = Colors.white;
    } else {
      activeLinePaint.color = const Color(0xFFEBAD26);
    }

    final double activeDevCenterY = N * blockHeight / 2.0 + offsetY;

    for (int i = 0; i < N; i++) {
      if (!connections[i]) continue;

      final double centerY = i * blockHeight + blockHeight / 2.0;

      if (isInput) {
        // Draw the active glowing connection line
        final path = Path()
          ..moveTo(175.0, centerY)
          ..lineTo(210.0, centerY)
          ..lineTo(210.0, activeDevCenterY)
          ..lineTo(size.width, activeDevCenterY);
        canvas.drawPath(path, activeLinePaint);

        // Active incoming conveyor belt track overlay
        final double strokeHalf = 1.6 / 2;
        // height = 54, so +/- 27. Draw rect inside.
        final rect = Rect.fromLTRB(0, centerY - 27, 168, centerY + 27);
        
        final gradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x00E88A11),
            Color(0xAAFFB82B),
          ],
        );
        activeTrackPaint.shader = gradient.createShader(rect);
        canvas.drawRect(rect, activeTrackPaint);

        final borderGradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x00FFBB33),
            Color(0xDDFFD266),
          ],
        );
        borderPaint.shader = borderGradient.createShader(rect);
        // Offset lines inwards by half a stroke width to avoid protruding above/below 54 block height
        canvas.drawLine(Offset(0, centerY - 27 + strokeHalf), Offset(168, centerY - 27 + strokeHalf), borderPaint);
        canvas.drawLine(Offset(0, centerY + 27 - strokeHalf), Offset(168, centerY + 27 - strokeHalf), borderPaint);

        canvas.save();
        canvas.clipRect(rect);
        for (int anim = 0; anim < 2; anim++) {
          final double t = (animationValue + anim / 2.0) % 1.0;
          final double arrowX = t * 168.0;
          // Opacity goes fully translucent to solid as it moves right
          final double opacity = (arrowX / 168.0) * 0.9;

          final arrowPaint = Paint()
            ..color = Colors.white.withValues(alpha: opacity)
            ..style = PaintingStyle.fill;

          final path = Path()
            ..moveTo(arrowX - 4, centerY - 6)
            ..lineTo(arrowX + 6, centerY)
            ..lineTo(arrowX - 4, centerY + 6)
            ..close();

          canvas.drawPath(path, arrowPaint);
        }
        canvas.restore();
      } else {
        // Draw the active glowing connection line
        final path = Path()
          ..moveTo(size.width - 175.0, centerY)
          ..lineTo(size.width - 210.0, centerY)
          ..lineTo(size.width - 210.0, activeDevCenterY)
          ..lineTo(0.0, activeDevCenterY);
        canvas.drawPath(path, activeLinePaint);

        // Active outgoing conveyor belt track overlay
        final double startX = size.width - 168;
        final double strokeHalf = 1.6 / 2;
        final rect = Rect.fromLTRB(startX, centerY - 27, size.width, centerY + 27);

        final gradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xAAFFB82B),
            Color(0x00E88A11),
          ],
        );
        activeTrackPaint.shader = gradient.createShader(rect);
        canvas.drawRect(rect, activeTrackPaint);

        final borderGradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xDDFFD266),
            Color(0x00FFBB33),
          ],
        );
        borderPaint.shader = borderGradient.createShader(rect);
        // Offset lines inwards by half a stroke width
        canvas.drawLine(Offset(startX, centerY - 27 + strokeHalf), Offset(size.width, centerY - 27 + strokeHalf), borderPaint);
        canvas.drawLine(Offset(startX, centerY + 27 - strokeHalf), Offset(size.width, centerY + 27 - strokeHalf), borderPaint);

        canvas.save();
        canvas.clipRect(rect);
        for (int anim = 0; anim < 2; anim++) {
          final double t = (animationValue + anim / 2.0) % 1.0;
          final double arrowX = startX + t * 168.0;
          final double opacity = (1.0 - (arrowX - startX) / 168.0) * 0.9;

          final arrowPaint = Paint()
            ..color = Colors.white.withValues(alpha: opacity)
            ..style = PaintingStyle.fill;

          final path = Path()
            ..moveTo(arrowX - 4, centerY - 6)
            ..lineTo(arrowX + 6, centerY)
            ..lineTo(arrowX - 4, centerY + 6)
            ..close();

          canvas.drawPath(path, arrowPaint);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrackJointsPainter oldDelegate) =>
      oldDelegate.connections != connections ||
      oldDelegate.isInput != isInput ||
      oldDelegate.animationValue != animationValue;
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

/// 生产进度条 - 胶囊形状，绿色渐变填充
class _ProductionProgressBar extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0

  const _ProductionProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: 168,
      height: 12,
      child: CustomPaint(
        painter: _ProgressBarPainter(progress: clampedProgress),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;

  _ProgressBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height / 2.0;
    final rect = Offset.zero & size;

    // 背景 - 深灰色胶囊
    final bgPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      bgPaint,
    );

    // 填充 - 绿色渐变
    if (progress > 0) {
      final fillWidth = size.width * progress;
      final fillRect = Rect.fromLTWH(0, 0, fillWidth, size.height);

      final gradient = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF44AA00),
          Color(0xFF88DD44),
        ],
      );

      final fillPaint = Paint()
        ..shader = gradient.createShader(fillRect)
        ..style = PaintingStyle.fill;

      // 使用 clipRRect 来确保填充也是胶囊形
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      canvas.drawRect(fillRect, fillPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ActionButton extends StatefulWidget {
  final String svgPath;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.svgPath,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;
  String? _svgString;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSvg();
  }

  @override
  void didUpdateWidget(_ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgPath != widget.svgPath) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    try {
      final data = await DefaultAssetBundle.of(context).loadString(widget.svgPath);
      if (mounted) {
        setState(() {
          _svgString = data;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    if (_svgString == null) {
      iconWidget = const SizedBox(
        width: 44,
        height: 44,
      );
    } else {
      String finalSvg = _svgString!;
      if (_isHovered) {
        finalSvg = finalSvg
            .replaceAll('fill:#636363', 'fill:#TEMP_WHITE_SVG')
            .replaceAll('fill:#ffffff', 'fill:#636363')
            .replaceAll('fill:#TEMP_WHITE_SVG', 'fill:#ffffff');
      }
      iconWidget = SvgPicture.string(
        finalSvg,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
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
                    cacheWidth: 384,
                    cacheHeight: 384,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
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

  @override
  Widget build(BuildContext context) {
    const trackWidth = 168.0;
    const trackHeight = 54.0;

    return SizedBox(
      width: trackWidth,
      height: trackHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(trackWidth, trackHeight),
            painter: _DepotTrackPainter(
              animationValue: controller.value,
              isInput: isInput,
            ),
          );
        },
      ),
    );
  }
}

class _DepotTrackPainter extends CustomPainter {
  final double animationValue;
  final bool isInput;

  _DepotTrackPainter({
    required this.animationValue,
    required this.isInput,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    
    final Paint activeTrackPaint = Paint()..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final gradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xAAFFB82B),
        Color(0x00E88A11),
      ],
    );
    activeTrackPaint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, activeTrackPaint);

    final borderGradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xDDFFD266),
        Color(0x00FFBB33),
      ],
    );
    borderPaint.shader = borderGradient.createShader(rect);
    
    final double strokeHalf = 1.6 / 2;
    canvas.drawLine(Offset(0, strokeHalf), Offset(size.width, strokeHalf), borderPaint);
    canvas.drawLine(Offset(0, size.height - strokeHalf), Offset(size.width, size.height - strokeHalf), borderPaint);

    canvas.save();
    canvas.clipRect(rect);
    final double centerY = size.height / 2;
    
    for (int anim = 0; anim < 2; anim++) {
      final double t = (animationValue + anim / 2.0) % 1.0;
      final double arrowX = isInput 
          ? size.width - (t * size.width) 
          : t * size.width;
      
      final double opacity = (1.0 - (arrowX / size.width)).clamp(0.0, 1.0) * 0.9;
      
      final Paint arrowPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      
      final path = Path();
      if (isInput) {
        path.moveTo(arrowX + 4, centerY - 6);
        path.lineTo(arrowX - 6, centerY);
        path.lineTo(arrowX + 4, centerY + 6);
      } else {
        path.moveTo(arrowX - 4, centerY - 6);
        path.lineTo(arrowX + 6, centerY);
        path.lineTo(arrowX - 4, centerY + 6);
      }
      path.close();
      
      canvas.drawPath(path, arrowPaint);
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DepotTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.isInput != isInput;
  }
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

class _RecipeListItem extends StatelessWidget {
  final Recipe recipe;
  final DataLoader dataLoader;
  final bool isPinned;
  final VoidCallback onPin;

  const _RecipeListItem({
    required this.recipe,
    required this.dataLoader,
    required this.isPinned,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final inputs = recipe.inputs;
    final input1 = inputs.isNotEmpty ? dataLoader.getItem(inputs[0].itemId) : null;
    final amount1 = inputs.isNotEmpty ? inputs[0].amount : 1;
    final input2 = inputs.length > 1 ? dataLoader.getItem(inputs[1].itemId) : null;
    final amount2 = inputs.length > 1 ? inputs[1].amount : 1;

    final outputs = recipe.outputs;
    final output1 = outputs.isNotEmpty ? dataLoader.getItem(outputs[0].itemId) : null;
    final outAmount1 = outputs.isNotEmpty ? outputs[0].amount : 1;
    final output2 = outputs.length > 1 ? dataLoader.getItem(outputs[1].itemId) : null;
    final outAmount2 = outputs.length > 1 ? outputs[1].amount : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 14,
                color: Color(0xFFCCCCCC),
              ),
              const SizedBox(width: 6),
              Text(
                recipe.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _MiniItemTile(item: input1, amount: amount1),
              const SizedBox(width: 8),
              _MiniItemTile(item: input2, amount: amount2),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF666666)),
                      Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF666666)),
                      Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF666666)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${recipe.processTimeSeconds.toStringAsFixed(0)}秒',
                    style: const TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _MiniItemTile(item: output1, amount: outAmount1),
              const SizedBox(width: 8),
              _MiniItemTile(item: output2, amount: outAmount2),
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 54,
                color: const Color(0xFFDCDCDC),
              ),
              const SizedBox(width: 12),
              _RecipePinButton(
                isPinned: isPinned,
                onTap: onPin,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipePinButton extends StatefulWidget {
  final bool isPinned;
  final VoidCallback onTap;

  const _RecipePinButton({
    required this.isPinned,
    required this.onTap,
  });

  @override
  State<_RecipePinButton> createState() => _RecipePinButtonState();
}

class _RecipePinButtonState extends State<_RecipePinButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool applyTransform = widget.isPinned || _isHovered;

    Color mainColor;
    if (widget.isPinned) {
      mainColor = const Color(0xFF99932A);
    } else if (_isHovered) {
      mainColor = const Color(0xFFCAAD2B);
    } else {
      mainColor = const Color(0xFF888888);
    }

    Color borderColor = widget.isPinned
        ? const Color(0xFF99932A)
        : (_isHovered ? const Color(0xFFCAAD2B) : const Color(0xFFCCCCCC));

    double rotationAngle = applyTransform ? math.pi / 4 : 0.0;
    double scale = applyTransform ? 1.25 : 1.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isPinned ? mainColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: widget.isPinned ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: AnimatedRotation(
              turns: rotationAngle / (2 * math.pi),
              duration: const Duration(milliseconds: 150),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.push_pin,
                  size: 18,
                  color: mainColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniItemTile extends StatelessWidget {
  final Item? item;
  final int amount;

  const _MiniItemTile({required this.item, required this.amount});

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFCCCCCC)),
        ),
        child: CustomPaint(
          painter: _DiagonalSlashPainter(),
        ),
      );
    }

    final colors = {
      2: const Color(0xFF44AA00),
      3: const Color(0xFF0082EA),
      4: const Color(0xFFB73CC5),
    };
    final tagColor = colors[item!.level] ?? const Color(0xFFEBEBEB);

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF666666)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item!.imageAssetPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(2),
              child: Image.asset(
                item!.imageAssetPath,
                cacheWidth: 162,
                cacheHeight: 162,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, __, ___) => Container(),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 12,
            child: Container(
              color: tagColor,
              alignment: Alignment.center,
              child: Text(
                '$amount',
                style: TextStyle(
                  color: item!.level >= 2 ? Colors.white : Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalSlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RecipeRunIndicator extends StatefulWidget {
  const _RecipeRunIndicator();

  @override
  State<_RecipeRunIndicator> createState() => _RecipeRunIndicatorState();
}

class _RecipeRunIndicatorState extends State<_RecipeRunIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;

        double op1, op2, op3;
        if (t < 1.0 / 3.0) {
          double subT = t / (1.0 / 3.0);
          op1 = 0.2 + (1.0 - 0.2) * subT;
          op2 = 0.6 + (0.2 - 0.6) * subT;
          op3 = 1.0 + (0.6 - 1.0) * subT;
        } else if (t < 2.0 / 3.0) {
          double subT = (t - 1.0 / 3.0) / (1.0 / 3.0);
          op1 = 1.0 + (0.6 - 1.0) * subT;
          op2 = 0.2 + (1.0 - 0.2) * subT;
          op3 = 0.6 + (0.2 - 0.6) * subT;
        } else {
          double subT = (t - 2.0 / 3.0) / (1.0 / 3.0);
          op1 = 0.6 + (0.2 - 0.6) * subT;
          op2 = 1.0 + (0.6 - 1.0) * subT;
          op3 = 0.2 + (1.0 - 0.2) * subT;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTriangle(op1),
            const SizedBox(width: 4),
            _buildTriangle(op2),
            const SizedBox(width: 4),
            _buildTriangle(op3),
          ],
        );
      },
    );
  }

  Widget _buildTriangle(double opacity) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: SizedBox(
        width: 10,
        height: 12,
        child: SvgPicture.asset(
          'assets/svg/Directional.svg',
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(
            Colors.white,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

class HoverCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const HoverCloseButton({super.key, required this.onTap});

  @override
  State<HoverCloseButton> createState() => _HoverCloseButtonState();
}

class _HoverCloseButtonState extends State<HoverCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 26,
          height: 26,
          child: SvgPicture.asset(
            'assets/png/window/Close_button.svg',
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            colorFilter: _isHovered
                ? const ColorFilter.mode(Color(0xFF636363), BlendMode.srcIn)
                : null,
          ),
        ),
      ),
    );
  }
}

class HoverSvgButton extends StatefulWidget {
  final String svgPath;
  final double width;
  final double height;
  final VoidCallback onTap;

  const HoverSvgButton({
    super.key,
    required this.svgPath,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<HoverSvgButton> createState() => _HoverSvgButtonState();
}

class _HoverSvgButtonState extends State<HoverSvgButton> {
  bool _isHovered = false;
  String? _svgString;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSvg();
  }

  @override
  void didUpdateWidget(HoverSvgButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgPath != widget.svgPath) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    try {
      final data = await DefaultAssetBundle.of(context).loadString(widget.svgPath);
      if (mounted) {
        setState(() {
          _svgString = data;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_svgString == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }
    String finalSvg = _svgString!;
    if (_isHovered) {
      finalSvg = finalSvg
          .replaceAll('fill:#636363', 'fill:#TEMP_WHITE_SVG')
          .replaceAll('fill:#ffffff', 'fill:#636363')
          .replaceAll('fill:#TEMP_WHITE_SVG', 'fill:#ffffff');
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: SvgPicture.string(
            finalSvg,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}