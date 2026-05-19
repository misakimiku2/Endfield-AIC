import 'package:flutter/material.dart';
import '../models/building.dart';
import '../data/data_loader.dart';

class BuildingPalette extends StatelessWidget {
  final DataLoader dataLoader;
  final String? selectedBuildingId;
  final ValueChanged<Building> onBuildingSelected;
  final VoidCallback onCancelPlacement;

  const BuildingPalette({
    super.key,
    required this.dataLoader,
    this.selectedBuildingId,
    required this.onBuildingSelected,
    required this.onCancelPlacement,
  });

  @override
  Widget build(BuildContext context) {
    final buildings = dataLoader.buildings.values.toList();

    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(right: BorderSide(color: Color(0xFF444444), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF444444), width: 1)),
            ),
            child: const Text(
              '设备列表',
              style: TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: buildings.length,
              itemBuilder: (context, index) {
                final building = buildings[index];
                final isSelected = selectedBuildingId == building.id;
                return _BuildingCard(
                  building: building,
                  isSelected: isSelected,
                  onTap: () {
                    if (isSelected) {
                      onCancelPlacement();
                    } else {
                      onBuildingSelected(building);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final Building building;
  final bool isSelected;
  final VoidCallback onTap;

  const _BuildingCard({
    required this.building,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? building.color.withValues(alpha: 0.2)
              : const Color(0xFF1E1E1E),
          border: Border.all(
            color: isSelected ? building.color : const Color(0xFF3A3A3A),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: building.color.withValues(alpha: 0.3),
                border: Border.all(
                  color: building.color.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  '${building.gridWidth}x${building.gridHeight}',
                  style: TextStyle(
                    color: building.color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    building.name,
                    style: const TextStyle(
                      color: Color(0xFFDDDDDD),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${building.category} · ${building.maxInputs}入${building.maxOutputs}出',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}