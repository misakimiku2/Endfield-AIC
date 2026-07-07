import 'dart:async';
import 'dart:isolate';

import '../data/data_loader.dart';
import '../models/project.dart';
import '../utils/error_handler.dart';
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

  /// Isolate 握手完成（worker 首个 SendPort 到达）时触发的回调。
  /// [SimulationEngine] 据此停止主线程回退后端，避免与 Isolate 同时驱动
  /// 建筑生产导致 inputItemCount/outputItems 双重消耗。
  final void Function()? _onReady;

  IsolateSimulationBackend(this._dataLoader, this._onChanged, {void Function()? onReady})
      : _onReady = onReady;

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
    } catch (e, stackTrace) {
      AppError(
        message: '[IsolateSimulationBackend] Isolate 初始化失败: $e',
        severity: ErrorSeverity.error,
        code: 'ISOLATE_SPAWN_FAILED',
        stackTrace: stackTrace,
      ).report();
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
      // 通知引擎：Isolate 已接管生产，可停止主线程回退，避免双重消耗。
      _onReady?.call();
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
                lockedInputBeltId: pb.lockedInputBeltId,
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
      speedMultiplier: speedMultiplier,
    );

    _sendControl('sync', state.toJson());
  }

  void _sendControl(String type, [Map<String, dynamic>? data]) {
    _workerSendPort?.send({'type': type, 'data': data});
  }

  /// 将 tick 结果应用到主线程的 project 数据。
  ///
  /// 仅同步传送带 flowProgress/isBlocked，不再处理建筑生产状态。
  void _applyTickResult(SimTickResult result) {
    if (_project == null) return;

    for (final br in result.buildings) {
      final pb = _project!.buildings.where((b) => b.id == br.id).firstOrNull;
      if (pb != null) {
        // 物流设备状态由 canvas_editor 主线程管理，跳过 Isolate 覆盖
        if (pb.isBeltBridge || pb.isSplitter || pb.isConverger) continue;
        // 生产建筑仅同步 isBlocked（始终 false，不再有生产阻塞）
        pb.isBlocked = br.isBlocked;
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
