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
/// 注意：原生平台在 Isolate 握手完成前，仍由
/// [MainThreadSimulationBackend] 驱动首个 tick 窗口
/// （`editor_page` 在 `init()` 完成前调用 `start()`），
/// 与旧实现保持一致的行为。
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
      _isolateBackend =
          IsolateSimulationBackend(_dataLoader, _onBackendChanged);
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

  /// 初始化：原生平台启动 Isolate，Web 平台无需异步初始化。
  Future<void> init() async {
    if (_isolateBackend != null) {
      await _isolateBackend!.init();
    }
  }

  void attach(ProjectState project) {
    _mainBackend.attach(project);
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

    // 与旧实现一致：主线程回退始终启动（Web 平台唯一路径；
    // 原生平台 Isolate 就绪前的过渡窗口也由它兜底）。
    _mainBackend.start();

    if (_isolateBackend != null && _isolateBackend!.isReady) {
      _isolateBackend!.start();
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
