/// 全局统一常量。
///
/// 这些 `const` 值在编译期内联，可安全跨 Isolate 边界共享
/// （`sim_worker.dart` 与 `simulation_engine.dart` 引用同一来源，
/// 避免主线程回退路径与 Isolate 之间因各自定义而漂移）。
class AppConstants {
  AppConstants._();

  /// 网格单元的像素尺寸。
  static const double cellSize = 48.0;

  /// 传送带端点与建筑端口判定为"连接"的最大像素距离。
  static const double portConnectionThreshold = 30.0;

  /// 仿真 tick 频率（每秒步数）。
  static const double simTickRate = 20.0;
}

/// 传送带物品段的冻结状态机哨兵值。
///
/// `ConveyorItemSegment.freezeProgress`（`double?`）用一个数值同时编码
/// "冻结状态"与"冻结位置"，状态机如下：
///
/// - [waiting](-1.0)：等待状态。死胡同段已到达极限，等待渲染器在
///   arrowProgress >= 0.5 时推进到 settled。
/// - [newlyFrozen](-0.75)：刚进入冻结的过渡态，由 freezeDeadEndSegments 设置。
/// - [midFrozen](-0.5)：中间冻结态。
/// - [settled](0.5)：已稳定的冻结位置（格子中央）。
/// - [rendererWaiting](-2.0)：渲染器侧的等待标记（见 transport_belt_renderer）。
/// - [clearing](-3.0)：解除冻结的目标态；非 null 且非此值即视为"冻结中"。
///
/// 注意：[isFreezing] 判定（null 或 clearing 视为未冻结）依赖这些具体数值，
/// 修改时务必同步 `pushSourceItem` / `canAcceptNewItemFromStart` / 渲染器逻辑。
class FreezeSentinels {
  FreezeSentinels._();

  /// 等待状态：死胡同段到达极限，等待渲染器推进。
  static const double waiting = -1.0;

  /// 刚进入冻结的过渡态。
  static const double newlyFrozen = -0.75;

  /// 中间冻结态。
  static const double midFrozen = -0.5;

  /// 已稳定的冻结位置（格子中央）。
  static const double settled = 0.5;

  /// 渲染器侧等待标记。
  static const double rendererWaiting = -2.0;

  /// 解除冻结的目标态。
  static const double clearing = -3.0;

  /// 判断 freezeProgress 是否表示"正在冻结"。
  /// null 或 clearing(-3.0) 视为未冻结。
  static bool isFreezing(double? fp) => fp != null && fp != clearing;
}
