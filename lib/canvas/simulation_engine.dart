import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import 'sim_protocol.dart';
import 'sim_worker.dart';

class SimulationEngine extends ChangeNotifier {
  final DataLoader _dataLoader;
  ProjectState? _project;
  bool _isRunning = false;
  double _speedMultiplier = 1.0;

  // Isolate 模式（原生平台）
  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription? _mainSubscription;
  bool _isolateReady = false;

  // 主线程回退模式（Web 平台）
  Timer? _fallbackTimer;
  static const double _tickRate = 20.0;
  static const double _cellSize = 48.0;
  static const double _portConnectionThreshold = 30.0;
  static const double _itemSpeed = 0.5; // 格/秒
  static const double _itemSpacing = 1.0; // 格

  bool get isRunning => _isRunning;
  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double v) {
    _speedMultiplier = v.clamp(0.25, 10.0);
    if (_isolateReady) {
      _sendControl('setSpeed', {'speedMultiplier': _speedMultiplier});
    }
    notifyListeners();
  }

  SimulationEngine(this._dataLoader);

  /// 初始化：原生平台启动 Isolate，Web 平台使用主线程回退
  Future<void> init() async {
    if (kIsWeb) {
      // Web 平台不支持 Isolate，使用主线程回退
      return;
    }

    try {
      _mainReceivePort = ReceivePort();
      _mainSubscription = _mainReceivePort!.listen(_onMessageFromWorker);

      _isolate = await Isolate.spawn(
        simWorkerEntry,
        _mainReceivePort!.sendPort,
      );
    } catch (e) {
      debugPrint('[SimulationEngine] Isolate 初始化失败，回退到主线程模式: $e');
      _mainSubscription?.cancel();
      _mainReceivePort?.close();
      _mainReceivePort = null;
      _isolate = null;
    }
  }

  void _onMessageFromWorker(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      _isolateReady = true;
      // Isolate 就绪后同步当前状态
      _syncState();
      return;
    }

    if (message is Map<String, dynamic>) {
      final result = SimTickResult.fromJson(message);
      _applyTickResult(result);
      notifyListeners();
    }
  }

  /// 将 tick 结果应用到主线程的 project 数据
  void _applyTickResult(SimTickResult result) {
    if (_project == null) return;

    for (final br in result.buildings) {
      final pb = _project!.buildings.where((b) => b.id == br.id).firstOrNull;
      if (pb != null) {
        pb.isBlocked = br.isBlocked;
        pb.productionProgress = br.productionProgress;
        pb.inputInventory = Map<String, int>.from(br.inputInventory);
        pb.outputInventory = Map<String, int>.from(br.outputInventory);
      }
    }

    for (final cr in result.conveyors) {
      final belt = _project!.conveyors.where((c) => c.id == cr.id).firstOrNull;
      if (belt != null) {
        belt.items = cr.items
            .map((i) => ConveyorItem(itemId: i.itemId, position: i.position))
            .toList();
        belt.flowProgress = cr.flowProgress;
        belt.isBlocked = cr.isBlocked;
      }
    }
  }

  void attach(ProjectState project) {
    _project = project;
    if (_isolateReady) {
      _syncState();
    }
  }

  /// 请求重新同步状态到计算 Isolate
  /// 当用户在仿真运行中修改了 outputItemId、activeRecipeId 等配置时调用
  void requestSync() {
    if (_isolateReady) {
      _syncState();
    }
  }

  /// 同步完整状态到计算 Isolate
  void _syncState() {
    if (_workerSendPort == null || _project == null) return;

    final state = SimSyncState(
      buildings: _project!.buildings.map((pb) => SimBuildingData(
        id: pb.id,
        buildingId: pb.building.id,
        gridX: pb.gridX,
        gridY: pb.gridY,
        rotation: pb.rotation,
        activeRecipeId: pb.activeRecipeId,
        gridWidth: pb.building.gridWidth,
        gridHeight: pb.building.gridHeight,
        inputPorts: pb.inputPorts.map((p) => SimPortData(
          index: p.index,
          type: p.type,
          relativeX: p.definition.relativeX,
          relativeY: p.definition.relativeY,
          direction: p.definition.direction,
          portType: p.definition.portType,
        )).toList(),
        outputPorts: pb.outputPorts.map((p) => SimPortData(
          index: p.index,
          type: p.type,
          relativeX: p.definition.relativeX,
          relativeY: p.definition.relativeY,
          direction: p.definition.direction,
          portType: p.definition.portType,
        )).toList(),
        inputInventory: Map<String, int>.from(pb.inputInventory),
        outputInventory: Map<String, int>.from(pb.outputInventory),
        outputItemId: pb.outputItemId,
      )).toList(),
      conveyors: _project!.conveyors.map((c) => SimConveyorData(
        id: c.id,
        path: c.path,
        items: c.items.map((i) => SimConveyorItemData(itemId: i.itemId, position: i.position)).toList(),
        flowProgress: c.flowProgress,
        isBlocked: c.isBlocked,
        forcedDirection: c.forcedDirection,
        incomingDirection: c.incomingDirection,
      )).toList(),
      recipes: _dataLoader.recipes.values.map((r) => SimRecipeData(
        id: r.id,
        processTimeSeconds: r.processTimeSeconds,
        inputs: r.inputs.map((io) => SimRecipeIOData(itemId: io.itemId, amount: io.amount)).toList(),
        outputs: r.outputs.map((io) => SimRecipeIOData(itemId: io.itemId, amount: io.amount)).toList(),
      )).toList(),
      speedMultiplier: _speedMultiplier,
    );

    _sendControl('sync', state.toJson());
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    if (_isolateReady) {
      // 启动前重新同步最新状态（用户可能修改了 outputItemId、activeRecipeId 等）
      _syncState();
      _sendControl('start');
    } else {
      // Web 回退：主线程定时器
      _fallbackTimer = Timer.periodic(
        Duration(milliseconds: (1000 / _tickRate).round()),
        _onFallbackTick,
      );
    }

    notifyListeners();
  }

  void stop() {
    _isRunning = false;

    if (_isolateReady) {
      _sendControl('stop');
    } else {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
    }

    notifyListeners();
  }

  void toggle() {
    if (_isRunning) {
      stop();
    } else {
      start();
    }
  }

  void _sendControl(String type, [Map<String, dynamic>? data]) {
    _workerSendPort?.send({'type': type, 'data': data});
  }

  // ============================================================
  // Web 回退：主线程计算（与 Isolate worker 逻辑完全一致）
  // ============================================================

  void _onFallbackTick(Timer timer) {
    if (_project == null) return;
    final dt = _speedMultiplier / _tickRate;

    _fallbackUpdateConveyors(dt);
    _fallbackUpdateBuildings(dt);
    _fallbackOutputToConveyors(dt);

    notifyListeners();
  }

  // --- 传送带物品移动 ---

  void _fallbackUpdateConveyors(double dt) {
    if (_project == null) return;

    for (final belt in _project!.conveyors) {
      // 更新流动进度（视觉效果）
      belt.flowProgress += dt * 60;
      if (belt.flowProgress > 100000) belt.flowProgress = 0;

      if (belt.path.isEmpty) continue;
      final maxPosition = belt.maxPosition;

      // 按位置从高到低排序（前方物品先处理）
      belt.items.sort((a, b) => b.position.compareTo(a.position));

      // 逐个移动物品
      for (int i = 0; i < belt.items.length; i++) {
        final item = belt.items[i];
        double newPosition = item.position + dt * _itemSpeed;

        // 检查前方物品间距
        if (i > 0) {
          final aheadItem = belt.items[i - 1]; // 已排序，i-1 是前方物品
          final minPos = aheadItem.position - _itemSpacing;
          if (newPosition > minPos) {
            newPosition = minPos;
          }
        }

        // 不能超过最大位置
        if (newPosition > maxPosition) {
          newPosition = maxPosition;
        }

        belt.items[i] = item.copyWith(position: newPosition);
      }

      // 处理到达终点的物品
      _fallbackProcessArrival(belt);
    }
  }

  /// 处理传送带终点物品到达逻辑
  void _fallbackProcessArrival(ConveyorBelt belt) {
    if (_project == null) return;
    if (belt.items.isEmpty) return;

    final maxPosition = belt.maxPosition;
    final endWorldPos = belt.end;

    // 找到在终点位置的物品（从前往后处理）
    final toRemove = <int>[];
    for (int i = 0; i < belt.items.length; i++) {
      final item = belt.items[i];
      if (item.position < maxPosition) break; // 后面的物品更靠后，不可能到达终点

      // 检查终点是否连接到设备的输入端口
      final targetBuilding = _fallbackFindBuildingAtInputPort(endWorldPos);
      if (targetBuilding != null) {
        if (targetBuilding.building.id == 'depot_loader_3x1') {
          // 仓库入货口：物品被消耗
          toRemove.add(i);
        } else {
          // 普通设备输入端口：物品进入 inputInventory
          targetBuilding.inputInventory[item.itemId] =
              (targetBuilding.inputInventory[item.itemId] ?? 0) + 1;
          toRemove.add(i);
        }
      }
      // 如果终点没有连接设备，物品停留在 maxPosition（堆积），阻塞后方物品
    }

    // 从后往前移除，避免索引偏移
    for (int i = toRemove.length - 1; i >= 0; i--) {
      belt.items.removeAt(toRemove[i]);
    }
  }

  /// 查找输入端口位于指定世界坐标的设备
  PlacedBuilding? _fallbackFindBuildingAtInputPort(Offset worldPos) {
    if (_project == null) return null;
    for (final pb in _project!.buildings) {
      for (final port in pb.inputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  // --- 设备自动生产 ---

  void _fallbackUpdateBuildings(double dt) {
    if (_project == null) return;

    for (final pb in _project!.buildings) {
      // 仓库取货口：持续输出物品到传送带（在 _fallbackOutputToConveyors 中处理）
      if (pb.building.id == 'depot_unloader_3x1') continue;

      // 仓库入货口：不需要生产逻辑
      if (pb.building.id == 'depot_loader_3x1') continue;

      if (pb.activeRecipeId == null) continue;
      final recipe = _dataLoader.getRecipe(pb.activeRecipeId!);
      if (recipe == null) continue;

      // 如果正在生产中（progress > 0），继续推进进度直到完成
      if (pb.productionProgress > 0.0) {
        pb.productionProgress += dt / recipe.processTimeSeconds;

        if (pb.productionProgress >= 1.0) {
          pb.productionProgress = 0.0;
          // 产出物品到 outputInventory
          for (final output in recipe.outputs) {
            pb.outputInventory[output.itemId] =
                (pb.outputInventory[output.itemId] ?? 0) + output.amount;
          }
        }
        pb.isBlocked = false;
        continue;
      }

      // 进度为 0 时，检查 inputInventory 是否有足够的输入物品
      bool hasInputs = true;
      for (final input in recipe.inputs) {
        final available = pb.inputInventory[input.itemId] ?? 0;
        if (available < input.amount) {
          hasInputs = false;
          break;
        }
      }

      if (!hasInputs) {
        pb.isBlocked = true;
        continue;
      }

      // 消耗输入并开始生产
      for (final input in recipe.inputs) {
        pb.inputInventory[input.itemId] =
            (pb.inputInventory[input.itemId] ?? 0) - input.amount;
        if (pb.inputInventory[input.itemId]! <= 0) {
          pb.inputInventory.remove(input.itemId);
        }
      }

      pb.isBlocked = false;
      pb.productionProgress += dt / recipe.processTimeSeconds;
    }
  }

  // --- 输出库存到传送带 & 仓库取货口持续输出 ---

  void _fallbackOutputToConveyors(double dt) {
    if (_project == null) return;

    for (final pb in _project!.buildings) {
      // 仓库取货口：持续输出
      if (pb.building.id == 'depot_unloader_3x1') {
        if (pb.outputItemId == null || pb.outputItemId!.isEmpty) continue;
        _fallbackTryOutputItemToBelt(pb, pb.outputItemId!);
        continue;
      }

      // 普通设备：从 outputInventory 输出
      if (pb.outputInventory.isEmpty) continue;

      // 复制 key 列表以避免并发修改
      final itemIds = pb.outputInventory.keys.toList();
      for (final itemId in itemIds) {
        final count = pb.outputInventory[itemId] ?? 0;
        if (count <= 0) continue;

        if (_fallbackTryOutputItemToBelt(pb, itemId)) {
          pb.outputInventory[itemId] = count - 1;
          if (pb.outputInventory[itemId]! <= 0) {
            pb.outputInventory.remove(itemId);
          }
        }
      }
    }
  }

  /// 尝试将一个物品从设备的输出端口放到连接的传送带上
  /// 返回 true 表示成功放置
  bool _fallbackTryOutputItemToBelt(PlacedBuilding pb, String itemId) {
    if (_project == null) return false;

    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(
          pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);

      for (final belt in _project!.conveyors) {
        // 传送带起点连接到设备输出端口
        if ((belt.start - portWorld).distance < _portConnectionThreshold) {
          // 检查传送带 position 0 附近是否为空（无物品在 1.0 范围内）
          bool position0Empty = true;
          for (final item in belt.items) {
            if (item.position < _itemSpacing) {
              position0Empty = false;
              break;
            }
          }

          if (position0Empty) {
            belt.items.add(ConveyorItem(itemId: itemId, position: 0.0));
            return true;
          }
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    stop();
    _mainSubscription?.cancel();
    _mainReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }
}
