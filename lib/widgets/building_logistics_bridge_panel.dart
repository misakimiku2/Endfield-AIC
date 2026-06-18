import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';

class _BridgeItemAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String? itemId;
  final int trackIndex;

  _BridgeItemAnim({
    required this.controller,
    required this.curveAnim,
    this.itemId,
    required this.trackIndex,
  });
}

enum _BridgeTrackType { a, b }

class LogisticsBridgePanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final List<ConveyorBelt>? conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const LogisticsBridgePanel({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    this.onMove,
    this.onDelete,
  });

  @override
  State<LogisticsBridgePanel> createState() => _LogisticsBridgePanelState();
}

class _LogisticsBridgePanelState extends State<LogisticsBridgePanel>
    with TickerProviderStateMixin {
  late AnimationController _arrowController;
  Timer? _spawnTimer;
  final List<_BridgeItemAnim> _itemAnims = [];
  int _spawnCounter = 0;

  static const double _trackLength = 480.0;
  static const double _trackWidth = 54.0;
  static const double _itemSize = 40.0;
  static const double _slotSize = 96.0;

  // 等轴测角度：X轴30°，Y轴150°，两轴夹角120°
  static const double _trackAngleA = math.pi / 6;
  static const double _trackAngleB = 5 * math.pi / 6;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _spawnTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _spawnItem();
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _arrowController.dispose();
    for (final anim in _itemAnims) {
      anim.controller.dispose();
    }
    super.dispose();
  }

  /// 判断指定轨道是否有传送带物理连接。
  /// 物流桥的传送带是"穿过"建筑的，因此不能依赖端点距离检测
  /// （conveyorPortConnections），而是检查传送带 path 是否经过物流桥
  /// 所在格子，并判断该格子处的传送带方向。
  /// Track A (x轴) 对应左右方向，Track B (y轴) 对应上下方向。
  bool _isTrackConnected(int trackIndex) {
    final targetDirections =
        trackIndex == 0 ? {'left', 'right'} : {'up', 'down'};
    return _findBeltDirectionAtBridge(targetDirections) != null;
  }

  /// 获取指定轨道对应的物品 ID
  String? _pickItemIdForTrack(int trackIndex) {
    final targetDirections =
        trackIndex == 0 ? {'left', 'right'} : {'up', 'down'};

    // 1. 从桥 lane 读取
    if (widget.placedBuilding.isBeltBridge) {
      for (final dir in targetDirections) {
        final laneItemId =
            widget.placedBuilding.bridgeItemIdForOutputDirection(dir);
        if (laneItemId != null && laneItemId.isNotEmpty) {
          return laneItemId;
        }
      }
    }

    // 2. 从穿过物流桥的传送带读取
    final dir = _findBeltDirectionAtBridge(targetDirections);
    if (dir != null) {
      final bridgeX = widget.placedBuilding.gridX;
      final bridgeY = widget.placedBuilding.gridY;
      for (final belt in widget.conveyors ?? []) {
        for (int i = 0; i < belt.path.length; i++) {
          if (belt.path[i].dx.round() == bridgeX &&
              belt.path[i].dy.round() == bridgeY) {
            final beltDir = _getBeltDirectionAtIndex(belt, i);
            if (beltDir == dir && belt.itemId.isNotEmpty) {
              return belt.itemId;
            }
          }
        }
      }
    }

    return null;
  }

  /// 在穿过物流桥的传送带中，找到方向匹配 targetDirections 的那一条的方向。
  String? _findBeltDirectionAtBridge(Set<String> targetDirections) {
    final bridgeX = widget.placedBuilding.gridX;
    final bridgeY = widget.placedBuilding.gridY;

    for (final belt in widget.conveyors ?? []) {
      for (int i = 0; i < belt.path.length; i++) {
        if (belt.path[i].dx.round() != bridgeX ||
            belt.path[i].dy.round() != bridgeY) {
          continue;
        }
        final dir = _getBeltDirectionAtIndex(belt, i);
        if (dir != null && targetDirections.contains(dir)) {
          return dir;
        }
      }
    }
    return null;
  }

  /// 获取传送带在指定索引处的方向（仅直行）。
  String? _getBeltDirectionAtIndex(ConveyorBelt belt, int i) {
    if (belt.path.length < 2) return null;
    if (i == 0) {
      return _directionBetween(belt.path[0], belt.path[1]);
    }
    if (i == belt.path.length - 1) {
      return _directionBetween(belt.path[i - 1], belt.path[i]);
    }
    final dir1 = _directionBetween(belt.path[i - 1], belt.path[i]);
    final dir2 = _directionBetween(belt.path[i], belt.path[i + 1]);
    if (dir1 == dir2) return dir1;
    return null;
  }

  String? _directionBetween(Offset from, Offset to) {
    final dx = to.dx.round() - from.dx.round();
    final dy = to.dy.round() - from.dy.round();
    if (dx == 1 && dy == 0) return 'right';
    if (dx == -1 && dy == 0) return 'left';
    if (dx == 0 && dy == 1) return 'down';
    if (dx == 0 && dy == -1) return 'up';
    return null;
  }

  void _spawnItem() {
    final trackAConnected = _isTrackConnected(0);
    final trackBConnected = _isTrackConnected(1);

    if (!trackAConnected && !trackBConnected) return;

    int trackIndex;
    if (trackAConnected && trackBConnected) {
      trackIndex = _spawnCounter % 2;
      _spawnCounter++;
    } else if (trackAConnected) {
      trackIndex = 0;
    } else {
      trackIndex = 1;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    final curveAnim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    final anim = _BridgeItemAnim(
      controller: controller,
      curveAnim: curveAnim,
      itemId: _pickItemIdForTrack(trackIndex),
      trackIndex: trackIndex,
    );
    _itemAnims.add(anim);
    controller.forward().then((_) {
      if (mounted) {
        _itemAnims.remove(anim);
        controller.dispose();
        setState(() {});
      }
    });
    setState(() {});
  }

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：设备文字说明 + 物流速度
              _buildDescriptionPanel(),
              const SizedBox(width: 20),
              // 右侧：轨道组件
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final centerX = constraints.maxWidth / 2;
                    final centerY = constraints.maxHeight / 2;
                    final trackAConnected = _isTrackConnected(0);
                    final trackBConnected = _isTrackConnected(1);

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 1. 下方轨道 B（先画，位于底层）
                        AnimatedBuilder(
                          animation: _arrowController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: _BridgeTrackPainter(
                                trackType: _BridgeTrackType.b,
                                isActive: trackBConnected,
                                animationValue:
                                    trackBConnected ? _arrowController.value : 0,
                                trackLength: _trackLength,
                                trackWidth: _trackWidth,
                              ),
                            );
                          },
                        ),
                        // 2. 轨道 B 的物品（位于轨道 B 之上，轨道 A 之下）
                        ..._buildItemWidgetsForTrack(1, centerX, centerY),
                        // 3. 上方轨道 A（后画，遮挡轨道 B 的物品）
                        AnimatedBuilder(
                          animation: _arrowController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: _BridgeTrackPainter(
                                trackType: _BridgeTrackType.a,
                                isActive: trackAConnected,
                                animationValue:
                                    trackAConnected ? _arrowController.value : 0,
                                trackLength: _trackLength,
                                trackWidth: _trackWidth,
                              ),
                            );
                          },
                        ),
                        // 4. 轨道 A 的物品（位于最上层）
                        ..._buildItemWidgetsForTrack(0, centerX, centerY),
                        // 5. 轨道两端的物品格子
                        ..._buildTrackEndSlots(centerX, centerY),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionPanel() {
    return const SizedBox(
      width: 440,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              // 设备文字说明：底部留空给物流速度
              Padding(
                padding: EdgeInsets.only(bottom: 56),
                child: Text(
                  '可让多条（最多3条）分支传送带汇流传输到1条传送带的物流工具。',
                  style: TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ),
              // 物流速度信息：定位到文字说明右下角
              Positioned(
                bottom: 0,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '物流速度',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '0.5',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '单位/秒',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildItemWidgetsForTrack(
      int trackIndex, double centerX, double centerY) {
    final widgets = <Widget>[];
    const edgeFade = _trackLength * _BridgeTrackPainter._fadeRatio;

    for (final anim in _itemAnims.where((a) => a.trackIndex == trackIndex)) {
      final angle = anim.trackIndex == 0 ? _trackAngleA : _trackAngleB;

      final dataItem =
          anim.itemId != null ? widget.dataLoader.getItem(anim.itemId!) : null;

      final itemChild = dataItem != null && dataItem.imageAssetPath.isNotEmpty
          ? Image.asset(
              dataItem.imageAssetPath,
              width: _itemSize,
              height: _itemSize,
              cacheWidth: 120,
              cacheHeight: 120,
              fit: BoxFit.contain,
              filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
              isAntiAlias: true,
              errorBuilder: (_, __, ___) => _buildItemPlaceholder(dataItem),
            )
          : _buildGenericItemPlaceholder();

      widgets.add(
        AnimatedBuilder(
          animation: anim.curveAnim,
          builder: (context, child) {
            final progress = anim.curveAnim.value;
            final travel = (progress - 0.5) * _trackLength;
            final x = centerX + travel * math.cos(angle);
            final y = centerY + travel * math.sin(angle);

            double opacity = 0.9;
            final distFromStart = progress * _trackLength;
            if (distFromStart < edgeFade) {
              opacity = (distFromStart / edgeFade) * 0.9;
            } else if (distFromStart > _trackLength - edgeFade) {
              opacity = ((_trackLength - distFromStart) / edgeFade) * 0.9;
            }

            return Positioned(
              left: x - _itemSize / 2,
              top: y - _itemSize / 2,
              child: Opacity(
                opacity: opacity.clamp(0.0, 0.9),
                child: child,
              ),
            );
          },
          child: itemChild,
        ),
      );
    }
    return widgets;
  }

  Widget _buildItemPlaceholder(Item dataItem) {
    return Container(
      width: _itemSize,
      height: _itemSize,
      decoration: BoxDecoration(
        color: dataItem.color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: dataItem.color.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildGenericItemPlaceholder() {
    return Container(
      width: _itemSize,
      height: _itemSize,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB82B).withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFFB82B).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// 构建轨道两端的物品格子
  List<Widget> _buildTrackEndSlots(double centerX, double centerY) {
    final widgets = <Widget>[];
    final trackAConnected = _isTrackConnected(0);
    final trackBConnected = _isTrackConnected(1);

    // Track A 两端 (角度 30°)
    final aItemId = _pickItemIdForTrack(0);
    final aItem = aItemId != null ? widget.dataLoader.getItem(aItemId) : null;
    const halfLen = _trackLength / 2;
    // 轨道 A 两端在屏幕上的位置
    final aEnd1X = centerX + (-halfLen) * math.cos(_trackAngleA);
    final aEnd1Y = centerY + (-halfLen) * math.sin(_trackAngleA);
    final aEnd2X = centerX + halfLen * math.cos(_trackAngleA);
    final aEnd2Y = centerY + halfLen * math.sin(_trackAngleA);

    widgets.add(_buildSlotWidget(
      aEnd1X, aEnd1Y, aItem, trackAConnected,
    ));
    widgets.add(_buildSlotWidget(
      aEnd2X, aEnd2Y, aItem, trackAConnected,
    ));

    // Track B 两端 (角度 150°)
    final bItemId = _pickItemIdForTrack(1);
    final bItem = bItemId != null ? widget.dataLoader.getItem(bItemId) : null;
    final bEnd1X = centerX + (-halfLen) * math.cos(_trackAngleB);
    final bEnd1Y = centerY + (-halfLen) * math.sin(_trackAngleB);
    final bEnd2X = centerX + halfLen * math.cos(_trackAngleB);
    final bEnd2Y = centerY + halfLen * math.sin(_trackAngleB);

    widgets.add(_buildSlotWidget(
      bEnd1X, bEnd1Y, bItem, trackBConnected,
    ));
    widgets.add(_buildSlotWidget(
      bEnd2X, bEnd2Y, bItem, trackBConnected,
    ));

    return widgets;
  }

  Widget _buildSlotWidget(
      double x, double y, Item? dataItem, bool isActive) {
    final level = dataItem?.level;
    final hasItem = dataItem != null;

    return Positioned(
      left: x - _slotSize / 2,
      top: y - _slotSize / 2,
      child: SizedBox(
        width: _slotSize,
        height: _slotSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.string(
              _getGridSvg(level, isActive),
              fit: BoxFit.fill,
            ),
            if (hasItem && dataItem.imageAssetPath.isNotEmpty)
              Center(
                child: AnimatedOpacity(
                  opacity: isActive ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 300),
                  child: Image.asset(
                    dataItem.imageAssetPath,
                    width: _slotSize,
                    height: _slotSize,
                    cacheWidth: 192,
                    cacheHeight: 192,
                    fit: BoxFit.contain,
                    filterQuality: kIsWeb ? FilterQuality.high : FilterQuality.medium,
                    isAntiAlias: true,
                    errorBuilder: (_, __, ___) =>
                        _buildItemPlaceholder(dataItem),
                  ),
                ),
              )
            else if (hasItem)
              Center(child: _buildItemPlaceholder(dataItem)),
          ],
        ),
      ),
    );
  }

  String _getGridSvg(int? level, bool isActive) {
    if (!isActive) {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
          '<rect x="0" y="0" width="128" height="128" rx="15" ry="15" fill="#4a4a4a"/>'
          '</svg>';
    }

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
}

class _BridgeTrackPainter extends CustomPainter {
  final double animationValue;
  final double trackLength;
  final double trackWidth;
  final _BridgeTrackType trackType;
  final bool isActive;

  static const double _depthHeight = 10.0;
  static const double _fadeRatio = 0.35;

  _BridgeTrackPainter({
    required this.animationValue,
    required this.trackLength,
    required this.trackWidth,
    required this.trackType,
    this.isActive = true,
  });

  // 等轴测投影映射函数
  Offset _project(double x, double y, double z, Offset center) {
    const double cos30 = 0.86602540378; // math.cos(math.pi / 6)
    const double sin30 = 0.5; // math.sin(math.pi / 6)
    return Offset(
      center.dx + (x - y) * cos30,
      center.dy + (x + y) * sin30 - z,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    if (trackType == _BridgeTrackType.b) {
      _drawTrackB(canvas, center);
    } else {
      _drawTrackA(canvas, center);
    }
  }

  void _drawTrackA(Canvas canvas, Offset center) {
    final halfLen = trackLength / 2;
    final halfWidth = trackWidth / 2;

    // 1. 顶面顶点 (z = 0)
    final p1 = _project(-halfLen, -halfWidth, 0, center);
    final p2 = _project(halfLen, -halfWidth, 0, center);
    final p3 = _project(halfLen, halfWidth, 0, center);
    final p4 = _project(-halfLen, halfWidth, 0, center);

    final topPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 2. 前方面板顶点 (朝向玩家的边缘在 y = halfWidth，自 z=0 向下延伸至 z=-_depthHeight)
    final p4Depth = _project(-halfLen, halfWidth, -_depthHeight, center);
    final p3Depth = _project(halfLen, halfWidth, -_depthHeight, center);

    final frontPath = Path()
      ..moveTo(p4.dx, p4.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p3Depth.dx, p3Depth.dy)
      ..lineTo(p4Depth.dx, p4Depth.dy)
      ..close();

    // 3. 顶面渐变着色器 (方向为 60°，以使渐变边缘与 150° 的端点完全平行)
    const cos30 = 0.86602540378;
    final double gradDist = halfLen * cos30;
    final gradStart = center + Offset(-gradDist * 0.5, -gradDist * cos30);
    final gradEnd = center + Offset(gradDist * 0.5, gradDist * cos30);

    final topGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00E88A11),
              Color(0xAAFFB82B),
              Color(0xAAFFB82B),
              Color(0x00E88A11),
            ]
          : const [
              Color(0x00444444),
              Color(0xAA666666),
              Color(0xAA666666),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final trackPaint = Paint()
      ..shader = topGradient
      ..style = PaintingStyle.fill;

    // 4. 前方面板渐变着色器
    final frontGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x006E4E1A),
              Color(0xCC8D6E32),
              Color(0xCC8D6E32),
              Color(0x006E4E1A),
            ]
          : const [
              Color(0x00333333),
              Color(0xCC555555),
              Color(0xCC555555),
              Color(0x00333333),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final frontPaint = Paint()
      ..shader = frontGradient
      ..style = PaintingStyle.fill;

    // 绘制前方面板和顶面
    canvas.drawPath(frontPath, frontPaint);
    canvas.drawPath(topPath, trackPaint);

    // 5. 边框线条 (同步渐变过渡)
    final borderGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00FFBB33),
              Color(0xDDFFD266),
              Color(0xDDFFD266),
              Color(0x00FFBB33),
            ]
          : const [
              Color(0x00444444),
              Color(0xDD777777),
              Color(0xDD777777),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final borderPaint = Paint()
      ..shader = borderGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 绘制长边边框
    canvas.drawLine(p1, p2, borderPaint);
    canvas.drawLine(p4, p3, borderPaint);

    // 6. 绘制箭头动画
    canvas.save();
    canvas.clipPath(topPath);

    for (int a = 0; a < 3; a++) {
      final t = (animationValue + a / 3.0) % 1.0;
      final arrowX = -halfLen + t * trackLength;

      final edgeFadeLen = trackLength * _fadeRatio;
      double opacity = 0.9;
      final distFromStart = t * trackLength;
      if (distFromStart < edgeFadeLen) {
        opacity = (distFromStart / edgeFadeLen) * 0.9;
      } else if (distFromStart > trackLength - edgeFadeLen) {
        opacity = ((trackLength - distFromStart) / edgeFadeLen) * 0.9;
      }

      final arrowPaint = Paint()
        ..color = (isActive ? Colors.white : const Color(0xFF999999))
            .withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      // 3D 三角形顶点 (沿 x 轴方向流动)
      const arrowHalfH = 3.5;
      final tip = _project(arrowX + 5.5, 0, 0, center);
      final leftBack = _project(arrowX - 4.5, -arrowHalfH, 0, center);
      final rightBack = _project(arrowX - 4.5, arrowHalfH, 0, center);

      final arrowPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(leftBack.dx, leftBack.dy)
        ..lineTo(rightBack.dx, rightBack.dy)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
    canvas.restore();
  }

  void _drawTrackB(Canvas canvas, Offset center) {
    final halfLen = trackLength / 2;
    final halfWidth = trackWidth / 2;

    // 1. 顶面顶点 (z = 0)
    final p1 = _project(-halfWidth, -halfLen, 0, center);
    final p2 = _project(halfWidth, -halfLen, 0, center);
    final p3 = _project(halfWidth, halfLen, 0, center);
    final p4 = _project(-halfWidth, halfLen, 0, center);

    final topPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 2. 前方面板顶点 (朝向玩家的边缘在 x = halfWidth，自 z=0 向下延伸至 z=-_depthHeight)
    final p2Depth = _project(halfWidth, -halfLen, -_depthHeight, center);
    final p3Depth = _project(halfWidth, halfLen, -_depthHeight, center);

    final frontPath = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p3Depth.dx, p3Depth.dy)
      ..lineTo(p2Depth.dx, p2Depth.dy)
      ..close();

    // 3. 顶面渐变着色器 (方向为 120°，以使渐变与 30° 的端点完全平行)
    const cos30 = 0.86602540378;
    final double gradDist = halfLen * cos30;
    final gradStart = center + Offset(gradDist * 0.5, -gradDist * cos30);
    final gradEnd = center + Offset(-gradDist * 0.5, gradDist * cos30);

    final topGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00E88A11),
              Color(0xAAFFB82B),
              Color(0xAAFFB82B),
              Color(0x00E88A11),
            ]
          : const [
              Color(0x00444444),
              Color(0xAA666666),
              Color(0xAA666666),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final trackPaint = Paint()
      ..shader = topGradient
      ..style = PaintingStyle.fill;

    // 4. 前方面板渐变着色器
    final frontGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x006E4E1A),
              Color(0xCC8D6E32),
              Color(0xCC8D6E32),
              Color(0x006E4E1A),
            ]
          : const [
              Color(0x00333333),
              Color(0xCC555555),
              Color(0xCC555555),
              Color(0x00333333),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final frontPaint = Paint()
      ..shader = frontGradient
      ..style = PaintingStyle.fill;

    // 绘制前方面板和顶面
    canvas.drawPath(frontPath, frontPaint);
    canvas.drawPath(topPath, trackPaint);

    // 5. 边框线条 (同步渐变过渡)
    final borderGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      isActive
          ? const [
              Color(0x00FFBB33),
              Color(0xDDFFD266),
              Color(0xDDFFD266),
              Color(0x00FFBB33),
            ]
          : const [
              Color(0x00444444),
              Color(0xDD777777),
              Color(0xDD777777),
              Color(0x00444444),
            ],
      const [0.0, _fadeRatio, 1.0 - _fadeRatio, 1.0],
    );

    final borderPaint = Paint()
      ..shader = borderGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 绘制长边边框
    canvas.drawLine(p1, p4, borderPaint);
    canvas.drawLine(p2, p3, borderPaint);

    // 6. 绘制箭头动画
    canvas.save();
    canvas.clipPath(topPath);

    for (int a = 0; a < 3; a++) {
      final t = (animationValue + a / 3.0) % 1.0;
      final arrowY = -halfLen + t * trackLength;

      final edgeFadeLen = trackLength * _fadeRatio;
      double opacity = 0.9;
      final distFromStart = t * trackLength;
      if (distFromStart < edgeFadeLen) {
        opacity = (distFromStart / edgeFadeLen) * 0.9;
      } else if (distFromStart > trackLength - edgeFadeLen) {
        opacity = ((trackLength - distFromStart) / edgeFadeLen) * 0.9;
      }

      final arrowPaint = Paint()
        ..color = (isActive ? Colors.white : const Color(0xFF999999))
            .withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      // 3D 三角形顶点 (沿 y 轴方向流动)
      const arrowHalfH = 3.5;
      final tip = _project(0, arrowY + 5.5, 0, center);
      final leftBack = _project(-arrowHalfH, arrowY - 4.5, 0, center);
      final rightBack = _project(arrowHalfH, arrowY - 4.5, 0, center);

      final arrowPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(leftBack.dx, leftBack.dy)
        ..lineTo(rightBack.dx, rightBack.dy)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BridgeTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.trackType != trackType;
  }
}
