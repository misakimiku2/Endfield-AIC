import 'package:flutter/material.dart';
import '../canvas/simulation_engine.dart';
import '../models/project.dart';

/// app 级项目状态提供者。
///
/// 包裹现有可变的 [ProjectState]（按引用共享、原地修改、无 copyWith），
/// 把原本散落在多处的 `simulationEngine.attach(project)` + `setState`
/// 收敛为单一入口 [notifyChanged]。
///
/// [ProjectState] 实例在 app 生命周期内保持稳定：导入是原地
/// `buildings.clear()..addAll(...)`，不替换实例。
class ProjectNotifier extends ChangeNotifier {
  ProjectNotifier(this._engine) : _project = ProjectState() {
    // 构造时把同一引用交给仿真引擎（Isolate / 主线程回退都会持有它）
    _engine.attach(_project);
  }

  final SimulationEngine _engine;
  final ProjectState _project;

  /// 结构性变更版本号：每次 [notifyChanged] 自增。
  /// 用于端口连接缓存等派生数据检测失效（见 TD-006）。
  int _version = 0;
  int get version => _version;

  /// 当前项目数据（各方按同一引用共享、原地修改）。
  ProjectState get project => _project;

  /// 任何结构性变更后调用：重新同步仿真引擎 + 通知所有监听者。
  ///
  /// 典型调用方：设备放置/删除/旋转、传送带创建/移除、库存/配方变更、
  /// 仓库取货口输出物品设置、项目导入。
  void notifyChanged() {
    _version++;
    _engine.attach(_project);
    notifyListeners();
  }
}
