import 'dart:async';
import 'dart:ui';

import '../constants/app_constants.dart';
import '../data/data_loader.dart';
import '../models/project.dart';
import 'simulation_backend.dart';

/// 主线程仿真后端（Web 平台 / Isolate 不可用时的回退）。
///
/// 直接在主线程上推进 [ProjectState] 中的建筑与传送带，不经过序列化。
/// 物品段的精细推进（[ConveyorItemSegment]）由 `BeltSimulationLogic`
/// 在 `canvas_editor` 中处理，本类只负责流动进度与建筑生产。
///
/// 计算完成后通过 [onChanged] 回调通知 [SimulationEngine] 调用
/// `notifyListeners()`，从而触发 UI 重建。
class MainThreadSimulationBackend implements SimulationBackend {
  final void Function() _onChanged;

  ProjectState? _project;
  Timer? _tickTimer;
  double _speedMultiplier = 1.0;

  static const double _tickRate = AppConstants.simTickRate;
  static const double _cellSize = AppConstants.cellSize;
  static const double _portConnectionThreshold =
      AppConstants.portConnectionThreshold;

  MainThreadSimulationBackend(DataLoader dataLoader, this._onChanged);

  @override
  bool get isReady => true;

  @override
  Future<void> init() async {
    // 主线程无需异步初始化。
  }

  @override
  void attach(ProjectState project) {
    _project = project;
  }

  @override
  void start() {
    if (_tickTimer != null) return;
    _tickTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _tickRate).round()),
      _onTick,
    );
  }

  @override
  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  @override
  void setSpeed(double multiplier) {
    _speedMultiplier = multiplier;
  }

  @override
  void syncState(
    int revision,
    ProjectState project,
    DataLoader loader,
    double speedMultiplier,
  ) {
    // 主线程直接操作实时 project，无需同步副本。
    // attach() 已绑定引用，loader 也不会变更。
  }

  /// 测试钩子：手动驱动一帧，跳过 Timer。
  ///
  /// 供 `SimulationEngine.debugTickForTesting` 转发调用，使现有测试无需改动。
  void debugTickForTesting(double dt) {
    if (_project == null) return;
    _updateConveyors(dt);
    _onChanged();
  }

  void _onTick(Timer timer) {
    if (_project == null) return;
    final dt = _speedMultiplier / _tickRate;

    _updateConveyors(dt);

    _onChanged();
  }

  void _updateConveyors(double dt) {
    if (_project == null) return;
    for (final belt in _project!.conveyors) {
      if (belt.isBlocked) continue;
      belt.flowProgress += dt * 60;
      if (belt.flowProgress > AppConstants.flowProgressWrapThreshold) {
        belt.flowProgress = 0;
      }

      final sourceBuilding = _findSourceBuilding(belt.start);
      if (sourceBuilding != null && sourceBuilding.isBlocked) {
        belt.isBlocked = true;
      } else {
        belt.isBlocked = false;
      }
    }
  }

  PlacedBuilding? _findSourceBuilding(Offset worldPos) {
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

  @override
  void dispose() {
    stop();
  }
}
