import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../constants/app_constants.dart';
import 'isolate_simulation_backend.dart';
import 'main_thread_simulation_backend.dart';
import 'simulation_backend.dart';

/// 仿真引擎：协调状态持有与 [ChangeNotifier] 通知。
///
/// 计算本身委托给 [SimulationBackend]：
/// - 原生平台：[IsolateSimulationBackend]（计算卸载到独立 Isolate）。
/// - Web 平台：[MainThreadSimulationBackend]（主线程回退）。
///
/// 注意：任一时刻**只有一套后端**驱动建筑生产，避免双重消耗
/// （inputItemCount 被减两次 / outputItems 累积翻倍）。
/// 原生平台在 Isolate 握手完成前由 [_mainBackend] 兜底过渡窗口，
/// Isolate 就绪后（[_onIsolateReady]）立即停止 [_mainBackend]、
/// 由 Isolate 接管。Web 平台始终使用 [_mainBackend]。
class SimulationEngine extends ChangeNotifier {
  final DataLoader _dataLoader;
  bool _isRunning = false;
  double _speedMultiplier = 1.0;
  int _syncRevision = 0;

  /// 主线程回退后端：Web 平台专用，原生平台仅用于 Isolate 就绪前的过渡窗口。
  late final MainThreadSimulationBackend _mainBackend;

  /// Isolate 后端：仅原生平台持有；Web 平台为 null。
  IsolateSimulationBackend? _isolateBackend;

  SimulationEngine(this._dataLoader) {
    _mainBackend = MainThreadSimulationBackend(_dataLoader, _onBackendChanged);
    if (!kIsWeb) {
      _isolateBackend = IsolateSimulationBackend(
        _dataLoader,
        _onBackendChanged,
        onReady: _onIsolateReady,
      );
    }
  }

  bool get isRunning => _isRunning;

  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double v) {
    _speedMultiplier = v.clamp(
      AppConstants.minSpeedMultiplier,
      AppConstants.maxSpeedMultiplier,
    );
    _mainBackend.setSpeed(_speedMultiplier);
    _isolateBackend?.setSpeed(_speedMultiplier);
    notifyListeners();
  }

  /// 后端计算完成后的统一回调，触发 UI 重建。
  void _onBackendChanged() => notifyListeners();

  /// Isolate 握手完成回调：原生平台 Isolate 就绪后接管生产。
  ///
  /// 此前由 [_mainBackend] 在过渡窗口兜底；Isolate 就绪后必须停止主线程回退，
  /// 否则两套后端会同时消耗 inputItemCount / 累积 outputItems，
  /// 导致输入端"50→48→50"跳变与物品回退、输出端产出倍率失真。
  ///
  /// Web 平台 [_isolateBackend] 为 null，本方法不会被调用。
  /// Isolate spawn 失败时 [IsolateSimulationBackend.isReady] 永不为 true，
  /// 本方法同样不会被调用，[_mainBackend] 持续兜底。
  void _onIsolateReady() {
    final isolate = _isolateBackend;
    if (isolate == null || !isolate.isReady) return;

    // 已在运行：停止主线程回退，由 Isolate 接管。
    if (_isRunning) {
      _mainBackend.stop();
      isolate.start();
      notifyListeners();
    }
    // 未运行（start() 尚未调用）：无需操作。后续 start() 会依据 isReady
    // 直接启动 Isolate 并跳过主线程回退（见 start()）。
  }

  /// 初始化：原生平台启动 Isolate，Web 平台无需异步初始化。
  Future<void> init() async {
    if (_isolateBackend != null) {
      await _isolateBackend!.init();
    }
  }

  void attach(ProjectState project) {
    _mainBackend.attach(project);
    // 始终在 Isolate 后端上保存 project 引用：握手到达时 _onMessageFromWorker
    // 会立即 _sendCurrentState，若此时 _project 为 null 将丢失首次同步，
    // 导致 Isolate 在空状态下 tick（已就绪即停 Main 后会中断生产）。
    _isolateBackend?.attach(project);
    if (_isolateBackend != null && _isolateBackend!.isReady) {
      _syncRevision++;
      _isolateBackend!.syncState(
        _syncRevision,
        project,
        _dataLoader,
        _speedMultiplier,
      );
    }
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // 原生平台且 Isolate 已就绪：直接由 Isolate 接管，跳过主线程回退，
    // 避免两套后端同时驱动生产造成双重消耗。
    // 其余情况（Web 平台 / Isolate 未就绪 / Isolate 不可用）由主线程回退兜底；
    // Isolate 后续就绪时会通过 [_onIsolateReady] 切换到 Isolate 驱动。
    if (_isolateBackend != null && _isolateBackend!.isReady) {
      _isolateBackend!.start();
    } else {
      _mainBackend.start();
    }

    notifyListeners();
  }

  void stop() {
    _isRunning = false;

    _mainBackend.stop();
    _isolateBackend?.stop();

    notifyListeners();
  }

  void toggle() {
    if (_isRunning) {
      stop();
    } else {
      start();
    }
  }

  /// 测试钩子：手动驱动一帧主线程回退计算。
  @visibleForTesting
  void debugTickForTesting(double dt) {
    _mainBackend.debugTickForTesting(dt);
  }

  @override
  void dispose() {
    _mainBackend.dispose();
    _isolateBackend?.dispose();
    super.dispose();
  }
}
