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

  // 计算 Isolate 持有的状态副本
  List<SimBuildingData> _buildings = [];
  List<SimConveyorData> _conveyors = [];
  List<SimRecipeData> _recipes = [];
  double _speedMultiplier = 1.0;
  int _revision = 0;
  bool _isRunning = false;

  static const double _tickRate = 20.0;
  static const double _cellSize = 48.0;
  static const double _portConnectionThreshold = 30.0;

  _SimWorker(this._mainSendPort);

  bool _hasStoppedLastItems(SimConveyorData belt) {
    return belt.path.isNotEmpty &&
        belt.lastItemFillCount >= belt.path.length &&
        belt.lastItemFillCount > belt.lastItemDrainCount;
  }

  bool _hasOutputSpace(SimConveyorData belt) {
    if (belt.itemId.isNotEmpty) {
      return belt.itemDrainCount > 0 || belt.itemFillCount < belt.path.length;
    }
    if (!_hasStoppedLastItems(belt)) return true;
    return belt.lastItemDrainCount > 0;
  }

  SimBuildingData _copyBuilding(
    SimBuildingData pb, {
    String? activeRecipeId,
    String? inputItemId,
    int? inputItemCount,
    Map<String, int>? outputItems,
  }) {
    return SimBuildingData(
      id: pb.id,
      buildingId: pb.buildingId,
      gridX: pb.gridX,
      gridY: pb.gridY,
      rotation: pb.rotation,
      activeRecipeId: activeRecipeId ?? pb.activeRecipeId,
      depotOutputItemId: pb.depotOutputItemId,
      inputItemId: inputItemId ?? pb.inputItemId,
      inputItemCount: inputItemCount ?? pb.inputItemCount,
      outputItems: outputItems ?? pb.outputItems,
      gridWidth: pb.gridWidth,
      gridHeight: pb.gridHeight,
      inputPorts: pb.inputPorts,
      outputPorts: pb.outputPorts,
    );
  }

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
          _speedMultiplier =
              (message['data']['speedMultiplier'] as num).toDouble();
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
    _revision = state.revision;
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

    // 发送轻量结果回主 Isolate
    final result = SimTickResult(
      revision: _revision,
      buildings: _buildings
          .map((b) => SimBuildingResult(
                id: b.id,
                isBlocked: _buildingBlocked[b.id] ?? false,
                productionProgress: _buildingProgress[b.id] ?? 0.0,
                inputItemId: b.inputItemId,
                inputItemCount: b.inputItemCount,
                activeRecipeId: b.activeRecipeId,
                outputItems: b.outputItems,
              ))
          .toList(),
      conveyors: _conveyors
          .map((c) => SimConveyorResult(
                id: c.id,
                itemId: c.itemId,
                flowProgress: c.flowProgress,
                itemFillCount: c.itemFillCount,
                itemDrainCount: c.itemDrainCount,
                isBlocked: c.isBlocked,
                lastItemFillCount: c.lastItemFillCount,
                lastItemDrainCount: c.lastItemDrainCount,
                deadEndFreezeProgress: c.deadEndFreezeProgress,
                lastItemFreezeProgress: c.lastItemFreezeProgress,
              ))
          .toList(),
    );

    _mainSendPort.send(result.toJson());
  }

  // 临时存储计算结果，避免在 _buildings 上添加额外字段
  final Map<String, bool> _buildingBlocked = {};
  final Map<String, double> _buildingProgress = {};

  void _updateConveyors(double dt) {
    for (int i = 0; i < _conveyors.length; i++) {
      final belt = _conveyors[i];
      if (belt.isBlocked) continue;

      // 更新流动进度
      double newFlow = belt.flowProgress + dt * 60;
      if (newFlow > 100000) newFlow = 0;

      // 检查源设备是否阻塞
      final startPos = _beltStart(belt);
      final sourceBuilding = _findSourceBuilding(startPos);
      final bool blocked = sourceBuilding != null &&
          (_buildingBlocked[sourceBuilding.id] ?? false);

      _conveyors[i] = SimConveyorData(
        id: belt.id,
        path: belt.path,
        itemId: belt.itemId,
        flowProgress: newFlow,
        itemFillCount: belt.itemFillCount,
        itemDrainCount: belt.itemDrainCount,
        isBlocked: blocked,
        lastItemFillCount: belt.lastItemFillCount,
        lastItemDrainCount: belt.lastItemDrainCount,
        deadEndFreezeProgress: belt.deadEndFreezeProgress,
        lastItemFreezeProgress: belt.lastItemFreezeProgress,
      );
    }
  }

  void _updateBuildings(double dt) {
    for (int i = 0; i < _buildings.length; i++) {
      var pb = _buildings[i];

      // 仓库取货口：不需要配方，直接将 depotOutputItemId 推送到连接的传送带
      if (pb.buildingId == 'depot_unloader_3x1') {
        _produceDepotOutput(pb);
        continue;
      }

      // 自动匹配配方：当建筑没有激活配方但有输入物品时，自动选择匹配的配方
      if (pb.activeRecipeId == null &&
          pb.inputItemId.isNotEmpty &&
          pb.inputItemCount > 0) {
        final recipeId = _findMatchingRecipe(pb.buildingId, pb.inputItemId);
        if (recipeId != null) {
          pb = _copyBuilding(pb, activeRecipeId: recipeId);
          _buildings[i] = pb;
        }
      }

      if (pb.activeRecipeId == null) continue;
      final recipe =
          _recipes.where((r) => r.id == pb.activeRecipeId).firstOrNull;
      if (recipe == null) continue;

      var progress = _buildingProgress[pb.id] ?? 0.0;
      if (progress <= 0.0) {
        if (!_canAcceptRecipeOutputs(pb, recipe)) {
          _buildingBlocked[pb.id] = false;
          _buildingProgress[pb.id] = 0.0;
          continue;
        }

        if (!_checkInputsAvailable(pb, recipe)) {
          _buildingBlocked[pb.id] = false;
          _buildingProgress[pb.id] = 0.0;
          continue;
        }

        pb = _consumeInputs(pb, recipe);
        _buildings[i] = pb;
      }

      _buildingBlocked[pb.id] = false;
      final processTime =
          recipe.processTimeSeconds <= 0 ? 1.0 : recipe.processTimeSeconds;
      progress += dt / processTime;

      if (progress >= 1.0) {
        progress = 0.0;
        final newOutputItems = Map<String, int>.from(pb.outputItems);
        for (final output in recipe.outputs) {
          newOutputItems[output.itemId] =
              (newOutputItems[output.itemId] ?? 0) + output.amount;
        }
        pb = _copyBuilding(pb, outputItems: newOutputItems);
        _buildings[i] = pb;
      }

      _buildingProgress[pb.id] = progress;
    }
  }

  /// 根据建筑类型和输入物品查找匹配的配方ID
  bool _canAcceptRecipeOutputs(SimBuildingData pb, SimRecipeData recipe) {
    final totalOutputCount =
        pb.outputItems.values.fold<int>(0, (sum, count) => sum + count);
    final outputAmount =
        recipe.outputs.fold<int>(0, (sum, output) => sum + output.amount);
    return totalOutputCount + outputAmount <= 50;
  }

  String? _findMatchingRecipe(String buildingId, String inputItemId) {
    for (final recipe in _recipes) {
      if (!recipe.allowedBuildings.contains(buildingId)) continue;
      if (recipe.inputs.any((input) => input.itemId == inputItemId)) {
        return recipe.id;
      }
    }
    return null;
  }

  /// 仓库取货口：将 depotOutputItemId 推送到连接的空传送带
  void _produceDepotOutput(SimBuildingData pb) {
    final outputItemId = pb.depotOutputItemId;
    if (outputItemId.isEmpty) return;
    for (final port in pb.outputPorts) {
      final portWorld = _portWorldPosition(port, pb);
      for (int i = 0; i < _conveyors.length; i++) {
        final belt = _conveyors[i];
        if ((_beltStart(belt) - portWorld).distance <
            _portConnectionThreshold) {
          if (_hasOutputSpace(belt)) {
            _conveyors[i] = SimConveyorData(
              id: belt.id,
              path: belt.path,
              itemId: outputItemId,
              flowProgress: belt.flowProgress,
              itemFillCount: belt.itemFillCount,
              itemDrainCount: belt.itemDrainCount,
              isBlocked: belt.isBlocked,
              lastItemFillCount: belt.lastItemFillCount,
              lastItemDrainCount: belt.lastItemDrainCount,
              deadEndFreezeProgress: belt.deadEndFreezeProgress,
              lastItemFreezeProgress: belt.lastItemFreezeProgress,
            );
          }
        }
      }
    }
  }

  bool _checkInputsAvailable(SimBuildingData pb, SimRecipeData recipe) {
    for (final input in recipe.inputs) {
      if (pb.inputItemId != input.itemId || pb.inputItemCount < input.amount) {
        return false;
      }
    }
    return true;
  }

  SimBuildingData _consumeInputs(SimBuildingData pb, SimRecipeData recipe) {
    var nextInputItemId = pb.inputItemId;
    var nextInputItemCount = pb.inputItemCount;
    for (final input in recipe.inputs) {
      if (nextInputItemId != input.itemId ||
          nextInputItemCount < input.amount) {
        return pb;
      }
      nextInputItemCount -= input.amount;
    }
    if (nextInputItemCount <= 0) {
      nextInputItemCount = 0;
      nextInputItemId = '';
    }

    return _copyBuilding(
      pb,
      inputItemId: nextInputItemId,
      inputItemCount: nextInputItemCount,
    );
  }

  /// 将输出库存中的物品推送到连接的传送带
  void _pushOutputToBelts(SimBuildingData pb, int buildingIndex) {
    if (pb.outputItems.isEmpty) return;
    final recipe = _recipes.where((r) => r.id == pb.activeRecipeId).firstOrNull;
    if (recipe == null) return;

    var remainingItems = Map<String, int>.from(pb.outputItems);

    for (final port in pb.outputPorts) {
      if (remainingItems.isEmpty) break;
      final portWorld = _portWorldPosition(port, pb);
      for (int ci = 0; ci < _conveyors.length; ci++) {
        if (remainingItems.isEmpty) break;
        final belt = _conveyors[ci];
        if ((_beltStart(belt) - portWorld).distance <
            _portConnectionThreshold) {
          if (!_hasOutputSpace(belt)) continue;
          // 按配方输出顺序确定该端口应推送的物品
          final outputIndex = port.index;
          final output = outputIndex < recipe.outputs.length
              ? recipe.outputs[outputIndex]
              : recipe.outputs.first;
          if (remainingItems[output.itemId] == null ||
              remainingItems[output.itemId]! <= 0) continue;
          // 推送物品：保留传送带现有状态，只更新 itemId
          _conveyors[ci] = SimConveyorData(
            id: belt.id,
            path: belt.path,
            itemId: belt.itemId.isNotEmpty ? belt.itemId : output.itemId,
            flowProgress: belt.flowProgress,
            itemFillCount: belt.itemFillCount,
            itemDrainCount: belt.itemDrainCount,
            isBlocked: belt.isBlocked,
            lastItemFillCount: belt.lastItemFillCount,
            lastItemDrainCount: belt.lastItemDrainCount,
            deadEndFreezeProgress: belt.deadEndFreezeProgress,
            lastItemFreezeProgress: belt.lastItemFreezeProgress,
          );
          remainingItems[output.itemId] = remainingItems[output.itemId]! - 1;
          if (remainingItems[output.itemId]! <= 0) {
            remainingItems.remove(output.itemId);
          }
          break;
        }
      }
    }

    // 更新建筑的输出库存
    _buildings[buildingIndex] = SimBuildingData(
      id: pb.id,
      buildingId: pb.buildingId,
      gridX: pb.gridX,
      gridY: pb.gridY,
      rotation: pb.rotation,
      activeRecipeId: pb.activeRecipeId,
      depotOutputItemId: pb.depotOutputItemId,
      inputItemId: pb.inputItemId,
      inputItemCount: pb.inputItemCount,
      outputItems: remainingItems,
      gridWidth: pb.gridWidth,
      gridHeight: pb.gridHeight,
      inputPorts: pb.inputPorts,
      outputPorts: pb.outputPorts,
    );
  }

  // === 辅助方法 ===

  SimBuildingData? _findSourceBuilding(Offset worldPos) {
    for (final pb in _buildings) {
      for (final port in pb.outputPorts) {
        final portWorld = _portWorldPosition(port, pb);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  Offset _portWorldPosition(SimPortData port, SimBuildingData pb) {
    double relativeX = port.relativeX;
    double relativeY = port.relativeY;

    double localGridX = (relativeX == 1.0)
        ? (pb.gridWidth - 1).toDouble()
        : (relativeX * pb.gridWidth).floorToDouble();
    double localGridY = (relativeY == 1.0)
        ? (pb.gridHeight - 1).toDouble()
        : (relativeY * pb.gridHeight).floorToDouble();

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
