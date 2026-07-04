import '../data/data_loader.dart';
import '../models/project.dart';

/// 仿真后端抽象：封装"计算发生在哪里"。
///
/// `SimulationEngine` 仅负责协调（状态持有、[ChangeNotifier] 通知、
/// 速度倍率），具体的计算路径由本接口的实现承担：
///
/// - [MainThreadSimulationBackend]：Web 平台或 Isolate 不可用时回退，
///   直接在主线程上推进 `ProjectState`。
/// - [IsolateSimulationBackend]：原生平台用独立 Isolate 计算，
///   通过 `SendPort`/`ReceivePort` 同步状态并回传增量结果。
///
/// 两种实现的差异在于"数据是远程副本还是实时引用"，但对
/// `SimulationEngine` 而一视同仁。
abstract class SimulationBackend {
  /// 后端是否已就绪接收 [syncState]/[start]。
  ///
  /// Isolate 路径需等待握手完成；主线程路径恒为 `true`。
  bool get isReady;

  /// 初始化后端资源（Isolate 路径会 spawn 计算 Isolate）。
  Future<void> init();

  /// 绑定当前项目状态。
  void attach(ProjectState project);

  /// 启动 tick 循环。
  void start();

  /// 停止 tick 循环。
  void stop();

  /// 设置仿真速度倍率。
  void setSpeed(double multiplier);

  /// 全量同步建筑/传送带/配方状态到后端。
  ///
  /// [revision] 用于 Isolate 路径拒绝过期结果；主线程路径可忽略。
  /// [speedMultiplier] 为当前仿真速度倍率，Isolate 路径会一并下发。
  void syncState(
    int revision,
    ProjectState project,
    DataLoader loader,
    double speedMultiplier,
  );

  /// 释放后端资源。
  void dispose();
}
