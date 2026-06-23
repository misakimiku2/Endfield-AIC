import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/project.dart';
import '../models/item.dart';
import '../data/data_loader.dart';
import 'building_shared_widgets.dart';

/// 汇流器专用面板：以等轴测 3D 视图展示 3 输入 → 1 输出的汇流原理。
///
/// 视觉结构与分流器对称：
/// - 3 条输入轨道从左/上/右向中心汇聚（箭头向中心流动）
/// - 1 条输出轨道从中心向下（箭头向远端流动）
/// - 轨道末端：物品格子（显示当前传输的物品）
/// - 物品动画：从输入格 → 中心 → 输出格
class ConvergerPanel extends StatefulWidget {
  final PlacedBuilding placedBuilding;
  final DataLoader dataLoader;
  final List<ConveyorBelt>? conveyors;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const ConvergerPanel({
    super.key,
    required this.placedBuilding,
    required this.dataLoader,
    this.conveyors,
    this.onMove,
    this.onDelete,
  });

  @override
  State<ConvergerPanel> createState() => _ConvergerPanelState();
}

class _ConvergerPanelState extends State<ConvergerPanel>
    with TickerProviderStateMixin {
  late AnimationController _arrowController;
  Timer? _spawnTimer;
  final List<_ConvergerItemAnim> _itemAnims = [];
  int _spawnCounter = 0;

  // 视觉常量（与分流器一致）
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

  String? _beltArrivalDirection(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      return _directionBetween(
          belt.path[belt.path.length - 2], belt.path.last);
    }
    return belt.incomingDirection;
  }

  /// 将传送带到达方向（物品移动方向）转换为汇流器输入端口方向。
  /// - 到达 'right'（物品向右移动）→ 输入端口 'left'（从左方进入）
  /// - 到达 'down'（物品向下移动）→ 输入端口 'up'（从上方进入）
  /// - 到达 'left'（物品向左移动）→ 输入端口 'right'（从右方进入）
  String _arrivalDirToInputPort(String arrivalDir) {
    switch (arrivalDir) {
      case 'right':
        return 'left';
      case 'down':
        return 'up';
      case 'left':
        return 'right';
      case 'up':
        return 'down';
      default:
        return arrivalDir;
    }
  }

  /// 输入端口方向转换为传送带到达方向（物品移动方向）
  String _inputPortToArrivalDir(String inputPort) {
    switch (inputPort) {
      case 'left':
        return 'right';
      case 'up':
        return 'down';
      case 'right':
        return 'left';
      case 'down':
        return 'up';
      default:
        return inputPort;
    }
  }

  Offset get _convergerCell => Offset(
        widget.placedBuilding.gridX.toDouble(),
        widget.placedBuilding.gridY.toDouble(),
      );

  /// 获取已连接的输入方向列表（输入端口方向：left/up/right，按传送带创建顺序）
  List<String> get _connectedInputDirections {
    final directions = <String>[];
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      final endsAtConverger = end.dx.round() == _convergerCell.dx.round() &&
          end.dy.round() == _convergerCell.dy.round();
      if (endsAtConverger) {
        final arrivalDir = _beltArrivalDirection(belt);
        if (arrivalDir != null) {
          final inputPort = _arrivalDirToInputPort(arrivalDir);
          // 排除输出方向 down
          if (inputPort != 'down' && !directions.contains(inputPort)) {
            directions.add(inputPort);
          }
        }
      }
    }
    return directions;
  }

  /// 检查是否有输出传送带（从汇流器向下流出）
  bool get _hasOutputBelt {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _convergerCell.dx.round() &&
          start.dy.round() == _convergerCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == 'down') return true;
      }
    }
    return false;
  }

  /// 获取指定输入端口方向传送带上的物品 ID
  /// direction 参数为输入端口方向（left/up/right）
  String? _itemIdForInput(String direction) {
    final targetArrivalDir = _inputPortToArrivalDir(direction);
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == _convergerCell.dx.round() &&
          end.dy.round() == _convergerCell.dy.round()) {
        final arrivalDir = _beltArrivalDirection(belt);
        if (arrivalDir == targetArrivalDir && belt.itemId.isNotEmpty) {
          return belt.itemId;
        }
      }
    }
    return null;
  }

  /// 获取输出传送带上的物品 ID
  String? _itemIdForOutput() {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _convergerCell.dx.round() &&
          start.dy.round() == _convergerCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == 'down' && belt.itemId.isNotEmpty) {
          return belt.itemId;
        }
      }
    }
    return null;
  }

  /// 检查输出传送带是否堵塞
  bool get _isOutputBlocked {
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == _convergerCell.dx.round() &&
          start.dy.round() == _convergerCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == 'down') {
          return belt.isBlocked || _isBeltStuck(belt);
        }
      }
    }
    return false;
  }

  /// 检查指定输入端口方向传送带是否堵塞
  /// direction 参数为输入端口方向（left/up/right）
  bool _isInputBlocked(String direction) {
    final targetArrivalDir = _inputPortToArrivalDir(direction);
    for (final belt in widget.conveyors ?? []) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == _convergerCell.dx.round() &&
          end.dy.round() == _convergerCell.dy.round()) {
        final arrivalDir = _beltArrivalDirection(belt);
        if (arrivalDir == targetArrivalDir) {
          final selfBlocked = belt.isBlocked || _isBeltStuck(belt);
          // 输出端堵塞 → 输入端也堵塞
          final outputBlocked = _isOutputBlocked;
          return selfBlocked || outputBlocked;
        }
      }
    }
    return false;
  }

  /// 判断传送带是否处于物品卡住状态
  bool _isBeltStuck(ConveyorBelt belt) {
    if (belt.itemId.isEmpty && belt.lastItemId.isEmpty) return false;
    if (belt.deadEndFreezeProgress != null) return true;
    if (belt.lastItemFreezeProgress != null) return true;
    if (belt.itemFillCount >= belt.path.length &&
        belt.itemDrainCount < belt.itemFillCount - 1) {
      return true;
    }
    return false;
  }

  void _spawnItem() {
    final inputDirs = _connectedInputDirections;
    final outputConnected = _hasOutputBelt;

    if (inputDirs.isEmpty || !outputConnected) return;
    if (_isOutputBlocked) return;

    // 按循环顺序选择输入方向
    final inputDir = inputDirs[_spawnCounter % inputDirs.length];
    _spawnCounter++;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    final curveAnim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    final anim = _ConvergerItemAnim(
      controller: controller,
      curveAnim: curveAnim,
      itemId: _itemIdForInput(inputDir),
      inputDirection: inputDir,
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

  // ===== 等轴测投影（与分流器一致）=====

  Offset _project(double x, double y, double z, Offset center) {
    const double cos30 = 0.86602540378;
    const double sin30 = 0.5;
    return Offset(
      center.dx + (y - x) * cos30,
      center.dy + (x + y) * sin30 - z,
    );
  }

  /// 计算指定方向轨道末端在屏幕上的位置
  Offset _slotScreenPos(String direction, Offset center) {
    switch (direction) {
      case 'down': // 输出：+y 方向
        return _project(0, _trackLength, 0, center);
      case 'up': // -y 方向（输入）
        return _project(0, -_trackLength, 0, center);
      case 'left': // +x 方向（屏幕左下，输入）
        return _project(_trackLength, 0, 0, center);
      case 'right': // -x 方向（屏幕右上，输入）
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
                    final inputDirs = _connectedInputDirections;
                    final outputConnected = _hasOutputBelt;
                    final outputBlocked = _isOutputBlocked;

                    // 计算每条轨道状态：0=未连接(灰), 1=正常(绿), 2=堵塞(红)
                    int trackState(bool connected, bool blocked) {
                      if (!connected) return 0;
                      return blocked ? 2 : 1;
                    }

                    final sOutput = trackState(outputConnected, outputBlocked);
                    final sUp = trackState(inputDirs.contains('up'), _isInputBlocked('up'));
                    final sLeft = trackState(inputDirs.contains('left'), _isInputBlocked('left'));
                    final sRight = trackState(inputDirs.contains('right'), _isInputBlocked('right'));

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 等轴测 3D 轨道
                        AnimatedBuilder(
                          animation: _arrowController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: Size(
                                  constraints.maxWidth, constraints.maxHeight),
                              painter: _ConvergerTrackPainter(
                                animationValue: _arrowController.value,
                                trackLength: _trackLength,
                                trackWidth: _trackWidth,
                                outputState: sOutput,
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
                        ..._buildTrackEndSlots(center, inputDirs),
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
              Padding(
                padding: EdgeInsets.only(bottom: 56),
                child: Text(
                  '可让多条（最多3条）分支传送带的物品汇流至1条传送带的物流工具。',
                  style: TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ),
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
      final inputSlot = _slotScreenPos(anim.inputDirection, center);
      final outputSlot = _slotScreenPos('down', center);

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
        color: const Color(0xFF49B675).withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF49B675).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  List<Widget> _buildTrackEndSlots(
      Offset center, List<String> inputDirs) {
    final widgets = <Widget>[];

    // 输入格（左/上/右方向）
    for (final dir in const ['left', 'up', 'right']) {
      final isActive = inputDirs.contains(dir);
      final itemId = isActive ? _itemIdForInput(dir) : null;
      final item =
          itemId != null ? widget.dataLoader.getItem(itemId) : null;
      final pos = _slotScreenPos(dir, center);
      widgets.add(_buildSlotWidget(
        pos.dx, pos.dy, item, isActive,
      ));
    }

    // 输出格（下方 +y 方向）
    final outputConnected = _hasOutputBelt;
    final outputItemId = _itemIdForOutput();
    final outputItem =
        outputItemId != null ? widget.dataLoader.getItem(outputItemId) : null;
    final outputPos = _slotScreenPos('down', center);
    widgets.add(_buildSlotWidget(
      outputPos.dx, outputPos.dy, outputItem, outputConnected,
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

class _ConvergerItemAnim {
  final AnimationController controller;
  final Animation<double> curveAnim;
  final String? itemId;
  final String inputDirection;

  _ConvergerItemAnim({
    required this.controller,
    required this.curveAnim,
    this.itemId,
    required this.inputDirection,
  });
}

/// 汇流器轨道绘制器：等轴测 3D 投影，绘制 4 条半轨道。
///
/// 轨道方向（游戏坐标）：
/// - 输入左：+x 方向（屏幕左下），箭头向中心流动
/// - 输入上：-y 方向（屏幕左上），箭头向中心流动
/// - 输入右：-x 方向（屏幕右上），箭头向中心流动
/// - 输出下：+y 方向（屏幕右下），箭头向远端流动
class _ConvergerTrackPainter extends CustomPainter {
  final double animationValue;
  final double trackLength;
  final double trackWidth;
  // 每条轨道状态：0=未连接(灰), 1=正常(绿), 2=堵塞(红)
  final int outputState;
  final int upState;
  final int leftState;
  final int rightState;

  static const double _depthHeight = 10.0;
  static const double _centerFadeRatio = 0.8;
  static const double _endFadeRatio = 0.35;

  _ConvergerTrackPainter({
    required this.animationValue,
    required this.trackLength,
    required this.trackWidth,
    this.outputState = 0,
    this.upState = 0,
    this.leftState = 0,
    this.rightState = 0,
  });

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
    // left 映射到 +x（屏幕左下），right 映射到 -x（屏幕右上）
    _drawHalfTrack(canvas, center, 1, 0, leftState, animationValue,
        flowTowardCenter: true);
    _drawHalfTrack(canvas, center, 0, -1, upState, animationValue,
        flowTowardCenter: true);
    _drawHalfTrack(canvas, center, -1, 0, rightState, animationValue,
        flowTowardCenter: true);
    _drawHalfTrack(canvas, center, 0, 1, outputState, animationValue,
        flowTowardCenter: false);
  }

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
    final effectiveAnimValue = isActive && !isBlocked ? animValue : 0.0;

    final halfWidth = trackWidth / 2;
    final L = trackLength;

    final px = -dy;
    final py = dx;

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

    final gradBackOffset = halfWidth * 0.6;
    final gradStart = _project(-dx * gradBackOffset, -dy * gradBackOffset, 0, center);
    final gradEnd = _project(dx * L, dy * L, 0, center);

    // 汇流器使用绿色主题色
    final topColors = isBlocked
        ? const [
            Color(0x00CC2222),
            Color(0xAAFF3333),
            Color(0xAAFF3333),
            Color(0x00CC2222),
          ]
        : isActive
            ? const [
                Color(0x002E8B57),
                Color(0xAA49B675),
                Color(0xAA49B675),
                Color(0x002E8B57),
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

    final frontColors = isBlocked
        ? const [
            Color(0x00661111),
            Color(0xCC992222),
            Color(0xCC992222),
            Color(0x00661111),
          ]
        : isActive
            ? const [
                Color(0x001A5C3A),
                Color(0xCC2E7D52),
                Color(0xCC2E7D52),
                Color(0x001A5C3A),
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

    canvas.drawPath(frontPath, frontPaint);
    canvas.drawPath(topPath, trackPaint);

    final borderColors = isBlocked
        ? const [
            Color(0x00EE3333),
            Color(0xDDFF5555),
            Color(0xDDFF5555),
            Color(0x00EE3333),
          ]
        : isActive
            ? const [
                Color(0x0049B675),
                Color(0xDD6DD99A),
                Color(0xDD6DD99A),
                Color(0x0049B675),
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

    canvas.drawLine(p1, p2, borderPaint);
    canvas.drawLine(p4, p3, borderPaint);

    // 绘制流动箭头
    canvas.save();
    canvas.clipPath(topPath);

    final flowDx = flowTowardCenter ? -dx : dx;
    final flowDy = flowTowardCenter ? -dy : dy;
    final flowPerpX = -flowDy;
    final flowPerpY = flowDx;

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

      final arrowBaseColor = isBlocked
          ? const Color(0xFFFF5555)
          : isActive
              ? Colors.white
              : const Color(0xFF999999);
      final arrowPaint = Paint()
        ..color = arrowBaseColor.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      final progress = flowTowardCenter ? (1.0 - t) : t;
      final arrowCx = dx * progress * L;
      final arrowCy = dy * progress * L;

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
  bool shouldRepaint(covariant _ConvergerTrackPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.outputState != outputState ||
        oldDelegate.upState != upState ||
        oldDelegate.leftState != leftState ||
        oldDelegate.rightState != rightState;
  }
}
