import 'package:flutter/material.dart';
import '../models/building.dart';
import '../data/data_loader.dart';

class EquipmentDock extends StatefulWidget {
  final DataLoader dataLoader;
  final Building? selectedBuilding;
  final ValueChanged<Building?> onBuildingSelected;

  const EquipmentDock({
    super.key,
    required this.dataLoader,
    this.selectedBuilding,
    required this.onBuildingSelected,
  });

  @override
  State<EquipmentDock> createState() => _EquipmentDockState();
}

class _EquipmentDockState extends State<EquipmentDock>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  static const List<String> _dockOrder = [
    'refining_unit_3x3',
    'shredder_3x3',
    'furnace_3x3',
    'assembler_4x4',
    'depot_loader_3x1',
    'depot_unloader_3x1',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    _animationController.value = 1.0;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _selectBuilding(Building? building) {
    widget.onBuildingSelected(building);
  }

  @override
  Widget build(BuildContext context) {
    final buildings = _dockOrder
        .map((id) => widget.dataLoader.getBuilding(id))
        .whereType<Building>()
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggleExpand,
          child: Container(
            width: 40,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF555555)),
            ),
            child: Icon(
              _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 14,
              color: const Color(0xFFAAAAAA),
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                heightFactor: _slideAnimation.value,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: Opacity(
            opacity: _isExpanded ? 1.0 : 0.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xE62A2A2A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF444444)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(10, (index) {
                  final building =
                      index < buildings.length ? buildings[index] : null;
                  final keyLabel = index == 9 ? '0' : '${index + 1}';
                  final isSelected = building != null &&
                      widget.selectedBuilding?.id == building.id;

                  return _DockSlot(
                    keyLabel: keyLabel,
                    building: building,
                    isSelected: isSelected,
                    onTap: () => _selectBuilding(
                        isSelected ? null : building),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DockSlot extends StatelessWidget {
  final String keyLabel;
  final Building? building;
  final bool isSelected;
  final VoidCallback onTap;

  const _DockSlot({
    required this.keyLabel,
    this.building,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBuilding = building != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: hasBuilding ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hasBuilding
                    ? (isSelected
                        ? building!.color.withValues(alpha: 0.35)
                        : const Color(0xFF222222))
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasBuilding
                      ? (isSelected
                          ? building!.color
                          : const Color(0xFF444444))
                      : const Color(0xFF2A2A2A),
                  width: isSelected ? 1.8 : 1.0,
                ),
              ),
              child: hasBuilding
                  ? Tooltip(
                      message: building!.name,
                      preferBelow: true,
                      child: Center(
                        child: Text(
                          building!.name.length > 4
                              ? building!.name.substring(0, 4)
                              : building!.name,
                          style: TextStyle(
                            color: isSelected
                                ? building!.color
                                : const Color(0xFFBBBBBB),
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: const Color(0xFF444444),
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 22,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFFCC00)
                      : const Color(0xFF555555),
                ),
              ),
              child: Center(
                child: Text(
                  keyLabel,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFFFFCC00)
                        : const Color(0xFF888888),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
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
