import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';
import 'item_description_dialog.dart';

class ItemTrackAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String itemId;

  ItemTrackAnim(
      {required this.controller,
      required this.curveAnim,
      required this.itemId});
}

class SynthesisGrid extends StatefulWidget {
  final List<RecipeIO> items;
  final bool isInput;
  final DataLoader dataLoader;
  final PlacedBuilding placedBuilding;
  final List<ConveyorBelt> conveyors;
  final bool isLiquidMode;
  final bool isDropTarget;
  final bool isDropHovered;
  final bool enableDrag;
  final InventoryDragData? dragData;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;
  final ValueChanged<InventoryDragData>? onDropAccept;
  final ValueChanged<bool>? onDropHoverChanged;

  const SynthesisGrid({
    required this.items,
    required this.isInput,
    required this.dataLoader,
    required this.placedBuilding,
    required this.conveyors,
    this.isLiquidMode = false,
    this.isDropTarget = false,
    this.isDropHovered = false,
    this.enableDrag = false,
    this.dragData,
    this.onDragStarted,
    this.onDragEnd,
    this.onDropAccept,
    this.onDropHoverChanged,
  });

  @override
  State<SynthesisGrid> createState() => SynthesisGridState();
}

class SynthesisGridState extends State<SynthesisGrid>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _rippleController;
  late AnimationController _longPressController;
  int _previousCount = -1;
  DateTime? _lastCountChangeTime;
  final List<ItemTrackAnim> _itemAnims = [];
  // 网格背景 SVG 缓存：仅在 level 变化时重新生成，避免每次 build 重新解析
  SvgPicture? _cachedGridSvg;
  SvgPicture? _cachedHoveredGridSvg;
  int? _cachedGridLevel = -999;
  bool _hovering = false;
  // 长按进度动画
  bool _isLongPressing = false;
  bool _dragStarted = false;
  Timer? _longPressDelayTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _longPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _longPressDelayTimer?.cancel();
    _animationController.dispose();
    _rippleController.dispose();
    _longPressController.dispose();
    for (final anim in _itemAnims) {
      anim.controller.dispose();
    }
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enableDrag) return;
    _dragStarted = false;
    // 延迟150ms后启动圆形动画，快速点击不会触发
    _longPressDelayTimer?.cancel();
    _longPressDelayTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _isLongPressing = true;
      _longPressController.forward(from: 0);
      setState(() {});
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressDelayTimer?.cancel();
    if (!_isLongPressing) return;
    _isLongPressing = false;
    _longPressController.reverse();
    setState(() {});
  }

  void _onDragStarted() {
    _dragStarted = true;
    _isLongPressing = false;
    // 拖拽开始后立即重置圆形动画，不播放回退
    _longPressController.value = 0;
    setState(() {});
    widget.onDragStarted?.call();
  }

  String _getGridSvg(int? level, {bool isHovered = false}) {
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
    final stopColor = isHovered ? '#252525' : '#696969';

    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">'
        '<stop offset="0" stop-color="$stopColor"/>'
        '<stop offset="0.7" stop-color="$stopColor"/>'
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
                      filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                      isAntiAlias: true,
                      errorBuilder: (_, __, ___) =>
                          _buildItemPlaceholder(dataItem),
                    )
                  : _buildItemPlaceholder(dataItem),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventoryItemId =
        widget.isInput ? widget.placedBuilding.inputItemId : null;
    final inventoryCount =
        widget.isInput ? widget.placedBuilding.inputItemCount : 0;
    final item = widget.items.isNotEmpty ? widget.items.first : null;
    // 输出侧使用输出库存
    final outputItemId = !widget.isInput ? item?.itemId : null;
    final outputCount = !widget.isInput && outputItemId != null
        ? (widget.placedBuilding.outputItems[outputItemId] ?? 0)
        : 0;
    final dataItem = widget.isInput
        ? (inventoryItemId != null && inventoryItemId.isNotEmpty
            ? widget.dataLoader.getItem(inventoryItemId)
            : (item != null
                ? widget.dataLoader.getItem(item.itemId)
                : null))
        : (outputItemId != null
            ? widget.dataLoader.getItem(outputItemId)
            : null);
    final level = dataItem?.level;
    // 仅在 level 变化时重新生成 SVG，避免每次 build 重新解析
    if (level != _cachedGridLevel) {
      _cachedGridLevel = level;
      _cachedGridSvg = SvgPicture.string(_getGridSvg(level), fit: BoxFit.fill);
      _cachedHoveredGridSvg =
          SvgPicture.string(_getGridSvg(level, isHovered: true), fit: BoxFit.fill);
    }
    final totalAmount = widget.isInput ? inventoryCount : outputCount;

    final solidPorts = (widget.isInput
            ? widget.placedBuilding.inputPorts
            : widget.placedBuilding.outputPorts)
        .where((p) => p.definition.portType == 'solid')
        .toList();

    // 检查是否有已连接的传送带端口
    final portConnections =
        widget.placedBuilding.conveyorPortConnections(widget.conveyors);
    final hasConnectedPort =
        solidPorts.any((p) => portConnections['${p.type}_${p.index}'] == true);

    // 检测数量变化，创建物品动画（仅在有连接的传送带时）
    final currentCount = widget.isInput ? inventoryCount : outputCount;
    if (_previousCount >= 0 &&
        currentCount > _previousCount &&
        hasConnectedPort) {
      final delta = currentCount - _previousCount;
      final animItemId =
          widget.isInput ? (inventoryItemId ?? '') : (outputItemId ?? '');
      _previousCount = currentCount;
      if (animItemId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _createItemAnimations(delta, animItemId);
        });
      }
    } else {
      _previousCount = currentCount;
    }

    // 直接显示实际数量
    final displayCount = totalAmount;

    // 提取网格内部内容
    final gridStack = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.antiAlias,
      children: [
        _hovering && _cachedHoveredGridSvg != null
            ? _cachedHoveredGridSvg!
            : _cachedGridSvg!,
        if (dataItem != null && dataItem.imageAssetPath.isNotEmpty)
          Center(
            child: AnimatedScale(
              scale: _hovering ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AnimatedOpacity(
                opacity: totalAmount == 0
                    ? 0.3
                    : totalAmount == 1
                        ? 0.5
                        : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Image.asset(
                  dataItem.imageAssetPath,
                  width: 128,
                  height: 128,
                  cacheWidth: 384,
                  cacheHeight: 384,
                  fit: BoxFit.contain,
                  filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                  isAntiAlias: true,
                  errorBuilder: (_, __, ___) => _buildItemPlaceholder(dataItem),
                ),
              ),
            ),
          )
        else if (dataItem != null)
          Center(child: _buildItemPlaceholder(dataItem)),
        if (_hovering && dataItem != null)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey[900]?.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dataItem.name,
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
        if (widget.isDropTarget)
          IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.white.withValues(alpha: 0.5),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 涟漪动画（位于图标下方）
                      AnimatedBuilder(
                        animation: _rippleController,
                        builder: (context, _) {
                          final progress = _rippleController.value;
                          return CustomPaint(
                            size: const Size(120, 120),
                            painter: _RipplePainter(
                              progress: progress,
                              color: const Color(0xFF666666),
                            ),
                          );
                        },
                      ),
                      // add.svg 图标（旋转+放大+颜色渐变）
                      AnimatedRotation(
                        turns: widget.isDropHovered ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: AnimatedScale(
                          scale: widget.isDropHovered ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: TweenAnimationBuilder<Color?>(
                            tween: ColorTween(
                              begin: const Color(0xFF555555),
                              end: widget.isDropHovered
                                  ? const Color(0xFF222222)
                                  : const Color(0xFF555555),
                            ),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            builder: (context, color, child) {
                              return SvgPicture.asset(
                                'assets/svg/add.svg',
                                width: 40,
                                height: 40,
                                colorFilter: ColorFilter.mode(
                                  color!,
                                  BlendMode.srcIn,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // 文字（向下移动+淡出动画）
                      Positioned(
                        bottom: 12,
                        child: AnimatedSlide(
                          offset: widget.isDropHovered
                              ? const Offset(0, 0.8)
                              : Offset.zero,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: AnimatedOpacity(
                            opacity: widget.isDropHovered ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: const Text(
                              '拖到此处输入',
                              style: TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 13,
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
            ),
          ),
      ],
    );

    // 根据是否启用拖拽，包装手势处理器
    Widget gestureChild;
    if (widget.enableDrag && widget.dragData != null) {
      // LongPressDraggable 不处理 onTap，需要用 GestureDetector 包裹 child
      final clickableGridStack = GestureDetector(
        onTap: dataItem != null
            ? () => ItemDescriptionDialog.show(context, item: dataItem)
            : null,
        behavior: HitTestBehavior.translucent,
        child: gridStack,
      );
      gestureChild = LongPressDraggable<InventoryDragData>(
        delay: const Duration(milliseconds: 450),
        data: widget.dragData!,
        feedback: _buildDragFeedback(dataItem),
        childWhenDragging: Opacity(opacity: 0.3, child: gridStack),
        child: clickableGridStack,
        onDragStarted: _onDragStarted,
        onDragEnd: (_) {
          _dragStarted = false;
          _longPressController.value = 0;
          widget.onDragEnd?.call();
        },
      );
    } else {
      gestureChild = GestureDetector(
        onTap: dataItem != null
            ? () => ItemDescriptionDialog.show(context, item: dataItem)
            : null,
        behavior: HitTestBehavior.opaque,
        child: gridStack,
      );
    }

    final gridBoxRaw = Container(
      width: 128,
      height: 128,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: (_) => _onPointerUp(PointerUpEvent()),
        child: MouseRegion(
          cursor: dataItem != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: dataItem != null ? (_) => setState(() => _hovering = true) : null,
          onExit: (_) => setState(() => _hovering = false),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.antiAlias,
            children: [
              gestureChild,
              // 长按圆形填充动画
              if (_isLongPressing || _dragStarted)
                IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _longPressController,
                      builder: (context, _) {
                        final progress = _longPressController.value;
                        final opacity = _dragStarted ? (1.0 - progress) : 1.0;
                        return Opacity(
                          opacity: opacity,
                          child: CustomPaint(
                            size: const Size(70, 70),
                            painter: _CircularProgressPainter(
                              progress: progress,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // 当作为拖放目标时，用 DragTarget 包裹 gridBox（仅 128x128 区域）
    final gridBox = widget.isDropTarget
        ? DragTarget<InventoryDragData>(
            builder: (context, candidate, rejected) => gridBoxRaw,
            onWillAcceptWithDetails: (details) {
              if (details.data.source == InventoryDragSource.itemPanel) {
                widget.onDropHoverChanged?.call(true);
                return true;
              }
              return false;
            },
            onLeave: (_) => widget.onDropHoverChanged?.call(false),
            onAcceptWithDetails: (details) {
              widget.onDropHoverChanged?.call(false);
              widget.onDropAccept?.call(details.data);
            },
          )
        : gridBoxRaw;

    final double connectorHeight =
        solidPorts.isNotEmpty ? (solidPorts.length * 62.0) : 0.0;

    final double defaultGridBoxH = 128.0;
    final double defaultRowH =
        connectorHeight > defaultGridBoxH ? connectorHeight : defaultGridBoxH;
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

    final double leftSizedBoxWidth =
        (widget.isInput && solidPorts.isNotEmpty) ? 288.0 : 0.0;
    final double rightSizedBoxWidth =
        (!widget.isInput && solidPorts.isNotEmpty) ? 288.0 : 0.0;
    final double gridBoxWidth = 128.0;
    final double totalWidth =
        leftSizedBoxWidth + gridBoxWidth + rightSizedBoxWidth;

    // Center of the gridBox horizontally
    final double gridBoxX = leftSizedBoxWidth;
    final double gridBoxCenterX = gridBoxX + gridBoxWidth / 2.0;

    // Calculate liquidBox X offset so its output/input "droplet" aligns with gridBox center
    final double liquidCx = (widget.isInput ? 221.0 : 45.7) * liquidScale;
    final double liquidBoxX = gridBoxCenterX - liquidCx;

    // 数量文本位于网格下方
    final double countY = finalGridBoxY + defaultGridBoxH + 6;
    final double newHeight = math.max(finalHeight, countY + 24);

    // 构建物品动画 widgets（坐标相对于轨道连接器）
    final List<Widget> itemAnimWidgets = _buildItemAnimWidgets(
      solidPorts: solidPorts,
    );

    return SizedBox(
      width: totalWidth,
      height: newHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.isLiquidMode)
            Positioned(
              left: liquidBoxX,
              top: finalLiquidY,
              child: _buildLiquidUnit(dataItem, liquidScale),
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
              child: TrackJointsConnector(
                ports: solidPorts,
                conveyors: widget.conveyors,
                isInput: true,
                placedBuilding: widget.placedBuilding,
                offsetY: finalOffsetY,
                itemAnimChildren: itemAnimWidgets,
              ),
            ),
          if (!widget.isInput && solidPorts.isNotEmpty)
            Positioned(
              right: 0,
              top: (defaultRowH - connectorHeight) / 2.0,
              child: TrackJointsConnector(
                ports: solidPorts,
                conveyors: widget.conveyors,
                isInput: false,
                placedBuilding: widget.placedBuilding,
                offsetY: finalOffsetY,
                itemAnimChildren: itemAnimWidgets,
              ),
            ),
          // 数量文本位于网格正下方
          Positioned(
            left: gridBoxX,
            top: countY,
            width: gridBoxWidth,
            child: Center(
              child: Text(
                '$displayCount',
                style: TextStyle(
                  color: ((widget.isInput &&
                              inventoryCount >=
                                  PlacedBuilding.maxInputItemCount) ||
                          (!widget.isInput &&
                              outputCount >= PlacedBuilding.maxOutputItemCount))
                      ? const Color(0xFFFF4444)
                      : const Color(0xFFDDDDDD),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _createItemAnimations(int delta, String itemId) {
    final now = DateTime.now();
    int durationMs = 1500;
    if (_lastCountChangeTime != null) {
      final interval = now.difference(_lastCountChangeTime!).inMilliseconds;
      if (interval > 0) {
        durationMs = interval.clamp(300, 5000);
      }
    }
    _lastCountChangeTime = now;

    for (int i = 0; i < delta; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: durationMs),
      );
      final curveAnim = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOutCubic,
      );
      final anim = ItemTrackAnim(
          controller: controller, curveAnim: curveAnim, itemId: itemId);
      _itemAnims.add(anim);
      controller.forward().then((_) {
        if (mounted) {
          _itemAnims.remove(anim);
          controller.dispose();
        }
      });
    }
  }

  List<Widget> _buildItemAnimWidgets({
    required List<PortState> solidPorts,
  }) {
    if (solidPorts.isEmpty || _itemAnims.isEmpty) return [];

    // 找到第一个已连接的端口
    final connections =
        widget.placedBuilding.conveyorPortConnections(widget.conveyors);
    int? connectedPortIndex;
    for (int i = 0; i < solidPorts.length; i++) {
      if (connections['${solidPorts[i].type}_${solidPorts[i].index}'] == true) {
        connectedPortIndex = i;
        break;
      }
    }

    if (connectedPortIndex == null) return [];

    const double itemSize = 40.0;
    const double trackActiveWidth = 168.0;
    const double trackHeight = 54.0;
    // 物品从轨道外左侧进入的距离
    const double entryOffset = itemSize;

    // 坐标相对于轨道连接器
    final double portCenterY = connectedPortIndex * 62.0 + 31.0;
    final double y = portCenterY - trackHeight / 2.0;

    // 输入：轨道从左侧开始(x=0)，渐变从透明→不透明
    // 输出：轨道从右侧开始(x=288-168=120)，渐变从不透明→透明
    final double trackStartX =
        widget.isInput ? 0.0 : (288.0 - trackActiveWidth);

    // 完整移动路径：从轨道外(entryOffset) 到轨道右边缘(trackActiveWidth)
    final double totalTravel = trackActiveWidth + entryOffset;

    // 渐变遮罩：与轨道 painter 中的渐变方向一致
    // shader 区域限定为轨道矩形（不含外部进入段）
    final trackGradient = widget.isInput
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
          )
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          );

    // 轨道矩形在 ShaderMask 坐标系中的位置（ShaderMask 左边缘 = trackStartX - entryOffset）
    final trackRectInMask = Rect.fromLTWH(
      entryOffset, 0, trackActiveWidth, trackHeight,
    );

    final List<Widget> widgets = [];
    for (final anim in _itemAnims) {
      final dataItem = widget.dataLoader.getItem(anim.itemId);
      if (dataItem == null) continue;

      final double itemY = portCenterY - itemSize / 2;

      widgets.add(
        Positioned(
          // 裁剪区域：从轨道外左侧到轨道右边缘，覆盖完整移动路径
          left: trackStartX - entryOffset,
          top: y,
          width: totalTravel,
          height: trackHeight,
          child: ClipRect(
            child: ShaderMask(
              // 渐变只作用于轨道区域（不含外部进入段）
              shaderCallback: (_) => trackGradient.createShader(trackRectInMask),
              child: AnimatedBuilder(
                animation: anim.curveAnim,
                builder: (context, child) {
                  // 从轨道外左侧(-entryOffset) 移动到轨道右边缘(trackActiveWidth)
                  final double x =
                      anim.curveAnim.value * totalTravel - entryOffset;
                  return Transform.translate(
                    offset: Offset(x, itemY - y),
                    child: child,
                  );
                },
                child: Opacity(
                  opacity: 0.9,
                  child: dataItem.imageAssetPath.isNotEmpty
                      ? Image.asset(
                          dataItem.imageAssetPath,
                          width: itemSize,
                          height: itemSize,
                          cacheWidth: 120,
                          cacheHeight: 120,
                          fit: BoxFit.contain,
                          filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                          isAntiAlias: true,
                          errorBuilder: (_, __, ___) =>
                              _buildItemPlaceholder(dataItem),
                        )
                      : _buildItemPlaceholder(dataItem),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
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

  /// 构建拖拽时跟随光标的反馈预览
  Widget _buildDragFeedback(Item? dataItem) {
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.85,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF373737),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: dataItem != null && dataItem.imageAssetPath.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    dataItem.imageAssetPath,
                    width: 68,
                    height: 68,
                    cacheWidth: 204,
                    cacheHeight: 204,
                    fit: BoxFit.contain,
                    filterQuality:
                        kIsWeb ? FilterQuality.high : FilterQuality.medium,
                    isAntiAlias: true,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class TrackJointsConnector extends StatefulWidget {
  final List<PortState> ports;
  final List<ConveyorBelt> conveyors;
  final bool isInput;
  final PlacedBuilding placedBuilding;
  final double offsetY;
  final List<Widget> itemAnimChildren;

  const TrackJointsConnector({
    required this.ports,
    required this.conveyors,
    required this.isInput,
    required this.placedBuilding,
    this.offsetY = 0.0,
    this.itemAnimChildren = const [],
  });

  @override
  State<TrackJointsConnector> createState() => TrackJointsConnectorState();
}

class TrackJointsConnectorState extends State<TrackJointsConnector>
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
    final connections =
        widget.placedBuilding.conveyorPortConnections(widget.conveyors);
    return connections['${port.type}_${port.index}'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final connections = widget.ports.map((p) => _isPortConnected(p)).toList();
    final int N = connections.length;
    final double height = N > 0 ? (N * 62.0) : 0;
    final double totalHeight = height > 0 ? height + widget.offsetY : 0;

    return SizedBox(
      width: 288,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                size: Size(288, totalHeight),
                painter: TrackJointsPainter(
                  connections: connections,
                  isInput: widget.isInput,
                  animationValue: _animationController.value,
                  offsetY: widget.offsetY,
                ),
              );
            },
          ),
          ...widget.itemAnimChildren,
        ],
      ),
    );
  }
}

class TrackJointsPainter extends CustomPainter {
  final List<bool> connections;
  final bool isInput;
  final double animationValue;
  final double offsetY;

  const TrackJointsPainter({
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
      canvas.drawRect(
          Rect.fromLTRB(207.5, 0, 212.5, backboneBottom), linkPaint);

      // Draw consolidated 'window_link' running from backbone to grid-box
      canvas.drawRect(
          Rect.fromLTRB(211.5, devCenterY - 3.3, size.width, devCenterY + 3.3),
          linkPaint);

      // Draw junction circle near grid-box
      canvas.drawCircle(Offset(size.width, devCenterY), 6.0, inputCirclePaint);

      for (int i = 0; i < N; i++) {
        final double centerY = i * blockHeight + blockHeight / 2.0;

        // Draw 'interface_link' block (overlaps to 174 and 209 to prevent anti-alias black line)
        canvas.drawRect(Rect.fromLTWH(174, centerY - 3.3, 35, 6.6), linkPaint);

        // Draw 'interface' block on top
        canvas.drawRect(
            Rect.fromLTWH(168, centerY - 27, 7, 54), interfacePaint);

        // Draw junction circle at interface link
        canvas.drawCircle(Offset(175, centerY), 6.0, inputCirclePaint);
      }
    } else {
      final double devCenterY = N * blockHeight / 2.0 + offsetY;
      final double backboneBottom = N * blockHeight > (devCenterY + 3.3)
          ? N * blockHeight
          : (devCenterY + 3.3);

      // Draw concatenated 'interface_link_separate' (vertical backbone)
      canvas.drawRect(
          Rect.fromLTRB(
              size.width - 212.5, 0, size.width - 207.5, backboneBottom),
          linkPaint);

      // Draw consolidated 'window_link' running from grid-box to backbone
      canvas.drawRect(
          Rect.fromLTRB(
              0, devCenterY - 3.3, size.width - 211.5, devCenterY + 3.3),
          linkPaint);

      // Draw junction circle near grid-box
      canvas.drawCircle(Offset(0, devCenterY), 6.0, outputCirclePaint);

      for (int i = 0; i < N; i++) {
        final double centerY = i * blockHeight + blockHeight / 2.0;

        // Draw 'interface_link' block
        canvas.drawRect(
            Rect.fromLTWH(size.width - 209, centerY - 3.3, 35, 6.6), linkPaint);

        // Draw 'interface' block
        canvas.drawRect(Rect.fromLTWH(size.width - 175, centerY - 27, 7, 54),
            interfacePaint);

        // Draw junction circle at interface link
        canvas.drawCircle(
            Offset(size.width - 175, centerY), 6.0, outputCirclePaint);
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
        canvas.drawLine(Offset(0, centerY - 27 + strokeHalf),
            Offset(168, centerY - 27 + strokeHalf), borderPaint);
        canvas.drawLine(Offset(0, centerY + 27 - strokeHalf),
            Offset(168, centerY + 27 - strokeHalf), borderPaint);

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
        final rect =
            Rect.fromLTRB(startX, centerY - 27, size.width, centerY + 27);

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
        canvas.drawLine(Offset(startX, centerY - 27 + strokeHalf),
            Offset(size.width, centerY - 27 + strokeHalf), borderPaint);
        canvas.drawLine(Offset(startX, centerY + 27 - strokeHalf),
            Offset(size.width, centerY + 27 - strokeHalf), borderPaint);

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
  bool shouldRepaint(covariant TrackJointsPainter oldDelegate) =>
      oldDelegate.connections != connections ||
      oldDelegate.isInput != isInput ||
      oldDelegate.animationValue != animationValue;
}

class InformationBackground extends StatelessWidget {
  final bool hideNo;
  final double width;
  final double height;

  const InformationBackground({
    required this.hideNo,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DefaultAssetBundle.of(context)
          .loadString('assets/svg/information_BG.svg'),
      builder: (context, snapshot) {
        var svg = snapshot.data;
        if (svg != null && hideNo) {
          svg = svg.replaceFirst(
            RegExp(r'<path[^>]*inkscape:label="NO"[^>]*/>'),
            '',
          );
        }

        if (svg == null) {
          return SizedBox(width: width, height: height);
        }

        return SvgPicture.string(
          svg,
          width: width,
          height: height,
          fit: BoxFit.fill,
        );
      },
    );
  }
}

class CollectAllButton extends StatefulWidget {
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool enabled;

  const CollectAllButton({
    required this.width,
    required this.height,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<CollectAllButton> createState() => CollectAllButtonState();
}

class CollectAllButtonState extends State<CollectAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final textColor = enabled
        ? const Color(0xFF222222)
        : const Color(0xFF666666);
    return GestureDetector(
      onTap: enabled ? widget.onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedScale(
          scale: enabled && _hovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter: !enabled
                      ? const ColorFilter.mode(
                          Color(0xFF373737), BlendMode.srcIn)
                      : _hovered
                          ? const ColorFilter.mode(
                              Color(0xFFEBAD26), BlendMode.srcIn)
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.srcOver),
                  child: SvgPicture.asset(
                    'assets/svg/Collect_button.svg',
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: 82,
                  right: 48,
                  top: 6,
                  bottom: 14,
                  child: Center(
                    child: Text(
                      '全部收取',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽目标区域的涟漪动画画笔
class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RipplePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 绘制两个交错的实心涟漪
    for (int i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final radius = t * maxRadius;
      final opacity = (1.0 - t) * 0.3;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 长按圆形填充动画画笔
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sweepAngle = progress * 2 * 3.14159265;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159265 / 2, // 从顶部开始
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
