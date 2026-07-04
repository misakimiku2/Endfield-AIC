import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;

import '../constants/app_constants.dart';
import '../data/data_loader.dart';
import '../models/project.dart';
import 'sim_protocol.dart';
import 'sim_worker.dart';
import 'simulation_backend.dart';

/// 基于 [Isolate] 的仿真后端（原生平台）。
///
/// 将计算卸载到独立 Isolate，主线程仅负责序列化状态下发与
/// 增量（delta）结果合并。仓库取货、传送带物品段推进等
/// 与渲染强耦合的逻辑仍在主线程的 `BeltSimulationLogic` 中处理，
/// 本后端只驱动建筑生产与流动进度。
///
/// 通过 [_onChanged] 回调通知 [SimulationEngine] 调用 `notifyListeners()`。
class IsolateSimulationBackend implements SimulationBackend {
  final DataLoader _dataLoader;
  final void Function() _onChanged;

  ProjectState? _project;

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  StreamSubscription? _mainSubscription;
  bool _isolateReady = false;

  /// 当前同步版本号，由 [SimulationEngine] 传入 [syncState]，
  /// 用于拒绝过期 Isolate 结果（避免覆盖较新状态）。
  int _syncRevision = 0;

  /// 当前仿真速度倍率，由 [setSpeed] 维护，握手完成后的首次同步需要它。
  double _speedMultiplier = 1.0;

  /// 跟踪上一次 Isolate 返回的建筑数据，用于计算增量而非直接覆盖。
  final Map<String, _IsolateBuildingSnapshot> _prevSnapshots = {};

  IsolateSimulationBackend(this._dataLoader, this._onChanged);

  @override
  bool get isReady => _isolateReady;

  @override
  Future<void> init() async {
    try {
      _mainReceivePort = ReceivePort();
      _mainSubscription = _mainReceivePort!.listen(_onMessageFromWorker);

      _isolate = await Isolate.spawn(
        simWorkerEntry,
        _mainReceivePort!.sendPort,
      );
    } catch (e) {
      debugPrint('[IsolateSimulationBackend] Isolate 初始化失败: $e');
      _mainSubscription?.cancel();
      _mainReceivePort?.close();
      _mainReceivePort = null;
      _isolate = null;
      // 调用方应据 [isReady] 回退到 MainThreadSimulationBackend。
    }
  }

  @override
  void attach(ProjectState project) {
    _project = project;
    if (_isolateReady) {
      _sendCurrentState(_dataLoader, _speedMultiplier);
    }
  }

  @override
  void start() {
    if (_isolateReady) {
      _sendControl('start');
    }
    // isReady==false 时由 SimulationEngine 决定是否回退，本方法不做兜底。
  }

  @override
  void stop() {
    if (_isolateReady) {
      _sendControl('stop');
    }
  }

  @override
  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier;
    if (_isolateReady) {
      _sendControl('setSpeed', {'speedMultiplier': multiplier});
    }
  }

  @override
  void syncState(
    int revision,
    ProjectState project,
    DataLoader loader,
    double speedMultiplier,
  ) {
    _project = project;
    _syncRevision = revision;
    if (_workerSendPort == null || _project == null) return;
    _sendCurrentState(loader, speedMultiplier);
  }

  void _onMessageFromWorker(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      _isolateReady = true;
      // Isolate 就绪后同步当前状态
      _sendCurrentState(_dataLoader, _speedMultiplier);
      return;
    }

    if (message is Map<String, dynamic>) {
      final result = SimTickResult.fromJson(message);
      if (result.revision != _syncRevision) return;
      _applyTickResult(result);
      _onChanged();
    }
  }

  void _sendCurrentState(DataLoader loader, double speedMultiplier) {
    if (_workerSendPort == null || _project == null) return;

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
      recipes: loader.recipes.values
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
      speedMultiplier: speedMultiplier,
    );

    _sendControl('sync', state.toJson());
  }

  void _sendControl(String type, [Map<String, dynamic>? data]) {
    _workerSendPort?.send({'type': type, 'data': data});
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

        final prev = _prevSnapshots[pb.id];
        if (prev != null) {
          // 增量更新 inputItemCount：仅应用 Isolate 消耗的增量
          final consumed = prev.inputItemCount - br.inputItemCount;
          if (consumed > 0) {
            pb.inputItemCount = (pb.inputItemCount - consumed)
                .clamp(0, AppConstants.inputItemCountClampCeiling);
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

        _prevSnapshots[pb.id] = _IsolateBuildingSnapshot(
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

  @override
  void dispose() {
    _mainSubscription?.cancel();
    _mainReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

/// Isolate 同步快照：记录上一次 Isolate 返回的建筑状态，用于增量（delta）计算。
///
/// 避免 [_applyTickResult] 直接覆盖主线程上的 inputItemCount 和 outputItems，
/// 导致传送带仿真在同一帧内新增/消费的物品被丢弃。
class _IsolateBuildingSnapshot {
  final int inputItemCount;
  final Map<String, int> outputItems;
  const _IsolateBuildingSnapshot({
    required this.inputItemCount,
    required this.outputItems,
  });
}
