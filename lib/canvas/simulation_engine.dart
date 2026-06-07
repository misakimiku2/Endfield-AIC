import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/recipe.dart';
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
      }
    }

    for (final cr in result.conveyors) {
      final belt = _project!.conveyors.where((c) => c.id == cr.id).firstOrNull;
      if (belt != null) {
        // 只有当没有残留物品时才更新 lastItemId，避免覆盖残留物品的 ID
        if (cr.itemId.isNotEmpty && belt.lastItemFillCount <= 0) {
          belt.lastItemId = cr.itemId;
        }
        // 当 itemId 首次从空变为非空时，立即初始化第一格物品
        // 避免等待下一个动画周期（最多 2 秒延迟）
        if (cr.itemId.isNotEmpty && belt.itemId.isEmpty) {
          belt.itemFillCount = 1;
          belt.itemDrainCount = 0;
          belt.lastItemFillCount = 0;
          belt.lastItemDrainCount = 0;
        }
        belt.itemId = cr.itemId;
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
        depotOutputItemId: pb.depotOutputItemId ?? '',
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
      )).toList(),
      conveyors: _project!.conveyors.map((c) => SimConveyorData(
        id: c.id,
        path: c.path,
        itemId: c.itemId,
        flowProgress: c.flowProgress,
        itemFillCount: c.itemFillCount,
        itemDrainCount: c.itemDrainCount,
        isBlocked: c.isBlocked,
        forcedDirection: c.forcedDirection,
        incomingDirection: c.incomingDirection,
        lastItemFillCount: c.lastItemFillCount,
        lastItemDrainCount: c.lastItemDrainCount,
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
  // Web 回退：主线程计算（与旧版 SimulationEngine 逻辑一致）
  // ============================================================

  void _onFallbackTick(Timer timer) {
    if (_project == null) return;
    final dt = _speedMultiplier / _tickRate;

    _fallbackUpdateConveyors(dt);
    _fallbackUpdateBuildings(dt);

    notifyListeners();
  }

  // 用于限制日志输出频率
  int _fallbackLogCounter = 0;

  void _fallbackUpdateConveyors(double dt) {
    if (_project == null) return;
    for (final belt in _project!.conveyors) {
      if (belt.isBlocked) continue;
      belt.flowProgress += dt * 60;
      if (belt.flowProgress > 100000) belt.flowProgress = 0;

      final sourceBuilding = _fallbackFindSourceBuilding(belt.start);
      if (sourceBuilding != null && sourceBuilding.isBlocked) {
        belt.isBlocked = true;
      } else {
        belt.isBlocked = false;
      }
    }
  }

  PlacedBuilding? _fallbackFindSourceBuilding(Offset worldPos) {
    if (_project == null) return null;
    for (final pb in _project!.buildings) {
      for (final port in pb.outputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  void _fallbackUpdateBuildings(double dt) {
    if (_project == null) return;
    for (final pb in _project!.buildings) {
      // 仓库取货口：不需要配方，直接将 depotOutputItemId 推送到连接的传送带
      if (pb.building.id == 'depot_unloader_3x1') {
        _fallbackProduceDepotOutput(pb);
        continue;
      }

      if (pb.activeRecipeId == null) continue;
      final recipe = _dataLoader.getRecipe(pb.activeRecipeId!);
      if (recipe == null) continue;

      final hasInputs = _fallbackCheckInputsAvailable(pb, recipe);
      final hasOutputSpace = _fallbackCheckOutputSpace(pb);

      if (!hasInputs || !hasOutputSpace) {
        pb.isBlocked = true;
        pb.productionProgress = pb.productionProgress * 0.9;
        continue;
      }

      pb.isBlocked = false;
      pb.productionProgress += dt / recipe.processTimeSeconds;

      if (pb.productionProgress >= 1.0) {
        pb.productionProgress = 0.0;
        _fallbackConsumeInputs(pb, recipe);
        _fallbackProduceOutputs(pb, recipe);
      }
    }
  }

  /// 仓库取货口：将 depotOutputItemId 推送到连接的空传送带
  void _fallbackProduceDepotOutput(PlacedBuilding pb) {
    final outputItemId = pb.depotOutputItemId;
    if (outputItemId == null || outputItemId.isEmpty) return;
    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(
          pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
      for (final belt in _project!.conveyors) {
        final dist = (belt.start - portWorld).distance;
        if (dist < _portConnectionThreshold) {
          if (belt.itemId.isEmpty) {
            belt.itemId = outputItemId;
            // 立即初始化第一格物品，避免等待下一个动画周期（最多 2 秒延迟）
            belt.itemFillCount = 1;
            belt.itemDrainCount = 0;
            belt.lastItemFillCount = 0;
            belt.lastItemDrainCount = 0;
            port.connected = true;
            port.linkedItemId = outputItemId;
            print('[SimFallback] Set belt ${belt.id} itemId=$outputItemId, fillCount=1, dist=$dist');
          }
        }
      }
    }
  }

  bool _fallbackCheckInputsAvailable(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      bool found = false;
      for (final belt in _project!.conveyors) {
        for (final port in pb.inputPorts) {
          final portWorld = port.worldPosition(
              pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
          if ((belt.end - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId == input.itemId) {
              found = true;
              break;
            }
          }
        }
        if (found) break;
      }
      if (!found) return false;
    }
    return true;
  }

  bool _fallbackCheckOutputSpace(PlacedBuilding pb) {
    if (pb.isBlocked) return false;
    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(
          pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
      for (final belt in _project!.conveyors) {
        if ((belt.start - portWorld).distance < _portConnectionThreshold) {
          if (belt.itemId.isEmpty) return true;
        }
      }
    }
    return false;
  }

  void _fallbackConsumeInputs(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      for (final port in pb.inputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
        for (final belt in _project!.conveyors) {
          if ((belt.end - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId == input.itemId) {
              belt.itemId = '';
              break;
            }
          }
        }
      }
    }
  }

  void _fallbackProduceOutputs(PlacedBuilding pb, Recipe recipe) {
    for (final output in recipe.outputs) {
      for (final port in pb.outputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight, rotation: pb.rotation);
        for (final belt in _project!.conveyors) {
          if ((belt.start - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId.isEmpty) {
              belt.itemId = output.itemId;
              port.connected = true;
              port.linkedItemId = output.itemId;
              break;
            }
          }
        }
      }
    }
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
