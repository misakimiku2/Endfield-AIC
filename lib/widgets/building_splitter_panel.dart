import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';

/// 分流器专用面板：以等轴测 3D 视图展示 1 输入 → 3 输出的分配原理。
///
/// 视觉结构与物流桥一致：
/// - 4 条半轨道从中心向外辐射（等轴测 30°/150° 投影）
/// - 输入轨道（+y 方向，屏幕右下）：箭头向中心流动
/// - 输出轨道（-y 上 / -x 左 / +x 右）：箭头向远端流动
/// - 轨道末端：物品格子（显示当前传输的物品）
/// - 物品动画：从输入格 → 中心 → 输出格（按循环顺序分配）
class SplitterPanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final List<ConveyorBelt>? conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const SplitterPanel({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    this.onMove,
    this.onDelete,
  });

  @override
  State<SplitterPanel> createState() => _SplitterPanelState();
}

class _SplitterPanelState extends State<SplitterPanel>
    with TickerProviderStateMixin {
  late AnimationController _arrowController;
  Timer? _spawnTimer;
  final List<_SplitterItemAnim> _itemAnims = [];
  int _spawnCounter = 0;

  // 视觉常量（与物流桥一致）
  static const double _trackLength = 220.0;
  static const double _trackWidth = 54.0;
  static const double _itemSize = 40.0;
  static const double _slotSize = 96.0;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _spawnTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
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

  // ===== 传送带检测 =====

  String? _directionBetween(Offset from, Offset to) {
    final dx = to.dx.round() - from.dx.round();
    final dy = to.dy.round() - from.dy.round();
    if (dx == 1 && dy == 0) return 'right';
    if (dx == -1 && dy == 0) return 'left';
    if (dx == 0 && dy == 1) return 'down';
    if (dx == 0 && dy == -1) return 'up';
    return null;
  }

  String? _beltExitDirection(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      return _directionBetween(belt.path.first, belt.path[1]);
    }
    return belt.forcedDirection;
  }

  Offset get _splitterCell => Offset(
        widget.placedBuilding.gridX.toDouble(),
        widget.placedBuilding.gridY.toDouble(),
      );

  /// 获取已连接的输出方向列表（按传送带创建顺序）
  List<String> get _connectedOutputDirections {
    final directions = <String>[];
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _splitterCell.dx.round() &&
          start.dy.round() == _splitterCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir != null &&
            !directions.contains(exitDir) &&
            exitDir != 'down') {
          directions.add(exitDir);
        }
      }
    }
    return directions;
  }

  /// 检查是否有输入传送带（从下方流入分流器）
  bool get _hasInputBelt {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == _splitterCell.dx.round() &&
          end.dy.round() == _splitterCell.dy.round()) {
        if (belt.path.length >= 2) {
          final dir = _directionBetween(
              belt.path[belt.path.length - 2], belt.path.last);
          if (dir == 'up') return true;
        }
      }
    }
    return false;
  }

  /// 获取输入传送带上的物品 ID
  String? _itemIdForInput() {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == _splitterCell.dx.round() &&
          end.dy.round() == _splitterCell.dy.round()) {
        if (belt.path.length >= 2) {
          final dir = _directionBetween(
              belt.path[belt.path.length - 2], belt.path.last);
          if (dir == 'up' && belt.itemId.isNotEmpty) {
            return belt.itemId;
          }
        }
      }
    }
    return null;
  }

  /// 获取指定输出方向传送带上的物品 ID
  String? _itemIdForOutput(String direction) {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _splitterCell.dx.round() &&
          start.dy.round() == _splitterCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == direction && belt.itemId.isNotEmpty) {
          return belt.itemId;
        }
      }
    }
    return null;
  }

  /// 检查输入传送带是否堵塞（源设备阻塞、传送带卡住、或输出端全部堵塞导致回流）
  bool get _isInputBlocked {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == _splitterCell.dx.round() &&
          end.dy.round() == _splitterCell.dy.round()) {
        if (belt.path.length >= 2) {
          final dir = _directionBetween(
              belt.path[belt.path.length - 2], belt.path.last);
          if (dir == 'up') {
            // 输入带自身的堵塞状态
            final selfBlocked = belt.isBlocked || _isBeltStuck(belt);
            // 任一已连接输出端堵塞 → 物品无法流出 → 输入端也堵塞
            final outputDirs = _connectedOutputDirections;
            final anyOutputBlocked = outputDirs.any(
                (d) => _isOutputBlocked(d));
            final blocked = selfBlocked || (outputDirs.isNotEmpty && anyOutputBlocked);
            debugPrint('[SplitterPanel] 输入传送带 self=$selfBlocked, anyOutBlk=$anyOutputBlocked, final=$blocked');
            return blocked;
          }
        }
      }
    }
    return false;
  }

  /// 检查指定输出方向传送带是否堵塞
  bool _isOutputBlocked(String direction) {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _splitterCell.dx.round() &&
          start.dy.round() == _splitterCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == direction) {
          final blocked = belt.isBlocked ||
              _isBeltStuck(belt);
          debugPrint('[SplitterPanel] 输出$direction 传送带 isBlocked=${belt.isBlocked}, stuck=${_isBeltStuck(belt)}, final=$blocked, path=${belt.path.map((e) => '(${e.dx.toInt()},${e.dy.toInt()})')}');
          return blocked;
        }
      }
    }
    return false;
  }

  /// 判断传送带是否处于物品卡住状态（非 isBlocked，但物品无法流动）
  /// 检测条件：有物品 + 死端冻结 或 满载无法推送
  bool _isBeltStuck(ConveyorBelt belt) {
    // 有物品才可能"卡住"
    if (belt.itemId.isEmpty && belt.lastItemId.isEmpty) return false;
    // 死端冻结：deadEndFreezeProgress 非空表示断头传送带已满载冻结
    if (belt.deadEndFreezeProgress != null) return true;
    // 残留物品冻结：lastItemFreezeProgress 非空表示残留物品排空被冻结
    if (belt.lastItemFreezeProgress != null) return true;
    // 物品满载且无 drainage（fillCount 到达末端但 drainCount 未跟上）
    if (belt.itemFillCount >= belt.path.length &&
        belt.itemDrainCount < belt.itemFillCount - 1) return true;
    return false;
  }

  void _spawnItem() {
    final inputConnected = _hasInputBelt;
    final outputDirs = _connectedOutputDirections;

    if (!inputConnected || outputDirs.isEmpty) return;
    // 堵塞时停止生成新物品动画
    if (_isInputBlocked) return;

    // 按循环顺序选择输出方向
    final outputDir = outputDirs[_spawnCounter % outputDirs.length];
    _spawnCounter++;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    final curveAnim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    final anim = _SplitterItemAnim(
      controller: controller,
      curveAnim: curveAnim,
      itemId: _itemIdForInput(),
      outputDirection: outputDir,
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

  // ===== 等轴测投影（与物流桥一致）=====

  Offset _project(double x, double y, double z, Offset center) {
    const double cos30 = 0.86602540378;
    const double sin30 = 0.5;
    return Offset(
      center.dx + (y - x) * cos30,
      center.dy + (x + y) * sin30 - z,
    );
  }

  /// 计算指定方向轨道末端在屏幕上的位置
  /// direction: 'down'(输入), 'up', 'left', 'right'
  Offset _slotScreenPos(String direction, Offset center) {
    switch (direction) {
      case 'down': // 输入：+y 方向
        return _project(0, _trackLength, 0, center);
      case 'up': // -y 方向
        return _project(0, -_trackLength, 0, center);
      case 'left': // +x 方向（屏幕左下）
        return _project(_trackLength, 0, 0, center);
      case 'right': // -x 方向（屏幕右上）
        return _project(-_trackLength, 0, 0, center);
      default:
        return center;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部操作按钮
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
              // 右侧：轨道可视化
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final center =
                        Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
                    final inputConnected = _hasInputBelt;
                    final inputBlocked = _isInputBlocked;
                    final outputDirs = _connectedOutputDirections;

                    // 计算每条轨道状态：0=未连接(灰), 1=正常(橙金), 2=堵塞(红)
                    int _state(bool connected, bool blocked) {
                      if (!connected) return 0;
                      return blocked ? 2 : 1;
                    }

                    final sInput = _state(inputConnected, inputBlocked);
                    final sUp = _state(outputDirs.contains('up'), _isOutputBlocked('up'));
                    final sLeft = _state(outputDirs.contains('left'), _isOutputBlocked('left'));
                    final sRight = _state(outputDirs.contains('right'), _isOutputBlocked('right'));
                    debugPrint('[SplitterPanel] 状态: input=$sInput(up=$inputConnected,blk=$inputBlocked) up=$sUp left=$sLeft right=$sRight  outputDirs=$outputDirs');

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 等轴测 3D 轨道（单一 CustomPaint 绘制全部 4 条轨道）
                        AnimatedBuilder(
                          animation: _arrowController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: Size(
                                  constraints.maxWidth, constraints.maxHeight),
                              painter: _SplitterTrackPainter(
                                animationValue: _arrowController.value,
                                trackLength: _trackLength,
                                trackWidth: _trackWidth,
                                inputState: sInput,
                                upState: sUp,
                                leftState: sLeft,
                                rightState: sRight,
                              ),
                            );
                          },
                        ),
                        // 物品流动动画
                        ..._buildItemWidgets(center),
                        // 轨道末端物品格子
                        ..._buildTrackEndSlots(center, outputDirs),
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
                  '可让1条传送带均匀传输到多条（最多3条）分支传送带的物流工具。',
                  style: TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ),
              // 物流速度信息
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

  List<Widget> _buildItemWidgets(Offset center) {
    final widgets = <Widget>[];
    const edgeFade = _trackLength * 0.35;

    for (final anim in _itemAnims) {
      final inputSlot = _slotScreenPos('down', center);
      final outputSlot = _slotScreenPos(anim.outputDirection, center);

      final dataItem =
          anim.itemId != null ? widget.dataLoader.getItem(anim.itemId!) : null;

      final itemChild =
          dataItem != null && dataItem.imageAssetPath.isNotEmpty
              ? Image.asset(
                  dataItem.imageAssetPath,
                  width: _itemSize,
                  height: _itemSize,
                  cacheWidth: 120,
                  cacheHeight: 120,
                  fit: BoxFit.contain,
                  filterQuality:
                      kIsWeb ? FilterQuality.high : FilterQuality.medium,
                  isAntiAlias: true,
                  errorBuilder: (_, __, ___) =>
                      _buildItemPlaceholder(dataItem),
                )
              : _buildGenericItemPlaceholder();

      widgets.add(
        AnimatedBuilder(
          animation: anim.curveAnim,
          builder: (context, child) {
            final progress = anim.curveAnim.value;
            Offset pos;
            double opacity = 0.9;

            if (progress < 0.5) {
              // 阶段1：输入格 → 中心
              final t = progress * 2;
              pos = Offset(
                inputSlot.dx + (center.dx - inputSlot.dx) * t,
                inputSlot.dy + (center.dy - inputSlot.dy) * t,
              );
              // 起点淡入
              final distFromStart = progress * _trackLength * 2;
              if (distFromStart < edgeFade) {
                opacity = (distFromStart / edgeFade) * 0.9;
              }
            } else {
              // 阶段2：中心 → 输出格
              final t = (progress - 0.5) * 2;
              pos = Offset(
                center.dx + (outputSlot.dx - center.dx) * t,
                center.dy + (outputSlot.dy - center.dy) * t,
              );
              // 终点淡出
              final distFromEnd = (1.0 - progress) * _trackLength * 2;
              if (distFromEnd < edgeFade) {
                opacity = (distFromEnd / edgeFade) * 0.9;
              }
            }

            return Positioned(
              left: pos.dx - _itemSize / 2,
              top: pos.dy - _itemSize / 2,
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

  List<Widget> _buildTrackEndSlots(
      Offset center, List<String> outputDirs) {
    final widgets = <Widget>[];

    // 输入格（下方 +y 方向）
    final inputConnected = _hasInputBelt;
    final inputItemId = _itemIdForInput();
    final inputItem =
        inputItemId != null ? widget.dataLoader.getItem(inputItemId) : null;
    final inputPos = _slotScreenPos('down', center);
    widgets.add(_buildSlotWidget(
      inputPos.dx, inputPos.dy, inputItem, inputConnected,
    ));

    // 输出格
    for (final dir in const ['up', 'left', 'right']) {
      final isActive = outputDirs.contains(dir);
      final itemId = isActive ? _itemIdForOutput(dir) : null;
      final item =
          itemId != null ? widget.dataLoader.getItem(itemId) : null;
      final pos = _slotScreenPos(dir, center);
      widgets.add(_buildSlotWidget(
        pos.dx, pos.dy, item, isActive,
      ));
    }

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
                    filterQuality:
                        kIsWeb ? FilterQuality.high : FilterQuality.medium,
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

class _SplitterItemAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String? itemId;
  final String outputDirection;

  _SplitterItemAnim({
    required this.controller,
    required this.curveAnim,
    this.itemId,
    required this.outputDirection,
  });
}

/// 分流器轨道绘制器：等轴测 3D 投影，绘制 4 条半轨道。
///
/// 轨道方向（游戏坐标）：
/// - 输入：+y 方向（屏幕右下），箭头向中心流动
/// - 输出上：-y 方向（屏幕左上），箭头向远端流动
/// - 输出左：+x 方向（屏幕左下），箭头向远端流动
/// - 输出右：-x 方向（屏幕右上），箭头向远端流动
class _SplitterTrackPainter extends CustomPainter {
  final double animationValue;
  final double trackLength;
  final double trackWidth;
  // 每条轨道状态：0=未连接(灰), 1=正常(橙金), 2=堵塞(红)
  final int inputState;
  final int upState;
  final int leftState;
  final int rightState;

  static const double _depthHeight = 10.0;
  static const double _centerFadeRatio = 0.8;
  static const double _endFadeRatio = 0.35;

  _SplitterTrackPainter({
    required this.animationValue,
    required this.trackLength,
    required this.trackWidth,
    this.inputState = 0,
    this.upState = 0,
    this.leftState = 0,
    this.rightState = 0,
  });

  // 等轴测投影（与物流桥完全一致）
  Offset _project(double x, double y, double z, Offset center) {
    const double cos30 = 0.86602540378;
    const double sin30 = 0.5;
    return Offset(
      center.dx + (y - x) * cos30,
      center.dy + (x + y) * sin30 - z,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 按深度顺序绘制（背面先画，正面后画）
    // left 现在映射到 +x（屏幕左下），right 映射到 -x（屏幕右上）
    _drawHalfTrack(canvas, center, 1, 0, leftState, animationValue,
        flowTowardCenter: false);
    _drawHalfTrack(canvas, center, 0, -1, upState, animationValue,
        flowTowardCenter: false);
    _drawHalfTrack(canvas, center, -1, 0, rightState, animationValue,
        flowTowardCenter: false);
    _drawHalfTrack(canvas, center, 0, 1, inputState, animationValue,
        flowTowardCenter: true);
  }

  /// 绘制单条半轨道（从中心向外辐射）。
  /// [dx], [dy] - 轨道方向（游戏坐标单位向量）
  /// [state] - 轨道状态：0=未连接(灰), 1=正常(橙金流动), 2=堵塞(红静止)
  /// [flowTowardCenter] - true=箭头向中心流（输入），false=箭头向远端流（输出）
  void _drawHalfTrack(
    Canvas canvas,
    Offset center,
    double dx,
    double dy,
    int state,
    double animValue, {
    required bool flowTowardCenter,
  }) {
    final isActive = state > 0;
    final isBlocked = state == 2;
    // 未连接或堵塞时使用固定值，箭头可见但静止
    final effectiveAnimValue = isActive && !isBlocked ? animValue : 0.0;

    final halfWidth = trackWidth / 2;
    final L = trackLength;

    // 垂直方向：perp = (-dy, dx)
    final px = -dy;
    final py = dx;

    // 顶面 4 个顶点（游戏坐标 → 屏幕投影）
    final p1 = _project(px * halfWidth, py * halfWidth, 0, center);
    final p2 =
        _project(dx * L + px * halfWidth, dy * L + py * halfWidth, 0, center);
    final p3 =
        _project(dx * L - px * halfWidth, dy * L - py * halfWidth, 0, center);
    final p4 = _project(-px * halfWidth, -py * halfWidth, 0, center);

    final topPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 确定前方面板（朝向玩家的边缘）
    // 比较 perp 和 -perp 方向的 (x+y) 和，较大者为前面
    final usePerpAsFront = (dx - dy) >= 0;
    final frontStart = usePerpAsFront ? p1 : p4;
    final frontEnd = usePerpAsFront ? p2 : p3;
    final frontPerpX = usePerpAsFront ? px * halfWidth : -px * halfWidth;
    final frontPerpY = usePerpAsFront ? py * halfWidth : -py * halfWidth;

    final frontStartDepth =
        _project(frontPerpX, frontPerpY, -_depthHeight, center);
    final frontEndDepth = _project(
        dx * L + frontPerpX, dy * L + frontPerpY, -_depthHeight, center);

    final frontPath = Path()
      ..moveTo(frontStart.dx, frontStart.dy)
      ..lineTo(frontEnd.dx, frontEnd.dy)
      ..lineTo(frontEndDepth.dx, frontEndDepth.dy)
      ..lineTo(frontStartDepth.dx, frontStartDepth.dy)
      ..close();

    // 渐变方向：起点沿轨道反方向后移，补偿等轴测投影后渐变等色线
    // 与轨道近端边不平行导致角落颜色残留的问题
    final gradBackOffset = halfWidth * 0.6;
    final gradStart = _project(-dx * gradBackOffset, -dy * gradBackOffset, 0, center);
    final gradEnd = _project(dx * L, dy * L, 0, center);

    // 顶面渐变（两端淡出）— 根据状态选色
    final topColors = isBlocked
        ? const [
            Color(0x00CC2222),
            Color(0xAAFF3333),
            Color(0xAAFF3333),
            Color(0x00CC2222),
          ]
        : isActive
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
              ];

    final topGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      topColors,
      const [0.0, _centerFadeRatio, 1.0 - _endFadeRatio, 1.0],
    );

    final trackPaint = Paint()
      ..shader = topGradient
      ..style = PaintingStyle.fill;

    // 前方面板渐变 — 根据状态选色
    final frontColors = isBlocked
        ? const [
            Color(0x00661111),
            Color(0xCC992222),
            Color(0xCC992222),
            Color(0x00661111),
          ]
        : isActive
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
              ];

    final frontGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      frontColors,
      const [0.0, _centerFadeRatio, 1.0 - _endFadeRatio, 1.0],
    );

    final frontPaint = Paint()
      ..shader = frontGradient
      ..style = PaintingStyle.fill;

    // 绘制前方面板和顶面
    canvas.drawPath(frontPath, frontPaint);
    canvas.drawPath(topPath, trackPaint);

    // 边框线条（同步渐变淡出）— 根据状态选色
    final borderColors = isBlocked
        ? const [
            Color(0x00EE3333),
            Color(0xDDFF5555),
            Color(0xDDFF5555),
            Color(0x00EE3333),
          ]
        : isActive
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
              ];

    final borderGradient = ui.Gradient.linear(
      gradStart,
      gradEnd,
      borderColors,
      const [0.0, _centerFadeRatio, 1.0 - _endFadeRatio, 1.0],
    );

    final borderPaint = Paint()
      ..shader = borderGradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // 绘制长边边框
    canvas.drawLine(p1, p2, borderPaint);
    canvas.drawLine(p4, p3, borderPaint);

    // 绘制流动箭头（3 个箭头，均匀错开）
    canvas.save();
    canvas.clipPath(topPath);

    // 箭头流动方向
    final flowDx = flowTowardCenter ? -dx : dx;
    final flowDy = flowTowardCenter ? -dy : dy;
    // 垂直于流动方向
    final flowPerpX = -flowDy;
    final flowPerpY = flowDx;

    // 中心端和远端的渐变长度（根据流动方向区分）
    // 输出轨道：起点=中心（大），终点=远端（小）
    // 输入轨道：起点=远端（小），终点=中心（大）
    final centerFadeLen = trackLength * _centerFadeRatio;
    final endFadeLen = trackLength * _endFadeRatio;
    final fadeLenStart = flowTowardCenter ? endFadeLen : centerFadeLen;
    final fadeLenEnd = flowTowardCenter ? centerFadeLen : endFadeLen;

    for (int a = 0; a < 3; a++) {
      final t = (effectiveAnimValue + a / 3.0) % 1.0;
      double opacity = 0.9;
      final distFromStart = t * trackLength;
      if (distFromStart < fadeLenStart) {
        opacity = (distFromStart / fadeLenStart) * 0.9;
      } else if (distFromStart > trackLength - fadeLenEnd) {
        opacity = ((trackLength - distFromStart) / fadeLenEnd) * 0.9;
      }

      // 箭头颜色：正常=白, 堵塞=红, 未连接=灰
      final arrowBaseColor = isBlocked
          ? const Color(0xFFFF5555)
          : isActive
              ? Colors.white
              : const Color(0xFF999999);
      final arrowPaint = Paint()
        ..color = arrowBaseColor.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      // 箭头中心位置（沿轨道方向）
      // 输出：t=0 在中心，t=1 在远端 → pos = (dx * t * L, dy * t * L)
      // 输入：t=0 在远端，t=1 在中心 → pos = (dx * (1-t) * L, dy * (1-t) * L)
      final progress = flowTowardCenter ? (1.0 - t) : t;
      final arrowCx = dx * progress * L;
      final arrowCy = dy * progress * L;

      // 箭头三角形顶点（游戏坐标 → 投影）
      const arrowLen = 10.0;
      const arrowHalfH = 4.0;
      final tip = _project(
        arrowCx + flowDx * arrowLen / 2,
        arrowCy + flowDy * arrowLen / 2,
        0,
        center,
      );
      final leftBack = _project(
        arrowCx - flowDx * arrowLen / 2 + flowPerpX * arrowHalfH,
        arrowCy - flowDy * arrowLen / 2 + flowPerpY * arrowHalfH,
        0,
        center,
      );
      final rightBack = _project(
        arrowCx - flowDx * arrowLen / 2 - flowPerpX * arrowHalfH,
        arrowCy - flowDy * arrowLen / 2 - flowPerpY * arrowHalfH,
        0,
        center,
      );

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
  bool shouldRepaint(covariant _SplitterTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.inputState != inputState ||
        oldDelegate.upState != upState ||
        oldDelegate.leftState != leftState ||
        oldDelegate.rightState != rightState;
  }
}
