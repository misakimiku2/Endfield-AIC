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

  /// 建筑输入库存格上限。
  ///
  /// `PlacedBuilding.maxInputItemCount` 与 Isolate 端（无法 import 模型层）
  /// 共享同一来源，避免单边修改导致主线程/Isolate 漂移。
  static const int maxInputItemCount = 50;

  /// 建筑输出库存格上限。
  ///
  /// `PlacedBuilding.maxOutputItemCount` 与 Isolate 端共享同一来源。
  static const int maxOutputItemCount = 50;

  /// 仿真速度倍率下限（speedMultiplier 的 clamp 下界）。
  static const double minSpeedMultiplier = 0.25;

  /// 仿真速度倍率上限（speedMultiplier 的 clamp 上界）。
  static const double maxSpeedMultiplier = 10.0;

  /// inputItemCount 增量更新时的 clamp 上界（防溢出）。
  static const int inputItemCountClampCeiling = 999999;

  /// 传送带 flowProgress 回绕阈值（超过则归零，避免浮点数累积误差）。
  static const double flowProgressWrapThreshold = 100000;
}

/// 画布交互相关的 UI 常量。
class UiConstants {
  UiConstants._();

  /// 画布最小缩放比例。
  static const double minScale = 0.25;

  /// 画布最大缩放比例。
  static const double maxScale = 5.0;
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
