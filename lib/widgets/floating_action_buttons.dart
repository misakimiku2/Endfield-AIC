import 'package:flutter/material.dart';

class FloatingActionButtons extends StatelessWidget {
  final bool conveyorMode;
  final VoidCallback onConveyorToggle;
  final VoidCallback onRotateCanvas;

  const FloatingActionButtons({
    super.key,
    required this.conveyorMode,
    required this.onConveyorToggle,
    required this.onRotateCanvas,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 124),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FloatingButton(
            icon: Icons.cable,
            isActive: conveyorMode,
            activeColor: const Color(0xFF4488FF),
            inactiveColor: const Color(0xFF666666),
            keyLabel: 'E',
            tooltip: '传送带模式 (E)',
            onTap: onConveyorToggle,
          ),
          const SizedBox(height: 12),
          _FloatingButton(
            icon: Icons.rotate_90_degrees_cw_outlined,
            isActive: false,
            activeColor: const Color(0xFFFFCC00),
            inactiveColor: const Color(0xFF666666),
            keyLabel: 'R',
            tooltip: '旋转画布 (Ctrl+R)',
            onTap: onRotateCanvas,
          ),
        ],
      ),
    );
  }
}

class _FloatingButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String keyLabel;
  final String tooltip;
  final VoidCallback onTap;

  const _FloatingButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.keyLabel,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? activeColor.withValues(alpha: 0.2)
                    : const Color(0xE62A2A2A),
                border: Border.all(
                  color: isActive ? activeColor : const Color(0xFF555555),
                  width: isActive ? 2.0 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 20,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 26,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isActive
                      ? activeColor.withValues(alpha: 0.5)
                      : const Color(0xFF555555),
                ),
              ),
              child: Center(
                child: Text(
                  keyLabel,
                  style: TextStyle(
                    color: isActive ? activeColor : const Color(0xFF888888),
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
