import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';
import '../constants/app_constants.dart';
import 'sim_protocol.dart';
import 'sim_worker.dart';

class SimulationEngine extends ChangeNotifier {
  final DataLoader _dataLoader;
  ProjectState? _project;
  bool _isRunning = false;
  double _speedMultiplier = 1.0;
  int _syncRevision = 0;

  // Isolate 模式（原生平台）
  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription? _mainSubscription;
  bool _isolateReady = false;

  // 主线程回退模式（Web 平台）
  Timer? _fallbackTimer;
  static const double _tickRate = AppConstants.simTickRate;
  static const double _cellSize = AppConstants.cellSize;
  static const double _portConnectionThreshold = AppConstants.portConnectionThreshold;

  bool get isRunning => _isRunning;

  /// 跟踪上一次 Isolate 返回的建筑数据，用于计算增量（delta）而非直接覆盖。
  /// key=建筑ID，value=上次 Isolate 同步的 inputItemCount / outputItems。
  final Map<String, _IsolateBuildingSnapshot> _prevIsolateBuildingSnapshots = {};

  bool _hasOutputSpace(ConveyorBelt belt) {
    belt.ensureItemSegmentsFromLegacy();
    if (belt.itemSegments.isNotEmpty) {
      return belt.itemSegments.first.drainCount > 0 ||
          belt.itemSegments.first.fillCount < belt.currentItemFillLimit;
    }
    if (belt.itemId.isNotEmpty) return false;
    if (!belt.hasStoppedLastItems) return true;
    return belt.lastItemDrainCount > 0;
  }

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
      if (result.revision != _syncRevision) return;
      _applyTickResult(result);
      notifyListeners();
    }
  }

  /// 将 tick 结果应用到主线程的 project 数据。
  ///
  /// 使用增量（delta）方式更新 inputItemCount 和 outputItems，
  /// 避免直接覆盖主线程上由 BeltSimulationLogic 在同一帧内新增/消费的值。
  /// 直接覆盖会导致输入端溢出（Bug: Isolate 快照覆盖传送带仿真新增的物品）。
  void _applyTickResult(SimTickResult result) {
    if (_project == null) return;

    for (final br in result.buildings) {
      final pb = _project!.buildings.where((b) => b.id == br.id).firstOrNull;
      if (pb != null) {
        // 物流设备状态由 canvas_editor 主线程管理，跳过 Isolate 覆盖
        if (pb.isBeltBridge || pb.isSplitter || pb.isConverger) continue;

        pb.isBlocked = br.isBlocked;
        pb.productionProgress = br.productionProgress;
        if (br.activeRecipeId != null) {
          pb.activeRecipeId = br.activeRecipeId;
        }

        final prev = _prevIsolateBuildingSnapshots[pb.id];
        if (prev != null) {
          // 增量更新 inputItemCount：仅应用 Isolate 消耗的增量
          final consumed = prev.inputItemCount - br.inputItemCount;
          if (consumed > 0) {
            pb.inputItemCount =
                (pb.inputItemCount - consumed).clamp(0, 999999);
            if (pb.inputItemCount <= 0) {
              pb.inputItemCount = 0;
              pb.inputItemId = null;
            } else if (br.inputItemId.isNotEmpty) {
              pb.inputItemId = br.inputItemId;
            }
          }

          // 增量更新 outputItems：仅增加 Isolate 新产出的物品
          for (final entry in br.outputItems.entries) {
            final prevCount = prev.outputItems[entry.key] ?? 0;
            final produced = entry.value - prevCount;
            if (produced > 0) {
              pb.addOutputItem(entry.key, produced);
            }
          }
        } else {
          // 首次同步：直接设置基准值
          pb.inputItemId = br.inputItemId.isEmpty ? null : br.inputItemId;
          pb.inputItemCount = br.inputItemCount;
          pb.outputItems = Map<String, int>.from(br.outputItems);
        }

        _prevIsolateBuildingSnapshots[pb.id] = _IsolateBuildingSnapshot(
          inputItemCount: br.inputItemCount,
          outputItems: Map<String, int>.from(br.outputItems),
        );
      }
    }

    for (final cr in result.conveyors) {
      final belt = _project!.conveyors.where((c) => c.id == cr.id).firstOrNull;
      if (belt != null) {
        if (belt.itemSegments.isNotEmpty) {
          belt.flowProgress = cr.flowProgress;
          belt.isBlocked = cr.isBlocked;
          continue;
        }
        // 只有当没有残留物品时才更新 lastItemId，避免覆盖残留物品的 ID
        // 当 itemId 首次从空变为非空时，立即初始化第一格物品
        // 避免等待下一个动画周期（最多 2 秒延迟）
        belt.flowProgress = cr.flowProgress;
        belt.isBlocked = cr.isBlocked;
      }
    }
  }

  String? _outputItemIdForBeltStart(ConveyorBelt belt) {
    if (_project == null || belt.path.isEmpty) return null;
    final start = belt.path.first;
    final gx = start.dx.round();
    final gy = start.dy.round();
    for (final pb in _project!.buildings) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      for (int i = 0; i < pb.outputPorts.length; i++) {
        final portCell = pb.outputPorts[i]
            .gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        if (portCell.dx.round() != gx || portCell.dy.round() != gy) continue;
        if (pb.building.id == 'depot_unloader_3x1') {
          final itemId = pb.depotOutputItemId;
          return itemId == null || itemId.isEmpty ? null : itemId;
        }
        final recipe = pb.activeRecipeId != null
            ? _dataLoader.getRecipe(pb.activeRecipeId!)
            : null;
        if (recipe == null || recipe.outputs.isEmpty) return null;
        final output = recipe.outputs.length > i
            ? recipe.outputs[i]
            : recipe.outputs.first;
        return output.itemId;
      }
    }
    return null;
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
    _syncRevision++;

    final state = SimSyncState(
      revision: _syncRevision,
      buildings: _project!.buildings
          .map((pb) => SimBuildingData(
                id: pb.id,
                buildingId: pb.building.id,
                gridX: pb.gridX,
                gridY: pb.gridY,
                rotation: pb.rotation,
                activeRecipeId: pb.activeRecipeId,
                depotOutputItemId: pb.depotOutputItemId ?? '',
                inputItemId: pb.inputItemId ?? '',
                inputItemCount: pb.inputItemCount,
                outputItems: pb.outputItems,
                gridWidth: pb.building.gridWidth,
                gridHeight: pb.building.gridHeight,
                inputPorts: pb.inputPorts
                    .map((p) => SimPortData(
                          index: p.index,
                          type: p.type,
                          relativeX: p.definition.relativeX,
                          relativeY: p.definition.relativeY,
                          direction: p.definition.direction,
                          portType: p.definition.portType,
                        ))
                    .toList(),
                outputPorts: pb.outputPorts
                    .map((p) => SimPortData(
                          index: p.index,
                          type: p.type,
                          relativeX: p.definition.relativeX,
                          relativeY: p.definition.relativeY,
                          direction: p.definition.direction,
                          portType: p.definition.portType,
                        ))
                    .toList(),
                isPaused: pb.isPaused,
              ))
          .toList(),
      conveyors: _project!.conveyors
          .map((c) => SimConveyorData(
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
                deadEndFreezeProgress: c.deadEndFreezeProgress,
                lastItemFreezeProgress: c.lastItemFreezeProgress,
              ))
          .toList(),
      recipes: _dataLoader.recipes.values
          .map((r) => SimRecipeData(
                id: r.id,
                processTimeSeconds: r.processTimeSeconds,
                inputs: r.inputs
                    .map((io) =>
                        SimRecipeIOData(itemId: io.itemId, amount: io.amount))
                    .toList(),
                outputs: r.outputs
                    .map((io) =>
                        SimRecipeIOData(itemId: io.itemId, amount: io.amount))
                    .toList(),
                allowedBuildings: r.allowedBuildings,
              ))
          .toList(),
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

  @visibleForTesting
  void debugTickForTesting(double dt) {
    if (_project == null) return;
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
        final portWorld = port.worldPosition(pb.gridX, pb.gridY, _cellSize,
            pb.building.gridWidth, pb.building.gridHeight,
            rotation: pb.rotation);
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
        continue;
      }

      // 自动匹配配方：当建筑没有激活配方但有输入物品时，自动选择匹配的配方
      if (pb.activeRecipeId == null &&
          pb.inputItemId != null &&
          pb.inputItemCount > 0) {
        _fallbackAutoSelectRecipe(pb);
      }

      if (pb.activeRecipeId == null) continue;
      // 设备暂停时跳过生产
      if (pb.isPaused) continue;
      final recipe = _dataLoader.getRecipe(pb.activeRecipeId!);
      if (recipe == null) continue;

      // 尝试将输出库存推送到传送带
      if (pb.productionProgress <= 0.0) {
        if (!_fallbackCanAcceptRecipeOutputs(pb, recipe)) {
          pb.isBlocked = false;
          pb.productionProgress = 0.0;
          continue;
        }

        if (!_fallbackCheckInputsAvailable(pb, recipe)) {
          pb.isBlocked = false;
          pb.productionProgress = 0.0;
          continue;
        }

        _fallbackConsumeInputs(pb, recipe);
      }

      pb.isBlocked = false;
      final processTime =
          recipe.processTimeSeconds <= 0 ? 1.0 : recipe.processTimeSeconds;
      pb.productionProgress += dt / processTime;

      if (pb.productionProgress >= 1.0) {
        pb.productionProgress = 0.0;
        // 产出物品放入输出库存
        for (final output in recipe.outputs) {
          pb.addOutputItem(output.itemId, output.amount);
        }
      }
    }
  }

  /// 自动匹配配方：根据建筑类型和输入物品选择第一个匹配的配方
  void _fallbackAutoSelectRecipe(PlacedBuilding pb) {
    final recipes = _dataLoader.getRecipesForBuilding(pb.building.id);
    for (final recipe in recipes) {
      if (recipe.inputs.any((input) => input.itemId == pb.inputItemId)) {
        pb.activeRecipeId = recipe.id;
        return;
      }
    }
  }

  /// 仓库取货口：将 depotOutputItemId 推送到连接的空传送带
  void _fallbackProduceDepotOutput(PlacedBuilding pb) {
    final outputItemId = pb.depotOutputItemId;
    if (outputItemId == null || outputItemId.isEmpty) return;
    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(pb.gridX, pb.gridY, _cellSize,
          pb.building.gridWidth, pb.building.gridHeight,
          rotation: pb.rotation);
      for (final belt in _project!.conveyors) {
        final dist = (belt.start - portWorld).distance;
        if (dist < _portConnectionThreshold) {
          if (_hasOutputSpace(belt)) {
            if (belt.itemSegments.isEmpty) {
              belt.pushSourceItem(outputItemId);
            }
            port.connected = true;
            port.linkedItemId = outputItemId;
          }
        }
      }
    }
  }

  bool _fallbackCheckInputsAvailable(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      if (!pb.hasInputItems(input.itemId, input.amount)) return false;
    }
    return true;
  }

  void _fallbackConsumeInputs(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      pb.consumeInputItems(input.itemId, input.amount);
    }
  }

  /// 将输出库存中的物品推送到连接的传送带
  bool _fallbackCanAcceptRecipeOutputs(PlacedBuilding pb, Recipe recipe) {
    final outputAmount =
        recipe.outputs.fold<int>(0, (sum, output) => sum + output.amount);
    return pb.totalOutputCount + outputAmount <=
        PlacedBuilding.maxOutputItemCount;
  }

  void _fallbackPushOutputToBelts(PlacedBuilding pb) {
    if (pb.outputItems.isEmpty) return;
    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(pb.gridX, pb.gridY, _cellSize,
          pb.building.gridWidth, pb.building.gridHeight,
          rotation: pb.rotation);
      for (final belt in _project!.conveyors) {
        if ((belt.start - portWorld).distance < _portConnectionThreshold) {
          if (!_hasOutputSpace(belt)) continue;
          // 按配方输出顺序确定该端口应推送的物品
          final recipe = pb.activeRecipeId != null
              ? _dataLoader.getRecipe(pb.activeRecipeId!)
              : null;
          if (recipe == null) continue;
          final outputIndex = port.index;
          final output = outputIndex < recipe.outputs.length
              ? recipe.outputs[outputIndex]
              : recipe.outputs.first;
          if (!pb.hasOutputItem(output.itemId)) continue;
          if (belt.pushSourceItem(output.itemId)) {
            pb.consumeOutputItem(output.itemId, 1);
          }
          port.connected = true;
          port.linkedItemId = output.itemId;
          break;
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

/// Isolate 同步快照：记录上一次 Isolate 返回的建筑状态，用于增量（delta）计算。
///
/// 避免 `_applyTickResult` 直接覆盖主线程上的 inputItemCount 和 outputItems，
/// 导致传送带仿真在同一帧内新增/消费的物品被丢弃。
class _IsolateBuildingSnapshot {
  final int inputItemCount;
  final Map<String, int> outputItems;
  const _IsolateBuildingSnapshot({
    required this.inputItemCount,
    required this.outputItems,
  });
}
