import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';
import 'processing_indicator.dart';
import 'synthesis_grid.dart';
import 'recipe_list_item.dart';

class DefaultSynthesisPanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final List<ConveyorBelt>? conveyors;
  final List<Recipe> recipes;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback? onInventoryChanged;

  const DefaultSynthesisPanel({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    required this.recipes,
    this.onMove,
    this.onDelete,
    this.onInventoryChanged,
  });

  @override
  State<DefaultSynthesisPanel> createState() => _DefaultSynthesisPanelState();
}

class _DefaultSynthesisPanelState extends State<DefaultSynthesisPanel> {
  bool _isLiquidMode = false;
  bool _isLiquidHover = false;
  Timer? _simTimer;
  // 液体开关 4 种状态预生成的 SVG 缓存，避免每次 build 重新解析
  SvgPicture? _liquidSwitchOn;
  SvgPicture? _liquidSwitchOnHover;
  SvgPicture? _liquidSwitchOff;
  SvgPicture? _liquidSwitchOffHover;

  Recipe? get _activeRecipe {
    if (widget.placedBuilding.activeRecipeId == null) return null;
    return widget.dataLoader.getRecipe(widget.placedBuilding.activeRecipeId!);
  }

  @override
  void initState() {
    super.initState();
    _loadLiquidSwitch();
    // 局部 100ms 定时器：仅刷新合成面板的生产进度/库存数量，
    // 不再波及左侧物品网格，保证滚动流畅。
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLiquidSwitch() async {
    try {
      final raw =
          await rootBundle.loadString('assets/svg/liquid_icon_switch.svg');
      if (mounted) {
        _liquidSwitchOn = SvgPicture.string(
          raw, width: 150, height: 43, fit: BoxFit.fill,
        );
        _liquidSwitchOnHover = SvgPicture.string(
          raw.replaceAll('#03a9ff', '#227aa8'),
          width: 150, height: 43, fit: BoxFit.fill,
        );
        _liquidSwitchOff = SvgPicture.string(
          raw.replaceAll('#03a9ff', '#b2b2b2'),
          width: 150, height: 43, fit: BoxFit.fill,
        );
        _liquidSwitchOffHover = SvgPicture.string(
          raw.replaceAll('#03a9ff', '#636363'),
          width: 150, height: 43, fit: BoxFit.fill,
        );
        setState(() {});
      }
    } catch (_) {}
  }

  Widget _buildLiquidModeSwitch() {
    final svg = _isLiquidMode
        ? (_isLiquidHover ? _liquidSwitchOnHover : _liquidSwitchOn)
        : (_isLiquidHover ? _liquidSwitchOffHover : _liquidSwitchOff);
    if (svg == null) {
      return const SizedBox.shrink();
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
              svg,
              Text(
                _isLiquidMode ? '液体模式' : '关闭模式',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 检测设备是否有连接的输出传送带
  bool _hasConnectedOutputBelt() {
    final conveyors = widget.conveyors;
    if (conveyors == null || conveyors.isEmpty) return false;
    final connections =
        widget.placedBuilding.conveyorPortConnections(conveyors);
    return widget.placedBuilding.outputPorts
        .any((p) => connections['output_${p.index}'] == true);
  }

  void _showRecipeListDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext dialogContext) {
        return RecipeListDialog(
          recipes: widget.recipes,
          placedBuilding: widget.placedBuilding,
          dataLoader: widget.dataLoader,
          onStateChanged: () {
            setState(() {});
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final solidInputPorts = widget.placedBuilding.inputPorts
        .where((p) => p.definition.portType == 'solid')
        .toList();
    final solidOutputPorts = widget.placedBuilding.outputPorts
        .where((p) => p.definition.portType == 'solid')
        .toList();
    final int maxPorts =
        math.max(solidInputPorts.length, solidOutputPorts.length);
    final double connectorHeight = maxPorts > 0 ? (maxPorts * 62.0) : 0.0;
    final double defaultGridBoxH = 128.0;
    final double defaultRowH =
        connectorHeight > defaultGridBoxH ? connectorHeight : defaultGridBoxH;
    final activeRecipe = _activeRecipe;
    final productionProgress =
        widget.placedBuilding.productionProgress.clamp(0.0, 1.0);
    final isInputFull =
        widget.placedBuilding.inputItemCount >=
            PlacedBuilding.maxInputItemCount;
    final isOutputFull =
        widget.placedBuilding.totalOutputCount >=
            PlacedBuilding.maxOutputItemCount;
    final isBlocked = isInputFull || isOutputFull;
    final isPaused = widget.placedBuilding.isPaused;
    final isProductionActive =
        activeRecipe != null && !isPaused && !isBlocked;
    final remainingSeconds = activeRecipe == null
        ? 0
        : (activeRecipe.processTimeSeconds * (1.0 - productionProgress))
            .ceil()
            .clamp(0, 999);
    final double productionRowH = defaultRowH + 74.0;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ActionButton(
                  svgPath: 'assets/svg/Move.svg',
                  label: '移动',
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onMove?.call();
                  },
                ),
                const SizedBox(width: 30),
                ActionButton(
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
                final double rowTop =
                    (containerH / 2.0) - (productionRowH / 2.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: rowTop,
                      left: 0,
                      right: 0,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SynthesisGrid(
                              items: _activeRecipe?.inputs ?? [],
                              isInput: true,
                              dataLoader: widget.dataLoader,
                              placedBuilding: widget.placedBuilding,
                              conveyors: widget.conveyors ?? [],
                              isLiquidMode: _isLiquidMode,
                            ),
                            const SizedBox(width: 11),
                            SizedBox(
                              width: 112,
                              height: productionRowH,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: defaultRowH,
                                    child: Center(
                                      child: isPaused
                                          ? PausedIndicator()
                                          : (isBlocked
                                              ? BlockedIndicator()
                                              : ProcessingIndicator(
                                                  isRunning: isProductionActive,
                                                )),
                                    ),
                                  ),
                                  Text(
                                    isProductionActive
                                        ? '${remainingSeconds.clamp(0, 999)}秒'
                                        : '',
                                    style: const TextStyle(
                                      color: Color(0xFFEDEDED),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  isPaused
                                      ? PausedProgressBar()
                                      : (isBlocked
                                          ? BlockedProgressBar()
                                          : ProductionProgressBar(
                                              progress: isProductionActive
                                                  ? productionProgress.toDouble()
                                                  : 0,
                                            )),
                                ],
                              ),
                            ),
                            const SizedBox(width: 11),
                            SynthesisGrid(
                              items: _activeRecipe?.outputs ?? [],
                              isInput: false,
                              dataLoader: widget.dataLoader,
                              placedBuilding: widget.placedBuilding,
                              conveyors: widget.conveyors ?? [],
                              isLiquidMode: _isLiquidMode,
                            ),
                          ],
                        ),
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
            final isProducing = _activeRecipe != null;
            // 当有连接的输出传送带时，物品会被自动传输走；
            // 只有物品堆积（>=2）时才启用按钮，避免单个物品被传输走时按钮闪烁。
            // 没有连接传送带时，只要有产出即可收取。
            final hasConnectedOutputBelt = _hasConnectedOutputBelt();
            final hasCollectableOutput = hasConnectedOutputBelt
                ? widget.placedBuilding.totalOutputCount >= 2
                : widget.placedBuilding.totalOutputCount > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Visibility(
                  visible: isProducing,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: const Padding(
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
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: SizedBox(
                      width: 800,
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
                              onTap: () => _showRecipeListDialog(),
                              child: InformationBackground(
                                hideNo: isProducing,
                                width: 348.16,
                                height: 76.8,
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
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          ...(_activeRecipe?.inputs
                                                  .map((inp) {
                                                final item = widget.dataLoader
                                                    .getItem(inp.itemId);
                                                if (item == null)
                                                  return const SizedBox
                                                      .shrink();
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4),
                                                  child: Image.asset(
                                                    item.imageAssetPath,
                                                    width: 56,
                                                    height: 56,
                                                    cacheWidth: 168,
                                                    cacheHeight: 168,
                                                    fit: BoxFit.contain,
                                                    filterQuality:
                                                        kIsWeb ? FilterQuality.high : FilterQuality.medium,
                                                    isAntiAlias: true,
                                                  ),
                                                );
                                              }) ??
                                              []),
                                          const SizedBox(width: 24),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const RecipeRunIndicator(),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_activeRecipe?.processTimeSeconds.toStringAsFixed(0)}秒',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 24),
                                          ...(_activeRecipe?.outputs
                                                  .map((out) {
                                                final item = widget.dataLoader
                                                    .getItem(out.itemId);
                                                if (item == null)
                                                  return const SizedBox
                                                      .shrink();
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4),
                                                  child: Image.asset(
                                                    item.imageAssetPath,
                                                    width: 56,
                                                    height: 56,
                                                    cacheWidth: 168,
                                                    cacheHeight: 168,
                                                    fit: BoxFit.contain,
                                                    filterQuality:
                                                        kIsWeb ? FilterQuality.high : FilterQuality.medium,
                                                    isAntiAlias: true,
                                                  ),
                                                );
                                              }) ??
                                              []),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
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
                            left: 326,
                            top: (76.8 - 43.52002) / 2,
                            child: HoverSvgButton(
                              svgPath: 'assets/svg/Recipe_button.svg',
                              width: 43.52002,
                              height: 43.52002,
                              onTap: () => _showRecipeListDialog(),
                            ),
                          ),
                          Positioned(
                            left: 448,
                            top: (76.8 - 30) / 2,
                            child: Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFF444444),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 524,
                            top: (76.8 - 87.59967 * 0.78) / 2,
                            child: CollectAllButton(
                              width: 300,
                              height: 68.32774,
                              enabled: hasCollectableOutput,
                              onTap: () {
                                setState(() {
                                  widget.placedBuilding.outputItems.clear();
                                });
                                widget.onInventoryChanged?.call();
                              },
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
}

class RecipeListDialog extends StatefulWidget {
  final List<Recipe> recipes;
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final VoidCallback onStateChanged;

  const RecipeListDialog({
    super.key,
    required this.recipes,
    required this.placedBuilding,
    required this.dataLoader,
    required this.onStateChanged,
  });

  @override
  State<RecipeListDialog> createState() => _RecipeListDialogState();
}

class _RecipeListDialogState extends State<RecipeListDialog> {
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
                  if (event is PointerScrollEvent &&
                      _scrollController.hasClients) {
                    final maxExtent =
                        _scrollController.position.maxScrollExtent;
                    final target =
                        (_scrollController.offset + event.scrollDelta.dy * 1.5)
                            .clamp(0.0, maxExtent);
                    _scrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: GridView.builder(
                    controller: _scrollController,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 3.5,
                    ),
                    itemCount: widget.recipes.length,
                    itemBuilder: (context, index) {
                      final recipe = widget.recipes[index];
                      final isPinned =
                          widget.placedBuilding.activeRecipeId == recipe.id;
                      return RecipeListItem(
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
