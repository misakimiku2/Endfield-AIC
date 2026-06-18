import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';
import 'depot_grid_tile.dart';

class DepotLoaderPanel extends StatelessWidget {
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  static void _noop() {}

  const DepotLoaderPanel({
    super.key,
    this.onMove,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
                onMove?.call();
              },
            ),
            const SizedBox(width: 30),
            ActionButton(
              svgPath: 'assets/svg/recycle.svg',
              label: '收纳',
              onTap: () {
                Navigator.of(context).pop();
                onDelete?.call();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Expanded(
          child: Center(
            child: DepotGridTile(
              item: null,
              isInput: true,
              showNoIcon: true,
              hasItemForButton: false,
              isAddMode: false,
              onToggleAddMode: _noop,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class DepotUnloaderPanel extends StatelessWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
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
    this.onMove,
    this.onDelete,
    this.onOutputItemSelected,
    required this.isAddMode,
    required this.selectedOutputItemId,
    required this.onToggleAddMode,
  });

  @override
  Widget build(BuildContext context) {
    final selectedItem = selectedOutputItemId != null
        ? dataLoader.getItem(selectedOutputItemId!)
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
                onMove?.call();
              },
            ),
            const SizedBox(width: 30),
            ActionButton(
              svgPath: 'assets/svg/recycle.svg',
              label: '收纳',
              onTap: () {
                Navigator.of(context).pop();
                onDelete?.call();
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
              hasItemForButton: selectedOutputItemId != null,
              isAddMode: isAddMode,
              onToggleAddMode: onToggleAddMode,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
