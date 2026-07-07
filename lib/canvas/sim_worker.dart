import 'dart:async';
import 'dart:isolate';

import '../utils/json_parse.dart';
import '../constants/app_constants.dart';
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
  double _speedMultiplier = 1.0;
  int _revision = 0;
  bool _isRunning = false;

  static const double _tickRate = AppConstants.simTickRate;

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
          _speedMultiplier =
              (message['data'] as Map).getDouble('speedMultiplier');
          break;
      }
    }
  }

  void _onSync(Map<String, dynamic> data) {
    final state = SimSyncState.fromJson(data);
    _buildings = state.buildings;
    _conveyors = state.conveyors;
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

    // 发送轻量结果回主 Isolate（不再包含生产数据）
    final result = SimTickResult(
      revision: _revision,
      buildings: _buildings
          .map((b) => SimBuildingResult(
                id: b.id,
                isBlocked: false,
                productionProgress: 0.0,
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

  void _updateConveyors(double dt) {
    for (int i = 0; i < _conveyors.length; i++) {
      final belt = _conveyors[i];
      if (belt.isBlocked) continue;

      // 更新流动进度
      double newFlow = belt.flowProgress + dt * 60;
      if (newFlow > AppConstants.flowProgressWrapThreshold) newFlow = 0;

      _conveyors[i] = SimConveyorData(
        id: belt.id,
        path: belt.path,
        itemId: belt.itemId,
        flowProgress: newFlow,
        itemFillCount: belt.itemFillCount,
        itemDrainCount: belt.itemDrainCount,
        isBlocked: false,
        lastItemFillCount: belt.lastItemFillCount,
        lastItemDrainCount: belt.lastItemDrainCount,
        deadEndFreezeProgress: belt.deadEndFreezeProgress,
        lastItemFreezeProgress: belt.lastItemFreezeProgress,
      );
    }
  }
}
