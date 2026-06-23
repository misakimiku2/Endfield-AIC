# 汇流器（Converger）全面重构计划

## 概述
汇流器是与分流器功能完全相反的物流工具：3条输入传送带汇流至1条输出传送带。输入端为左、上、右三个方向，输出端为下方。处理速度0.5单位/秒，一次处理一个物品，按传送带创建顺序排队等待。

## 修改步骤

### 1. 修正端口定义
- converger.dart: inputPorts=left/up/right, outputPorts=down
- buildings_db.json: 同步修正

### 2. PlacedBuilding模型扩展
- isConverger, convergerCycleIndex, convergerBuffer机制

### 3. 仿真逻辑实现
- canvas_editor.dart: 6个新方法+4处修改
- simulation_engine.dart: Isolate跳过汇流器

### 4. 传送带创建约束
- transport_belt.dart: 汇流器输出端口方向限制(仅down)

### 5. 汇流器弹窗面板
- 新建building_converger_panel.dart

### 6. BuildingDetailDialog集成
- _isConverger判断、面板路由、SVG处理

### 7. 汇流器输入方向约束
- 不能在上方(up)创建传送带
