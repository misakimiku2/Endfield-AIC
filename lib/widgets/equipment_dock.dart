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
  late AnimationController _animController;
  late Animation<double> _dockSlide;

  static const double _sideMargin = 80.0;

  static const List<String> _dockOrder = [
    'refining_unit_3x3',
    'depot_loader_3x1',
    'depot_unloader_3x1',
    'belt_bridge_1x1',
    'splitter_1x1',
    'converger_1x1',
    'item_control_port_1x1',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _dockSlide = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
    _animController.value = 1.0;
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dockWidth = screenWidth - _sideMargin * 2;
    final buildings = _dockOrder
        .map((id) => widget.dataLoader.getBuilding(id))
        .whereType<Building>()
        .toList();

    return SizedBox(
      width: dockWidth,
      height: 112, // 容器高度：容纳 100px 高度的 Dock 栏与 12px 悬浮间距
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final slide = _dockSlide.value;

          // Dock 栏滑动及淡入淡出动画数值计算
          // 展开状态：bottom = 12 (完美悬浮高度)
          // 收起状态：bottom = -120 (完全移出底部)
          final dockBottom = -120.0 + (12.0 - (-120.0)) * slide;
          final dockOpacity = slide.clamp(0.0, 1.0);

          // 展开按钮滑动及淡入淡出动画数值计算
          // 展开状态：bottom = -80 (完全潜入屏幕下方隐藏)
          // 收起状态：bottom = 0 (正好贴齐底部状态栏)
          final expandBottom = -80.0 + (0.0 - (-80.0)) * (1.0 - slide);
          final expandOpacity = (1.0 - slide).clamp(0.0, 1.0);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 收起状态下的展开按钮
              if (expandOpacity > 0.0)
                Positioned(
                  left: 0,
                  bottom: expandBottom,
                  child: Opacity(
                    opacity: expandOpacity,
                    child: _ExpandButton(onTap: _toggle),
                  ),
                ),

              // 展开状态下的 Dock 栏主体
              if (dockOpacity > 0.0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: dockBottom,
                  child: Opacity(
                    opacity: dockOpacity,
                    child: _DockBarBody(
                      dockWidth: dockWidth,
                      buildings: buildings,
                      selectedBuilding: widget.selectedBuilding,
                      isExpanded: _isExpanded,
                      onCollapse: _toggle,
                      onBuildingSelected: (b) {
                        widget.onBuildingSelected(b);
                      },
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

class _DockBarBody extends StatelessWidget {
  final double dockWidth;
  final List<Building> buildings;
  final Building? selectedBuilding;
  final bool isExpanded;
  final VoidCallback onCollapse;
  final ValueChanged<Building?> onBuildingSelected;

  const _DockBarBody({
    required this.dockWidth,
    required this.buildings,
    this.selectedBuilding,
    required this.isExpanded,
    required this.onCollapse,
    required this.onBuildingSelected,
  });

  @override
  Widget build(BuildContext context) {
    const double capWidth = 66.0;
    const double gap = 5.0;
    final double middleWidth = dockWidth - (capWidth * 2) - (gap * 2);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 左半圆：收起按钮
        _CollapseButton(
          isExpanded: isExpanded,
          onTap: onCollapse,
          width: capWidth,
        ),
        const SizedBox(width: gap),
        // 中间：设备插槽主栏
        Container(
          width: middleWidth,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xE62A2A2A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF444444), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(10, (index) {
              final building =
                  index < buildings.length ? buildings[index] : null;
              final keyLabel = index == 9 ? '0' : '${index + 1}';
              final isSelected =
                  building != null && selectedBuilding?.id == building.id;
              return Flexible(
                flex: 1,
                child: _DeviceSlot(
                  keyLabel: keyLabel,
                  building: building,
                  isSelected: isSelected,
                  onTap: () => onBuildingSelected(isSelected ? null : building),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: gap),
        // 右半圆：纯装饰用的对称Cap
        const _DecorativeCap(width: capWidth),
      ],
    );
  }
}

class _CollapseButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;
  final double width;

  const _CollapseButton({
    required this.isExpanded,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xE62A2A2A),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(50),
            bottomLeft: Radius.circular(50),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: const Color(0xFF444444), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 24,
            color: Color(0xFFAAAAAA),
          ),
        ),
      ),
    );
  }
}

class _DecorativeCap extends StatelessWidget {
  final double width;

  const _DecorativeCap({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xE62A2A2A),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(50),
          bottomRight: Radius.circular(50),
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
        border: Border.all(color: const Color(0xFF444444), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF555555),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ExpandButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 66,
        height: 112,
        decoration: const BoxDecoration(
          color: Color(0xE62A2A2A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(33),
            topRight: Radius.circular(33),
          ),
          border: Border(
            top: BorderSide(color: Color(0xFF444444), width: 1.2),
            left: BorderSide(color: Color(0xFF444444), width: 1.2),
            right: BorderSide(color: Color(0xFF444444), width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 12,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: const Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 50,
              child: Center(
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 24,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSlot extends StatelessWidget {
  final String keyLabel;
  final Building? building;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeviceSlot({
    required this.keyLabel,
    this.building,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBuilding = building != null;
    return Tooltip(
      message: hasBuilding ? building!.name : '未解锁',
      preferBelow: false,
      child: GestureDetector(
        onTap: hasBuilding ? onTap : null,
        child: Container(
          height: 68,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: hasBuilding
                ? (isSelected
                    ? building!.color.withValues(alpha: 0.25)
                    : const Color(0xFF222222))
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasBuilding
                  ? (isSelected ? building!.color : const Color(0xFF3A3A3A))
                  : const Color(0xFF252525),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: hasBuilding
              ? Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: building!.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: building!.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          keyLabel,
                          style: TextStyle(
                            color: isSelected
                                ? building!.color
                                : building!.color.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        building!.name,
                        style: TextStyle(
                          color: isSelected
                              ? building!.color
                              : const Color(0xFFCCCCCC),
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Color(0xFF444444),
                  ),
                ),
        ),
      ),
    );
  }
}
