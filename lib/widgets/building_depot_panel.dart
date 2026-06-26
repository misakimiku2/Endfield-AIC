import 'dart:async';

import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../constants/app_constants.dart';
import 'building_shared_widgets.dart';
import 'depot_grid_tile.dart';

/// 仓库存货口面板（仅显示，无交互按钮）
class DepotLoaderPanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final ProjectState project;
  final DataLoader dataLoader;
  final List<ConveyorBelt> conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const DepotLoaderPanel({
    super.key,
    required this.placedBuilding,
    required this.project,
    required this.dataLoader,
    required this.conveyors,
    this.onMove,
    this.onDelete,
  });

  @override
  State<DepotLoaderPanel> createState() => _DepotLoaderPanelState();
}

class _DepotLoaderPanelState extends State<DepotLoaderPanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 100ms 定时器刷新，确保仓库数量和物品显示实时更新
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 查找连接到仓库存货口输入端口的传送带上的所有不同物品ID
  /// 返回 (所有不同物品ID列表, 当前正在进入的物品ID)
  (List<String>, String?) _detectAllIncomingItemIds() {
    final pb = widget.placedBuilding;
    const cellSize = AppConstants.cellSize;
    const threshold = AppConstants.portConnectionThreshold;

    final allItemIds = <String>{};
    String? currentIncomingId;

    for (final port in pb.inputPorts) {
      final portWorld = port.worldPosition(
        pb.gridX,
        pb.gridY,
        cellSize,
        pb.building.gridWidth,
        pb.building.gridHeight,
        rotation: pb.rotation,
      );
      for (final belt in widget.conveyors) {
        if (belt.path.length < 2) continue;
        // 输入端口连接传送带的终点
        if ((belt.end - portWorld).distance < threshold) {
          // 收集传送带上所有的不同物品类型
          for (final seg in belt.itemSegments) {
            if (seg.itemId.isNotEmpty) {
              allItemIds.add(seg.itemId);
            }
          }
          // 当前正在进入仓库存货口的物品（传送带末端物品）
          // belt.itemId 是传送带起始端物品，应使用末端物品
          final downstreamId = belt.downstreamItemId();
          if (downstreamId != null && downstreamId.isNotEmpty) {
            currentIncomingId ??= downstreamId;
          }
        }
      }
    }
    // 排序保证卡片顺序稳定，不受 Set 迭代顺序影响
    final sortedIds = allItemIds.toList()..sort();
    return (sortedIds, currentIncomingId);
  }

  @override
  Widget build(BuildContext context) {
    // 检测传送带上的所有不同物品 + 当前正在进入的物品
    final (allItemIds, currentIncomingId) = _detectAllIncomingItemIds();

    // 构建物品条目列表
    final itemEntries = <DepotItemEntry>[];
    for (final itemId in allItemIds) {
      final item = widget.dataLoader.getItem(itemId);
      if (item != null) {
        final isActive = itemId == currentIncomingId;
        final quantity = widget.project.getWarehouseItemCount(itemId);
        itemEntries.add(DepotItemEntry(
          item: item,
          isActive: isActive,
          warehouseQuantity: quantity,
        ));
      }
    }

    // 兼容旧逻辑：取第一个物品用于单个仓库卡片
    final incomingItemId = currentIncomingId;
    final incomingItem = incomingItemId != null
        ? widget.dataLoader.getItem(incomingItemId)
        : null;
    final warehouseQuantity = incomingItemId != null
        ? widget.project.getWarehouseItemCount(incomingItemId)
        : null;

    return Column(
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
        const SizedBox(height: 20),
        Expanded(
          child: Center(
            child: itemEntries.isNotEmpty
                ? DepotGridTile(
                    allItems: itemEntries,
                    isInput: true,
                    showNoIcon: true,
                    showButton: false,
                    onToggleAddMode: () {},
                  )
                : DepotGridTile(
                    item: incomingItem,
                    isInput: true,
                    showNoIcon: true,
                    showButton: false,
                    warehouseQuantity: warehouseQuantity,
                    onToggleAddMode: () {},
                  ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// 仓库取货口面板（可选择输出物品）
class DepotUnloaderPanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final ProjectState project;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final ValueChanged<String?>? onOutputItemSelected;
  final bool isAddMode;
  final String? selectedOutputItemId;
  final VoidCallback onToggleAddMode;

  const DepotUnloaderPanel({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    required this.project,
    this.onMove,
    this.onDelete,
    this.onOutputItemSelected,
    required this.isAddMode,
    required this.selectedOutputItemId,
    required this.onToggleAddMode,
  });

  @override
  State<DepotUnloaderPanel> createState() => _DepotUnloaderPanelState();
}

class _DepotUnloaderPanelState extends State<DepotUnloaderPanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 100ms 定时器刷新，确保仓库数量实时更新
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = widget.selectedOutputItemId != null
        ? widget.dataLoader.getItem(widget.selectedOutputItemId!)
        : null;
    final warehouseQuantity = widget.selectedOutputItemId != null
        ? widget.project.getWarehouseItemCount(widget.selectedOutputItemId!)
        : null;

    return Column(
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
        const SizedBox(height: 20),
        Expanded(
          child: Center(
            child: DepotGridTile(
              item: selectedItem,
              isInput: false,
              showNoIcon: false,
              hasItemForButton: widget.selectedOutputItemId != null,
              isAddMode: widget.isAddMode,
              showButton: true,
              warehouseQuantity: warehouseQuantity,
              onToggleAddMode: widget.onToggleAddMode,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
