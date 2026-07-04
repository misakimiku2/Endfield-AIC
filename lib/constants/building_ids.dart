/// 建筑 ID 字符串常量。
///
/// 散布在 `editor_page` 的 dockOrder、各 Config 类、`canvas_editor`、
/// `simulation_engine`、`sim_worker`、`building_detail_dialog` 等处。
/// 集中定义避免字面量笔误导致 ID 不匹配。
class BuildingIds {
  BuildingIds._();

  static const String refiningUnit3x3 = 'refining_unit_3x3';
  static const String depotLoader3x1 = 'depot_loader_3x1';
  static const String depotUnloader3x1 = 'depot_unloader_3x1';
  static const String beltBridge1x1 = 'belt_bridge_1x1';
  static const String splitter1x1 = 'splitter_1x1';
  static const String converger1x1 = 'converger_1x1';
  static const String itemControlPort1x1 = 'item_control_port_1x1';
}
