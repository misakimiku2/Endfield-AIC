import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'sim_protocol.dart';

/// 计算 Isolate 的入口函数
/// 必须是顶层函数或静态方法，才能被 Isolate.spawn 调用
void simWorkerEntry(SendPort mainSendPort) {
  final worker = _SimWorker(mainSendPort);
  worker._init();
}

class _SimWorker {
  final SendPort _mainSendPort;
  late ReceivePort _receivePort;
  Timer? _tickTimer;

  // 计算 Isolate 持有的状态副本（不可变数据）
  List<SimBuildingData> _buildings = [];
  List<SimConveyorData> _conveyors = [];
  List<SimRecipeData> _recipes = [];
  double _speedMultiplier = 1.0;
  bool _isRunning = false;

  static const double _tickRate = 20.0;
  static const double _cellSize = 48.0;
  static const double _portConnectionThreshold = 30.0;
  static const double _itemSpeed = 0.5; // 格/秒
  static const double _itemSpacing = 1.0; // 格

  // 可变状态：传送带物品列表（key = conveyor id）
  final Map<String, List<SimConveyorItemData>> _conveyorItems = {};

  // 可变状态：设备库存（key = building id）
  final Map<String, Map<String, int>> _buildingInputInventory = {};
  final Map<String, Map<String, int>> _buildingOutputInventory = {};

  // 可变状态：设备生产进度和阻塞标记
  final Map<String, bool> _buildingBlocked = {};
  final Map<String, double> _buildingProgress = {};

  // 可变状态：传送带流动进度
  final Map<String, double> _conveyorFlowProgress = {};

  _SimWorker(this._mainSendPort);

  void _init() {
    _receivePort = ReceivePort();
    // 发送 ReceivePort 给主 Isolate，建立双向通信
    _mainSendPort.send(_receivePort.sendPort);
    _receivePort.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'] as String;
      switch (type) {
        case 'sync':
          _onSync(message['data'] as Map<String, dynamic>);
          break;
        case 'start':
          _onStart();
          break;
        case 'stop':
          _onStop();
          break;
        case 'setSpeed':
          _speedMultiplier = (message['data']['speedMultiplier'] as num).toDouble();
          break;
      }
    }
  }

  void _onSync(Map<String, dynamic> data) {
    final state = SimSyncState.fromJson(data);
    _buildings = state.buildings;
    _conveyors = state.conveyors;
    _recipes = state.recipes;
    _speedMultiplier = state.speedMultiplier;

    // 同步传送带物品：保留已有物品，添加新传送带，移除已删除传送带
    final newConveyorIds = _conveyors.map((c) => c.id).toSet();
    _conveyorItems.removeWhere((id, _) => !newConveyorIds.contains(id));
    _conveyorFlowProgress.removeWhere((id, _) => !newConveyorIds.contains(id));
    for (final belt in _conveyors) {
      _conveyorItems.putIfAbsent(belt.id, () => List<SimConveyorItemData>.from(belt.items));
      _conveyorFlowProgress.putIfAbsent(belt.id, () => belt.flowProgress);
    }

    // 同步设备库存：保留已有库存，添加新设备，移除已删除设备
    final newBuildingIds = _buildings.map((b) => b.id).toSet();
    _buildingInputInventory.removeWhere((id, _) => !newBuildingIds.contains(id));
    _buildingOutputInventory.removeWhere((id, _) => !newBuildingIds.contains(id));
    _buildingBlocked.removeWhere((id, _) => !newBuildingIds.contains(id));
    _buildingProgress.removeWhere((id, _) => !newBuildingIds.contains(id));
    for (final pb in _buildings) {
      _buildingInputInventory.putIfAbsent(pb.id, () => Map<String, int>.from(pb.inputInventory));
      _buildingOutputInventory.putIfAbsent(pb.id, () => Map<String, int>.from(pb.outputInventory));
      _buildingBlocked.putIfAbsent(pb.id, () => false);
      _buildingProgress.putIfAbsent(pb.id, () => 0.0);
    }
  }

  void _onStart() {
    if (_isRunning) return;
    _isRunning = true;
    _tickTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _tickRate).round()),
      (_) => _onTick(),
    );
  }

  void _onStop() {
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  void _onTick() {
    final dt = _speedMultiplier / _tickRate;

    _updateConveyors(dt);
    _updateBuildings(dt);
    _outputToConveyors(dt);

    // 发送轻量结果回主 Isolate
    final result = SimTickResult(
      buildings: _buildings.map((b) => SimBuildingResult(
        id: b.id,
        isBlocked: _buildingBlocked[b.id] ?? false,
        productionProgress: _buildingProgress[b.id] ?? 0.0,
        inputInventory: Map<String, int>.from(_buildingInputInventory[b.id] ?? {}),
        outputInventory: Map<String, int>.from(_buildingOutputInventory[b.id] ?? {}),
      )).toList(),
      conveyors: _conveyors.map((c) => SimConveyorResult(
        id: c.id,
        items: List<SimConveyorItemData>.from(_conveyorItems[c.id] ?? []),
        flowProgress: _conveyorFlowProgress[c.id] ?? 0.0,
        isBlocked: false,
      )).toList(),
    );

    _mainSendPort.send(result.toJson());
  }

  // ============================================================
  // 传送带物品移动
  // ============================================================

  void _updateConveyors(double dt) {
    for (final belt in _conveyors) {
      // 更新流动进度（视觉效果）
      double flow = (_conveyorFlowProgress[belt.id] ?? 0.0) + dt * 60;
      if (flow > 100000) flow = 0.0;
      _conveyorFlowProgress[belt.id] = flow;

      if (belt.path.isEmpty) continue;
      final maxPosition = belt.path.length > 1 ? (belt.path.length - 1).toDouble() : 0.0;

      final items = _conveyorItems[belt.id] ?? [];

      // 按位置从高到低排序（前方物品先处理）
      items.sort((a, b) => b.position.compareTo(a.position));

      // 逐个移动物品
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        double newPosition = item.position + dt * _itemSpeed;

        // 检查前方物品间距
        if (i > 0) {
          final aheadItem = items[i - 1]; // 已排序，i-1 是前方物品
          final minPos = aheadItem.position - _itemSpacing;
          if (newPosition > minPos) {
            newPosition = minPos;
          }
        }

        // 不能超过最大位置
        if (newPosition > maxPosition) {
          newPosition = maxPosition;
        }

        items[i] = SimConveyorItemData(itemId: item.itemId, position: newPosition);
      }

      _conveyorItems[belt.id] = items;

      // 处理到达终点的物品
      _processArrival(belt, items, maxPosition);
    }
  }

  /// 处理传送带终点物品到达逻辑
  void _processArrival(SimConveyorData belt, List<SimConveyorItemData> items, double maxPosition) {
    if (items.isEmpty) return;

    final endWorldPos = _beltEnd(belt);

    // 找到在终点位置的物品（从前往后处理）
    final toRemove = <int>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.position < maxPosition) break; // 后面的物品更靠后，不可能到达终点

      // 检查终点是否连接到设备的输入端口
      final targetBuilding = _findBuildingAtInputPort(endWorldPos);
      if (targetBuilding != null) {
        if (targetBuilding.buildingId == 'depot_loader_3x1') {
          // 仓库入货口：物品被消耗
          toRemove.add(i);
        } else {
          // 普通设备输入端口：物品进入 inputInventory
          final inv = _buildingInputInventory[targetBuilding.id] ?? {};
          inv[item.itemId] = (inv[item.itemId] ?? 0) + 1;
          _buildingInputInventory[targetBuilding.id] = inv;
          toRemove.add(i);
        }
      }
      // 如果终点没有连接设备，物品停留在 maxPosition（堆积），阻塞后方物品
    }

    // 从后往前移除，避免索引偏移
    for (int i = toRemove.length - 1; i >= 0; i--) {
      items.removeAt(toRemove[i]);
    }

    _conveyorItems[belt.id] = items;
  }

  /// 查找输入端口位于指定世界坐标的设备
  SimBuildingData? _findBuildingAtInputPort(Offset worldPos) {
    for (final pb in _buildings) {
      for (final port in pb.inputPorts) {
        final portWorld = _portWorldPosition(port, pb);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  // ============================================================
  // 设备自动生产
  // ============================================================

  void _updateBuildings(double dt) {
    for (final pb in _buildings) {
      // 仓库取货口：持续输出物品到传送带（在 _outputToConveyors 中处理）
      if (pb.buildingId == 'depot_unloader_3x1') continue;

      // 仓库入货口：不需要生产逻辑
      if (pb.buildingId == 'depot_loader_3x1') continue;

      if (pb.activeRecipeId == null) continue;
      final recipe = _recipes.where((r) => r.id == pb.activeRecipeId).firstOrNull;
      if (recipe == null) continue;

      final progress = _buildingProgress[pb.id] ?? 0.0;

      // 如果正在生产中（progress > 0），继续推进进度直到完成
      if (progress > 0.0) {
        double newProgress = progress + dt / recipe.processTimeSeconds;

        if (newProgress >= 1.0) {
          newProgress = 0.0;
          // 产出物品到 outputInventory
          final outputInv = _buildingOutputInventory[pb.id] ?? {};
          for (final output in recipe.outputs) {
            outputInv[output.itemId] = (outputInv[output.itemId] ?? 0) + output.amount;
          }
          _buildingOutputInventory[pb.id] = outputInv;
        }

        _buildingProgress[pb.id] = newProgress;
        _buildingBlocked[pb.id] = false;
        continue;
      }

      // 进度为 0 时，检查 inputInventory 是否有足够的输入物品
      final inputInv = _buildingInputInventory[pb.id] ?? {};
      bool hasInputs = true;
      for (final input in recipe.inputs) {
        final available = inputInv[input.itemId] ?? 0;
        if (available < input.amount) {
          hasInputs = false;
          break;
        }
      }

      if (!hasInputs) {
        _buildingBlocked[pb.id] = true;
        _buildingProgress[pb.id] = 0.0;
        continue;
      }

      // 消耗输入并开始生产
      for (final input in recipe.inputs) {
        inputInv[input.itemId] = (inputInv[input.itemId] ?? 0) - input.amount;
        if (inputInv[input.itemId]! <= 0) {
          inputInv.remove(input.itemId);
        }
      }
      _buildingInputInventory[pb.id] = inputInv;

      _buildingBlocked[pb.id] = false;
      _buildingProgress[pb.id] = dt / recipe.processTimeSeconds;
    }
  }

  // ============================================================
  // 输出库存到传送带 & 仓库取货口持续输出
  // ============================================================

  void _outputToConveyors(double dt) {
    for (final pb in _buildings) {
      // 仓库取货口：持续输出
      if (pb.buildingId == 'depot_unloader_3x1') {
        if (pb.outputItemId == null || pb.outputItemId!.isEmpty) continue;
        _tryOutputItemToBelt(pb, pb.outputItemId!);
        continue;
      }

      // 普通设备：从 outputInventory 输出
      final outputInv = _buildingOutputInventory[pb.id];
      if (outputInv == null || outputInv.isEmpty) continue;

      // 复制 key 列表以避免并发修改
      final itemIds = outputInv.keys.toList();
      for (final itemId in itemIds) {
        final count = outputInv[itemId] ?? 0;
        if (count <= 0) continue;

        if (_tryOutputItemToBelt(pb, itemId)) {
          outputInv[itemId] = count - 1;
          if (outputInv[itemId]! <= 0) {
            outputInv.remove(itemId);
          }
        }
      }
    }
  }

  /// 尝试将一个物品从设备的输出端口放到连接的传送带上
  /// 返回 true 表示成功放置
  bool _tryOutputItemToBelt(SimBuildingData pb, String itemId) {
    for (final port in pb.outputPorts) {
      final portWorld = _portWorldPosition(port, pb);

      for (final belt in _conveyors) {
        // 传送带起点连接到设备输出端口
        if ((_beltStart(belt) - portWorld).distance < _portConnectionThreshold) {
          final items = _conveyorItems[belt.id] ?? [];

          // 检查传送带 position 0 附近是否为空（无物品在 1.0 范围内）
          bool position0Empty = true;
          for (final item in items) {
            if (item.position < _itemSpacing) {
              position0Empty = false;
              break;
            }
          }

          if (position0Empty) {
            items.add(SimConveyorItemData(itemId: itemId, position: 0.0));
            _conveyorItems[belt.id] = items;
            return true;
          }
        }
      }
    }
    return false;
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  Offset _portWorldPosition(SimPortData port, SimBuildingData pb) {
    double relativeX = port.relativeX;
    double relativeY = port.relativeY;

    double localGridX = (relativeX == 1.0) ? (pb.gridWidth - 1).toDouble() : (relativeX * pb.gridWidth).floorToDouble();
    double localGridY = (relativeY == 1.0) ? (pb.gridHeight - 1).toDouble() : (relativeY * pb.gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - pb.gridWidth / 2.0;
    double cy = ry - pb.gridHeight / 2.0;

    double rcx, rcy;
    switch (pb.rotation % 4) {
      case 1:
        rcx = -cy;
        rcy = cx;
        break;
      case 2:
        rcx = -cx;
        rcy = -cy;
        break;
      case 3:
        rcx = cy;
        rcy = -cx;
        break;
      case 0:
      default:
        rcx = cx;
        rcy = cy;
        break;
    }

    double wx = pb.gridX + rcx + pb.gridWidth / 2.0;
    double wy = pb.gridY + rcy + pb.gridHeight / 2.0;

    return Offset(wx * _cellSize, wy * _cellSize);
  }

  Offset _beltStart(SimConveyorData belt) {
    if (belt.path.isEmpty) return Offset.zero;
    return Offset(
      belt.path.first.dx * _cellSize + _cellSize / 2,
      belt.path.first.dy * _cellSize + _cellSize / 2,
    );
  }

  Offset _beltEnd(SimConveyorData belt) {
    if (belt.path.isEmpty) return Offset.zero;
    return Offset(
      belt.path.last.dx * _cellSize + _cellSize / 2,
      belt.path.last.dy * _cellSize + _cellSize / 2,
    );
  }
}
