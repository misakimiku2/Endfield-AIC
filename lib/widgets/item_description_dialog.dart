import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/item.dart';
import 'building_shared_widgets.dart';

/// 物品说明弹窗 — 点击设备弹窗物品区域或传送带弹窗物品格时弹出。
/// 风格与项目其他弹窗一致：深色背景、圆角边框、背景花纹。
class ItemDescriptionDialog extends StatefulWidget {
  final Item item;

  const ItemDescriptionDialog({super.key, required this.item});

  static Future<void> show(BuildContext context, {required Item item}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => ItemDescriptionDialog(item: item),
    );
  }

  @override
  State<ItemDescriptionDialog> createState() => _ItemDescriptionDialogState();
}

class _ItemDescriptionDialogState extends State<ItemDescriptionDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDescription = item.description.isNotEmpty;
    final hasSecondary = item.secondaryDescription.isNotEmpty &&
        item.secondaryDescription != '-';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.center,
          child: Container(
            width: 460,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF444444)),
            ),
            child: Stack(
              children: [
                const DialogBackgroundPattern(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部栏：物品名称 + 关闭按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          HoverCloseButton(
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 分隔线
                      Container(
                        height: 1,
                        color: const Color(0xFF444444),
                      ),
                      const SizedBox(height: 28),
                      // 物品图片（原始图片，无网格背景）
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: item.imageAssetPath.isNotEmpty
                            ? Center(
                                child: Image.asset(
                                  item.imageAssetPath,
                                  width: 160,
                                  height: 160,
                                  cacheWidth: 480,
                                  cacheHeight: 480,
                                  fit: BoxFit.contain,
                                  filterQuality: kIsWeb
                                      ? FilterQuality.high
                                      : FilterQuality.medium,
                                  isAntiAlias: true,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color:
                                          item.color.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            item.color.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: item.color.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: item.color.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 28),
                      // 描述文字（白色）
                      if (hasDescription)
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.7,
                          ),
                        ),
                      if (hasDescription && hasSecondary)
                        const SizedBox(height: 12),
                      // 次要描述（浅灰色）
                      if (hasSecondary)
                        Text(
                          item.secondaryDescription,
                          style: const TextStyle(
                            color: Color(0xFF9A9A9A),
                            fontSize: 13,
                            height: 1.7,
                          ),
                        ),
                      if (!hasDescription && !hasSecondary)
                        const Text(
                          '暂无描述信息',
                          style: TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 14,
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
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
