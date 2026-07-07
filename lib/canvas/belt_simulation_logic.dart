import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../state/project_notifier.dart';
import '../constants/app_constants.dart';
import '../AIC/equipment.dart';
import '../utils/error_handler.dart';
import 'canvas_editor.dart';

mixin BeltSimulationLogic on State<CanvasEditor> {
  // 跟踪每个传送带的上一帧 itemId，用于检测 itemId 变化
  final Map<String, String> _prevBeltItemIds = {};
  final Map<String, String> _prevBeltLastItemIds = {};

  // 传送带填充时钟：用于在 addListener 中检测 arrowProgress 跨零
  final Map<String, double> _prevBeltProgressForTick = {};

  // 汇流器 FCFS 逻辑时钟：物品到达传送带末端时分配递增序号，
  // 序号越小表示越早到达，汇流器优先处理序号最小的方向
  int _convergerArrivalCounter = 0;

  double _prevGlobalProgress = 0.0;

  ProjectState get _project => context.read<ProjectNotifier>().project;
  DataLoader get _dataLoader => context.read<DataLoader>();

  /// 传送带物品填充时钟滴答：每次 arrowProgress 跨零时触发
  /// 驱动所有传送带的 itemFillCount / itemDrainCount 增减
  // ignore: unused_element
  void _onBeltTick() {
    final buildings = _project.buildings;

    var inventoryChanged = false;
    for (final belt in _project.conveyors) {
      if (belt.isBlocked) continue;
      if (belt.path.isEmpty) continue;

      // 检测是否是断头传送带（终点未连接设备输入端口）
      final isDeadEnd =
          !TransportBeltRenderer.isInputPort(belt.path.last, buildings);
      final inputBuilding =
          isDeadEnd ? null : _findInputBuildingAtCell(belt.path.last);
      final pendingOutputItemId =
          inputBuilding == null ? null : belt.downstreamItemId();
      final inputBlocked = inputBuilding != null &&
          pendingOutputItemId != null &&
          !_canBeltOutputEnterBuilding(
            belt,
            inputBuilding,
            pendingOutputItemId,
          );
      final terminalLimit = inputBlocked ? belt.path.length - 1 : null;
      final sourceItemId = _getAvailableOutputItemIdForBeltStart(belt);
      final isProducing = sourceItemId != null && sourceItemId.isNotEmpty;

      belt.ensureItemSegmentsFromLegacy();
      if (isProducing) {
        final pushed =
            belt.pushSourceItem(sourceItemId, terminalLimit: terminalLimit);
        if (pushed) {
          inventoryChanged =
              _consumeOutputItemForBeltStart(belt, sourceItemId) ||
                  inventoryChanged;
        }
      }
      belt.advanceItemSegments(
        isDeadEnd: isDeadEnd || inputBuilding != null || inputBlocked,
        activeSourceItemId: isProducing ? sourceItemId : null,
        terminalLimit: terminalLimit,
      );
      if (inputBuilding != null) {
        inventoryChanged = _transferBeltOutputToBuilding(belt, inputBuilding) ||
            inventoryChanged;
        _freezeReadyOutputSegments(
          belt,
          limit: terminalLimit ?? belt.path.length,
        );
      }
      _prevBeltItemIds[belt.id] = belt.itemId;
      _prevBeltLastItemIds[belt.id] = belt.lastItemId;
    }
    // 确保重绘（当从 AnimationController listener 触发时，ticker 可能已暂停）
    if (mounted) {
      if (inventoryChanged) {
        context.read<ProjectNotifier>().notifyChanged();
      }
      setState(() {});
    }
  }

  void onBeltAnimationFrame(double globalProgress) {
    // 计算本帧 globalProgress 增量（处理 0→1 循环回绕）
    double progressDelta = globalProgress - _prevGlobalProgress;
    if (progressDelta < 0) progressDelta += 1.0;
    _prevGlobalProgress = globalProgress;

    final activeIds = _project.conveyors.map((belt) => belt.id).toSet();
    _prevBeltProgressForTick.removeWhere((id, _) => !activeIds.contains(id));

    final buildings = _project.buildings;
    var inventoryChanged = false;
    var ticked = false;

    for (final belt in _project.conveyors) {
      final progress = belt.animationProgress(globalProgress);
      final previous = _prevBeltProgressForTick[belt.id] ?? progress;
      if (previous > 0.5 && progress < 0.5) {
        ticked = true;
        inventoryChanged =
            _tickSingleBeltOnce(belt, buildings) || inventoryChanged;
      }
      _prevBeltProgressForTick[belt.id] = progress;
    }

    if (!mounted || !ticked) return;
    if (inventoryChanged) {
      context.read<ProjectNotifier>().notifyChanged();
    }
    setState(() {});
  }

  bool _tickSingleBeltOnce(
    ConveyorBelt belt,
    List<PlacedBuilding> buildings,
  ) {
    if (belt.isBlocked) return false;
    if (belt.path.isEmpty) return false;

    final isDeadEnd =
        !TransportBeltRenderer.isInputPort(belt.path.last, buildings);
    var inputBuilding =
        isDeadEnd ? null : _findInputBuildingAtCell(belt.path.last);
    // 生产建筑输入端按断头传送带处理：物品不进入建筑，填满到端口格子后自然停止
    final bool isProductionDeadEnd = inputBuilding != null &&
        !inputBuilding.isBeltBridge &&
        !inputBuilding.isSplitter &&
        !inputBuilding.isConverger &&
        inputBuilding.building.id != DepotLoaderConfig.id;
    if (isProductionDeadEnd) {
      inputBuilding = null;
    }
    final pendingOutputItemId =
        inputBuilding == null ? null : belt.downstreamItemId();
    final inputBlocked = inputBuilding != null &&
        pendingOutputItemId != null &&
        !_canBeltOutputEnterBuilding(
          belt,
          inputBuilding,
          pendingOutputItemId,
        );
    final terminalLimit = inputBlocked ? belt.path.length - 1 : null;
    final sourceItemId = _getAvailableOutputItemIdForBeltStart(belt);
    final isProducing = sourceItemId != null && sourceItemId.isNotEmpty;

    var sourceExtendedThisTick = false;
    String? activeSourceItemId = isProducing ? sourceItemId : null;
    if (!isProducing && belt.itemSegments.isNotEmpty) {
      final firstSegment = belt.itemSegments.first;
      if (firstSegment.drainCount == 0) {
        if (firstSegment.skipAdvanceOnce) {
          firstSegment.skipAdvanceOnce = false;
          activeSourceItemId = firstSegment.itemId;
          sourceExtendedThisTick = true;
        } else {
          final sourceBuilding = _findOutputBuildingAtCell(belt.path.first);
          if (sourceBuilding != null && sourceBuilding.isSplitter) {
            activeSourceItemId = firstSegment.itemId;
          }
        }
      }
    }

    var inventoryChanged = false;
    belt.ensureItemSegmentsFromLegacy();

    // 本带是否为被锁定补货带（后端消耗后按轮询锁定的那条输入带）。
    // 锁定带补货时不合段（pushSourceItem）、不推进源段（advanceItemSegments
    // freezeSourceAdvance），避免第2个物品被压向末端后因设备又满而被重新冻结
    // （视觉"走到输入端被刷新弹回"）。只有末段通过 clearing→null→drainCount++
    // 自然前进进入设备。
    final isLockedRefill =
        inputBuilding != null && inputBuilding.lockedInputBeltId == belt.id;

    // 输入端阻塞（inputBlocked）时，terminalLimit 已限制物品推进上限
    // （path.length-1），物品在端口前一格冻结。此时仍应从源推送，
    // 让物品在传送带上排队填满到 terminalLimit 为止，再自然停止。
    // 否则传送带上只有一个初始物品，不会形成满带队列。
    // 锁定带补货时跳过 pushSourceItem（不合段，不把第2个物品压入末端）。
    if (isProducing && !isLockedRefill) {
      final pushed =
          belt.pushSourceItem(sourceItemId, terminalLimit: terminalLimit);
      if (pushed) {
        sourceExtendedThisTick = true;
        inventoryChanged = _consumeOutputItemForBeltStart(belt, sourceItemId) ||
            inventoryChanged;
      }
    }

    belt.advanceItemSegments(
      isDeadEnd: isDeadEnd || isProductionDeadEnd || inputBuilding != null || inputBlocked,
      activeSourceItemId: activeSourceItemId,
      terminalLimit: terminalLimit,
      sourceExtendedThisTick: sourceExtendedThisTick,
      freezeSourceAdvance: isLockedRefill,
    );

    if (inputBuilding != null) {
      inventoryChanged = _transferBeltOutputToBuilding(belt, inputBuilding) ||
          inventoryChanged;
      _freezeReadyOutputSegments(
        belt,
        limit: terminalLimit ?? belt.path.length,
      );
    } else if (isDeadEnd || isProductionDeadEnd) {
      belt.freezeDeadEndSegments();
    }
    _prevBeltItemIds[belt.id] = belt.itemId;
    _prevBeltLastItemIds[belt.id] = belt.lastItemId;
    // 输出端诊断日志：当带的末端有冻结物品但本 tick 没有传输时，记录冻结状态，
    // 用于诊断"延展断头带后物品不流动"等问题。仅在状态变化时输出（缓存防刷屏）。
    _logBeltTerminalState(belt, isDeadEnd || isProductionDeadEnd, inputBuilding != null, inputBlocked,
        terminalLimit);
    return inventoryChanged;
  }

  /// 输出端带末端状态诊断日志缓存（key=belt.id, value=状态签名）。
  final Map<String, String> _beltTerminalStateCache = {};

  void _logBeltTerminalState(ConveyorBelt belt, bool isDeadEnd,
      bool hasInputBuilding, bool inputBlocked, int? terminalLimit) {
    belt.ensureItemSegmentsFromLegacy();
    if (belt.itemSegments.isEmpty) return;
    final last = belt.itemSegments.last;
    if (!last.hasItems) return;
    final sig =
        '${belt.path.length}|$isDeadEnd|$hasInputBuilding|$inputBlocked|$terminalLimit|'
        '${last.fillCount}|${last.drainCount}|${last.freezeProgress}';
    if (_beltTerminalStateCache[belt.id] == sig) return;
    _beltTerminalStateCache[belt.id] = sig;
    Logger.debug(
        '[Prod] 带末端状态: belt=${belt.id}, pathLen=${belt.path.length}, '
        'isDeadEnd=$isDeadEnd, hasInputBldg=$hasInputBuilding, '
        'inputBlocked=$inputBlocked, terminalLimit=$terminalLimit, '
        'lastSeg fill=${last.fillCount} drain=${last.drainCount} '
        'freeze=${last.freezeProgress}');
  }

  bool _canBeltOutputEnterBuilding(
    ConveyorBelt belt,
    PlacedBuilding building,
    String itemId,
  ) {
    if (building.isBeltBridge) {
      final outputDirection = _beltArrivalDirection(belt);
      return outputDirection != null &&
          building.canAcceptBridgeInputItem(itemId, outputDirection);
    }
    // 分流器：纯推送式，无内部缓冲。
    // 仅当至少有一条输出传送带可实际接收物品时才允许进入，
    // 否则直接阻塞输入端（物品在传送带上排队等待）。
    if (building.isSplitter) {
      final connectedDirs = _getConnectedSplitterOutputDirections(building);
      if (connectedDirs.isEmpty) return false;
      for (final dir in connectedDirs) {
        final outputBelt = _getBeltForSplitterOutputDirection(building, dir);
        if (outputBelt != null && _canSplitterOutputBeltAcceptItem(outputBelt, itemId)) {
          return true;
        }
      }
      return false;
    }
    if (building.isConverger) {
      final outputBelt = _getBeltForConvergerOutputDirection(building);
      return outputBelt != null;
    }
    // 仓库存货口始终可以接收物品（直接进入全局仓库库存）
    if (building.building.id == DepotLoaderConfig.id) return true;
    // 生产建筑：不接收物品（生产逻辑已移除）
    return false;
  }

  String? _beltExitDirection(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      return _directionBetween(belt.path.first, belt.path[1]);
    }
    return belt.forcedDirection;
  }

  /// 获取分流器已连接的输出传送带方向列表
  /// 通过查找所有起点在分流器格子上的传送带的出口方向来确定
  List<String> _getConnectedSplitterOutputDirections(PlacedBuilding splitter) {
    final splitterCell =
        Offset(splitter.gridX.toDouble(), splitter.gridY.toDouble());
    final directions = <String>[];
    for (final belt in _project.conveyors) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == splitterCell.dx.round() &&
          start.dy.round() == splitterCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir != null && !directions.contains(exitDir)) {
          directions.add(exitDir);
        }
      }
    }
    return directions;
  }

  /// 获取分流器指定输出方向上的传送带
  ConveyorBelt? _getBeltForSplitterOutputDirection(
      PlacedBuilding splitter, String direction) {
    final splitterCell =
        Offset(splitter.gridX.toDouble(), splitter.gridY.toDouble());
    for (final belt in _project.conveyors) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == splitterCell.dx.round() &&
          start.dy.round() == splitterCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == direction) return belt;
      }
    }
    return null;
  }

  /// 检查分流器输出传送带是否可以接收新物品
  /// 综合考虑传送带起始端空间和末端阻塞情况
  bool _canSplitterOutputBeltAcceptItem(ConveyorBelt belt, String itemId) {
    if (belt.path.isEmpty || itemId.isEmpty) return false;

    belt.ensureItemSegmentsFromLegacy();

    // 计算末端阻塞情况（与 _tickSingleBeltOnce 相同的逻辑）
    final isDeadEnd =
        !TransportBeltRenderer.isInputPort(belt.path.last, _project.buildings);
    final inputBuilding =
        isDeadEnd ? null : _findInputBuildingAtCell(belt.path.last);
    final pendingOutputItemId =
        inputBuilding == null ? null : belt.downstreamItemId();
    final inputBlocked = inputBuilding != null &&
        pendingOutputItemId != null &&
        !_canBeltOutputEnterBuilding(belt, inputBuilding, pendingOutputItemId);
    final terminalLimit = inputBlocked ? belt.path.length - 1 : null;

    final result = belt.canAcceptNewItemFromStart(itemId, terminalLimit: terminalLimit);
    return result;
  }

  /// 查找分流器下一个可用的输出方向（不更新循环索引）
  /// 按输出传送带创建顺序循环，跳过无传送带和满传送带的方向
  String? _peekNextAvailableSplitterDirection(
      PlacedBuilding splitter, String itemId) {
    final cycleOrder = _getConnectedSplitterOutputDirections(splitter);
    if (cycleOrder.isEmpty) return null;

    for (int offset = 0; offset < cycleOrder.length; offset++) {
      final index =
          (splitter.splitterCycleIndex + offset) % cycleOrder.length;
      final direction = cycleOrder[index];

      // 查找该方向的输出传送带
      final belt =
          _getBeltForSplitterOutputDirection(splitter, direction);
      if (belt == null) continue;

      // 检查传送带是否可以接收物品
      if (_canSplitterOutputBeltAcceptItem(belt, itemId)) {
        return direction;
      }
    }

    return null;
  }

  /// 查找分流器下一个可用的输出方向并更新循环索引
  String? _findNextAvailableSplitterDirection(
      PlacedBuilding splitter, String itemId) {
    final direction = _peekNextAvailableSplitterDirection(splitter, itemId);
    if (direction == null) return null;

    // 更新循环索引到选定方向之后（按创建顺序）
    final cycleOrder = _getConnectedSplitterOutputDirections(splitter);
    final index = cycleOrder.indexOf(direction);
    if (index >= 0) {
      splitter.splitterCycleIndex = (index + 1) % cycleOrder.length;
    }
    return direction;
  }

  /// 尝试将分流器缓冲槽位中的物品推送到已变为可用的输出带上
  void _drainSplitterBuffer(PlacedBuilding splitter) {
    if (!splitter.splitterBufferOccupied) return;
    final itemId = splitter.splitterBufferedItemId;
    if (itemId == null || itemId.isEmpty) return;

    // 检查缓冲物品的目标方向是否已可用
    final bufferedDir = splitter.splitterBufferedDirection;
    if (bufferedDir != null) {
      final belt = _getBeltForSplitterOutputDirection(splitter, bufferedDir);
      if (belt != null && _canSplitterOutputBeltAcceptItem(belt, itemId)) {
        final terminalLimit = _calculateBeltTerminalLimit(belt);
        if (belt.pushSourceItem(itemId, terminalLimit: terminalLimit)) {
          splitter.consumeFromBuffer();
          return;
        }
      }
    }
    // 目标方向仍满：尝试其他连通方向（按创建顺序）
    final cycleOrder = _getConnectedSplitterOutputDirections(splitter);
    for (int offset = 0; offset < cycleOrder.length; offset++) {
      final index =
          (splitter.splitterCycleIndex + offset) % cycleOrder.length;
      final direction = cycleOrder[index];
      final belt = _getBeltForSplitterOutputDirection(splitter, direction);
      if (belt == null) continue;
      if (!_canSplitterOutputBeltAcceptItem(belt, itemId)) continue;
      final terminalLimit = _calculateBeltTerminalLimit(belt);
      if (belt.pushSourceItem(itemId, terminalLimit: terminalLimit)) {
        splitter.consumeFromBuffer();
        // 不更新 cycleIndex：缓冲排出不改变正常的轮询顺序
        return;
      }
    }
  }

  // ===== 汇流器（Converger）仿真逻辑 =====

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

  /// 获取汇流器已连接的输入传送带方向列表（输入端口方向：left/up/right）
  /// 通过查找所有终点在汇流器格子上的传送带的到达方向来确定
  List<String> _getConnectedConvergerInputDirections(PlacedBuilding converger) {
    final convergerCell =
        Offset(converger.gridX.toDouble(), converger.gridY.toDouble());
    final directions = <String>[];
    for (final belt in _project.conveyors) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == convergerCell.dx.round() &&
          end.dy.round() == convergerCell.dy.round()) {
        final arrivalDir = _beltArrivalDirection(belt);
        if (arrivalDir != null) {
          final inputPort = _arrivalDirToInputPort(arrivalDir);
          // 排除输出方向 down（输出传送带终点不在汇流器格子上，此处为安全检查）
          if (inputPort != 'down' && !directions.contains(inputPort)) {
            directions.add(inputPort);
          }
        }
      }
    }
    return directions;
  }

  /// 获取汇流器指定输入端口方向上的传送带
  /// direction 参数为输入端口方向（left/up/right）
  ConveyorBelt? _getBeltForConvergerInputDirection(
      PlacedBuilding converger, String direction) {
    final convergerCell =
        Offset(converger.gridX.toDouble(), converger.gridY.toDouble());
    // 输入端口方向转换为到达方向来匹配传送带
    final targetArrivalDir = _inputPortToArrivalDir(direction);
    for (final belt in _project.conveyors) {
      if (belt.path.isEmpty) continue;
      final end = belt.path.last;
      if (end.dx.round() == convergerCell.dx.round() &&
          end.dy.round() == convergerCell.dy.round()) {
        final arrivalDir = _beltArrivalDirection(belt);
        if (arrivalDir == targetArrivalDir) return belt;
      }
    }
    return null;
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

  /// 获取汇流器输出方向上的传送带（唯一输出，方向为 down）
  ConveyorBelt? _getBeltForConvergerOutputDirection(
      PlacedBuilding converger) {
    final convergerCell =
        Offset(converger.gridX.toDouble(), converger.gridY.toDouble());
    for (final belt in _project.conveyors) {
      if (belt.path.isEmpty) continue;
      final start = belt.path.first;
      if (start.dx.round() == convergerCell.dx.round() &&
          start.dy.round() == convergerCell.dy.round()) {
        final exitDir = _beltExitDirection(belt);
        if (exitDir == 'down') return belt;
      }
    }
    return null;
  }

  /// FCFS（先到先得）：查找汇流器所有输入中，物品最早到达末端的方向。
  ///
  /// 工作流程：
  /// 1. 清理不再有物品到达末端的方向的时间戳（物品已被取走或传送带空了）
  /// 2. 为有物品到达末端但尚未记录时间戳的方向分配递增序号
  /// 3. 返回序号最小（最早到达）的方向
  ///
  /// 这样确保无论传送带长度和速率如何，始终遵循"先到先得"原则：
  /// 物品先到达传送带末端的方向优先被汇流器处理。
  String? _findEarliestArrivalConvergerDirection(PlacedBuilding converger) {
    final connectedDirs = _getConnectedConvergerInputDirections(converger);
    if (connectedDirs.isEmpty) return null;

    // 1. 清理不再有物品到达末端的方向的时间戳
    final expiredDirs = <String>[];
    for (final entry in converger.convergerArrivalTimestamps.entries) {
      final dir = entry.key;
      final belt = _getBeltForConvergerInputDirection(converger, dir);
      if (belt == null || belt.outputReadyItemId() == null) {
        expiredDirs.add(dir);
      }
    }
    for (final dir in expiredDirs) {
      converger.convergerArrivalTimestamps.remove(dir);
    }

    // 2. 为有物品到达末端但尚未记录时间戳的方向分配序号
    for (final dir in connectedDirs) {
      if (converger.convergerArrivalTimestamps.containsKey(dir)) continue;
      final belt = _getBeltForConvergerInputDirection(converger, dir);
      if (belt == null) continue;
      final itemId = belt.outputReadyItemId();
      if (itemId == null || itemId.isEmpty) continue;
      converger.convergerArrivalTimestamps[dir] = _convergerArrivalCounter++;
    }

    // 3. 返回序号最小（最早到达）的方向
    if (converger.convergerArrivalTimestamps.isEmpty) return null;

    String? earliestDir;
    int? earliestTime;
    for (final entry in converger.convergerArrivalTimestamps.entries) {
      if (earliestTime == null || entry.value < earliestTime) {
        earliestTime = entry.value;
        earliestDir = entry.key;
      }
    }

    return earliestDir;
  }

  /// 判断汇流器输出带是否准备好接收下一个物品（上一个物品已走出遮挡格）
  bool _isConvergerReadyForNextItem(ConveyorBelt outputBelt) {
    outputBelt.ensureItemSegmentsFromLegacy();
    if (outputBelt.itemSegments.isEmpty) return true;
    final first = outputBelt.itemSegments.first;
    return first.drainCount >= 1;
  }

  String? _beltArrivalDirection(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      return _directionBetween(
        belt.path[belt.path.length - 2],
        belt.path.last,
      );
    }
    return belt.incomingDirection;
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

  PlacedBuilding? _findInputBuildingAtCell(Offset cell) {
    final gx = cell.dx.round();
    final gy = cell.dy.round();
    for (final pb in _project.buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in pb.inputPorts) {
        final portCell = port.gridPosition(
          pb.gridX,
          pb.gridY,
          gw,
          gh,
          rotation: rot,
        );
        if (portCell.dx.round() == gx && portCell.dy.round() == gy) {
          return pb;
        }
      }
    }
    return null;
  }

  /// 查找指定格子上的输出端口建筑（用于识别分流器源）
  PlacedBuilding? _findOutputBuildingAtCell(Offset cell) {
    final gx = cell.dx.round();
    final gy = cell.dy.round();
    for (final pb in _project.buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (final port in pb.outputPorts) {
        final portCell = port.gridPosition(
          pb.gridX,
          pb.gridY,
          gw,
          gh,
          rotation: rot,
        );
        if (portCell.dx.round() == gx && portCell.dy.round() == gy) {
          return pb;
        }
      }
    }
    return null;
  }

  /// 计算传送带的末端阻塞限制
  /// 用于分流器推送时确定输出带可接收物品的位置上限
  int? _calculateBeltTerminalLimit(ConveyorBelt belt) {
    if (belt.path.isEmpty) return null;
    final isDeadEnd =
        !TransportBeltRenderer.isInputPort(belt.path.last, _project.buildings);
    final inputBuilding =
        isDeadEnd ? null : _findInputBuildingAtCell(belt.path.last);
    final pendingOutputItemId =
        inputBuilding == null ? null : belt.downstreamItemId();
    final inputBlocked = inputBuilding != null &&
        pendingOutputItemId != null &&
        !_canBeltOutputEnterBuilding(belt, inputBuilding, pendingOutputItemId);
    return inputBlocked ? belt.path.length - 1 : null;
  }

  bool _transferBeltOutputToBuilding(
      ConveyorBelt belt, PlacedBuilding building) {
    if (building.building.maxInputs <= 0) return false;
    final itemId = belt.outputReadyItemId();
    if (itemId == null) return false;

    // 若建筑当前不可接收（如分流器缓冲槽已满），则不尝试传输
    if (!_canBeltOutputEnterBuilding(belt, building, itemId)) return false;

    // 兜底守卫：输入端达到容量上限时直接拒绝传输。
    // 防止主线程与 Isolate 异步同步导致的竞争：Isolate 同步可能短暂降低
    // inputItemCount，使 _canBeltOutputEnterBuilding 通过，但实际输入端已满。
    // 物流桥/分流器/汇流器/仓库有其独立的容量管理，不受此限制。
    if (building.inputItemCount >= PlacedBuilding.maxInputItemCount &&
        !building.isBeltBridge &&
        !building.isSplitter &&
        !building.isConverger &&
        building.building.id != DepotLoaderConfig.id) {
      return false;
    }

    if (building.isBeltBridge) {
      final outputDirection = _beltArrivalDirection(belt);
      if (outputDirection == null) return false;
      if (!building.acceptBridgeInputItem(itemId, outputDirection)) {
        return false;
      }
      belt.removeOutputReadyItem();
      return true;
    }
    // 分流器：纯推送式，无内部缓冲。直接推到输出带，全满则阻塞输入端。
    if (building.isSplitter) {
      final direction = _findNextAvailableSplitterDirection(building, itemId);
      if (direction != null) {
        final outputBelt =
            _getBeltForSplitterOutputDirection(building, direction);
        if (outputBelt != null) {
          final terminalLimit = _calculateBeltTerminalLimit(outputBelt);
          if (outputBelt.pushSourceItem(itemId, terminalLimit: terminalLimit, skipAdvanceOnce: true)) {
            belt.removeOutputReadyItem();
            return true;
          }
        }
        // 推送失败：回退 cycleIndex（按创建顺序）
        final cycleOrder = _getConnectedSplitterOutputDirections(building);
        final idx = cycleOrder.indexOf(direction);
        if (idx >= 0) {
          building.splitterCycleIndex = idx;
        }
      }
      return false;
    }
    // 汇流器：FCFS（先到先得）机制，基于物品到达末端的时间戳序号处理。
    // 一次只处理一个物品：物品到达传送带末端时记录到达序号，
    // 汇流器优先处理序号最小（最早到达）的方向。
    // 其他方向的物品在传送带末端排队等待，待当前处理完成后按到达顺序处理。
    // 输出带满时，物品在输入传送带末端排队，不使用内部缓冲。
    if (building.isConverger) {
      final arrivalDir = _beltArrivalDirection(belt);
      if (arrivalDir == null) return false;
      final inputPort = _arrivalDirToInputPort(arrivalDir);

      final earliestDir = _findEarliestArrivalConvergerDirection(building);
      if (earliestDir == null) return false;
      if (inputPort != earliestDir) return false;

      final outputBelt = _getBeltForConvergerOutputDirection(building);
      if (outputBelt == null) return false;

      if (!_isConvergerReadyForNextItem(outputBelt)) return false;

      final terminalLimit = _calculateBeltTerminalLimit(outputBelt);
      if (outputBelt.pushSourceItem(itemId, terminalLimit: terminalLimit)) {
        belt.removeOutputReadyItem();
        building.convergerArrivalTimestamps.remove(inputPort);
        return true;
      }
      return false;
    }
    // 仓库存货口：直接增加全局仓库库存，不受 inputItemCount 限制
    if (building.building.id == DepotLoaderConfig.id) {
      _project.incrementWarehouseItem(itemId);
      belt.removeOutputReadyItem();
      return true;
    }
    // 生产建筑：不接收物品（生产逻辑已移除）
    return false;
  }

  void _freezeReadyOutputSegments(ConveyorBelt belt, {required int limit}) {
    belt.ensureItemSegmentsFromLegacy();
    if (belt.itemSegments.isEmpty) {
      belt.syncLegacyFromSegments();
      return;
    }
    belt.itemSegments.sort((a, b) => a.drainCount.compareTo(b.drainCount));
    final endLimit = limit.clamp(0, belt.path.length).toInt();
    bool frozenAhead = false;
    for (int i = belt.itemSegments.length - 1; i >= 0; i--) {
      final segment = belt.itemSegments[i];
      if (!segment.hasItems) continue;
      final segLimit = i + 1 < belt.itemSegments.length
          ? belt.itemSegments[i + 1].drainCount.clamp(0, belt.path.length).toInt()
          : endLimit;
      final isLastSegment = i == belt.itemSegments.length - 1;
      final atLimit = segment.fillCount >= segLimit;
      final shouldFreeze = atLimit && (isLastSegment || frozenAhead);
      final fp = segment.freezeProgress;
      if (shouldFreeze && fp == null) {
        segment.freezeProgress = FreezeSentinels.newlyFrozen;
      }
      if (shouldFreeze && fp == FreezeSentinels.clearing) {
        segment.freezeProgress = FreezeSentinels.newlyFrozen;
      }
      // 冻结状态机推进（逻辑层主动推进全部过渡态，不依赖渲染器的 arrowProgress 条件）
      if (shouldFreeze && fp == FreezeSentinels.newlyFrozen) {
        segment.freezeProgress = FreezeSentinels.waiting;
      }
      if (shouldFreeze && fp == FreezeSentinels.waiting) {
        segment.freezeProgress = FreezeSentinels.midFrozen;
      }
      if (shouldFreeze && fp == FreezeSentinels.midFrozen) {
        segment.freezeProgress = FreezeSentinels.settled;
      }
      if (!shouldFreeze &&
          (fp == FreezeSentinels.newlyFrozen ||
              fp == FreezeSentinels.waiting ||
              fp == FreezeSentinels.midFrozen)) {
        segment.freezeProgress = FreezeSentinels.clearing;
      }
      if (!shouldFreeze && fp == FreezeSentinels.settled) {
        segment.freezeProgress = FreezeSentinels.clearing;
      }
      final newFp = segment.freezeProgress;
      frozenAhead = FreezeSentinels.isFreezing(newFp);
    }
    belt.syncLegacyFromSegments();
  }

  String? _getAvailableOutputItemIdForBeltStart(ConveyorBelt belt) {
    if (belt.path.isEmpty) return null;
    final start = belt.path.first;
    for (final pb in _project.buildings) {
      final outputIndex = _findOutputPortIndexAtCell(pb, start);
      if (outputIndex == null) continue;

      // 生产设备输出端诊断日志：看输出带是否能从设备拉取物品。
      if (!pb.isBeltBridge &&
          !pb.isSplitter &&
          !LogisticsUnitRenderer.isLogisticsUnit(pb.building.id) &&
          pb.building.id != DepotUnloaderConfig.id) {
        final recipe = pb.activeRecipeId != null
            ? _dataLoader.getRecipe(pb.activeRecipeId!)
            : null;
        if (recipe != null && recipe.outputs.isNotEmpty) {
          final output = recipe.outputs.length > outputIndex
              ? recipe.outputs[outputIndex]
              : recipe.outputs.first;
          Logger.debug(
              '[Prod] 输出带拉取检查: dev=${pb.id}, belt=${belt.id}, '
              'outputItem=${output.itemId}, hasOutput=${pb.hasOutputItem(output.itemId)}, '
              'outputTotal=${pb.totalOutputCount}');
        }
      }

      if (pb.isBeltBridge) {
        final outputDirection = _beltExitDirection(belt);
        return outputDirection == null
            ? null
            : pb.bridgeItemIdForOutputDirection(outputDirection);
      }

      // 分流器：若缓冲槽位中有物品，输出带从中拉取（作为生产者）
      if (pb.isSplitter) {
        if (pb.splitterBufferOccupied) {
          return pb.splitterBufferedItemId;
        }
        return null;
      }

      if (LogisticsUnitRenderer.isLogisticsUnit(pb.building.id)) {
        return pb.inputItemCount > 0 ? pb.inputItemId : null;
      }

      if (pb.building.id == DepotUnloaderConfig.id) {
        final itemId = pb.depotOutputItemId;
        if (itemId == null || itemId.isEmpty) return null;
        // 仓库库存为 0 时不再输出物品
        if (_project.getWarehouseItemCount(itemId) <= 0) return null;
        return itemId;
      }

      // 生产建筑：无产出（生产逻辑已移除）
      return null;
    }
    return null;
  }

  bool _consumeOutputItemForBeltStart(ConveyorBelt belt, String itemId) {
    if (belt.path.isEmpty || itemId.isEmpty) return false;
    final start = belt.path.first;
    for (final pb in _project.buildings) {
      final outputIndex = _findOutputPortIndexAtCell(pb, start);
      if (outputIndex == null) continue;
      if (pb.isBeltBridge) {
        final outputDirection = _beltExitDirection(belt);
        return outputDirection != null &&
            pb.consumeBridgeOutputItem(itemId, outputDirection);
      }
      // 分流器：消费缓冲槽位中的物品（仅当 belt 方向与缓冲方向匹配时）
      if (pb.isSplitter) {
        if (pb.splitterBufferOccupied) {
          pb.consumeFromBuffer();
          return true;
        }
        return false;
      }
      if (LogisticsUnitRenderer.isLogisticsUnit(pb.building.id)) {
        return pb.consumeInputItems(itemId, 1);
      }
      if (pb.building.id == DepotUnloaderConfig.id) {
        // 仓库取货口输出物品时减少全局仓库库存
        _project.decrementWarehouseItem(itemId);
        return false;
      }
      // 生产建筑：不消费（生产逻辑已移除）
      return false;
    }
    return false;
  }

  int? _findOutputPortIndexAtCell(PlacedBuilding pb, Offset cell) {
    final gx = cell.dx.round();
    final gy = cell.dy.round();
    final rot = pb.rotation;
    final gw = pb.building.gridWidth;
    final gh = pb.building.gridHeight;
    for (int i = 0; i < pb.outputPorts.length; i++) {
      final portCell = pb.outputPorts[i]
          .gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
      if (portCell.dx.round() == gx && portCell.dy.round() == gy) {
        return i;
      }
    }
    return null;
  }

}

