# Tasks

- [x] Task 1: 重构 ConveyorBelt 数据模型
  - [x] 1.1: 在 `lib/models/project.dart` 中新增 `ConveyorItem` 类，包含 `itemId`（String）和 `position`（double，单位格，0=起点）
  - [x] 1.2: 修改 `ConveyorBelt` 类：移除 `itemId`、`particles` 字段，新增 `items`（List<ConveyorItem>）字段
  - [x] 1.3: 修改 `ConveyorBelt` 的 `start`/`end`/`length` getter 适配新模型
  - [x] 1.4: 确保传送带创建、合并、截断等逻辑中 ConveyorBelt 的构造适配新字段

- [x] Task 2: 扩展 PlacedBuilding 数据模型
  - [x] 2.1: 在 `PlacedBuilding` 中新增 `inputInventory`（Map<String, int>）和 `outputInventory`（Map<String, int>）字段
  - [x] 2.2: 在 `PlacedBuilding` 中新增 `outputItemId`（String?）字段，用于仓库取货口记录选择的输出物品

- [x] Task 3: 更新仿真通信协议
  - [x] 3.1: 在 `sim_protocol.dart` 中新增 `SimConveyorItemData` 类（itemId + position）
  - [x] 3.2: 修改 `SimConveyorData`：移除 `itemId`，新增 `items`（List<SimConveyorItemData>）
  - [x] 3.3: 修改 `SimConveyorResult`：返回 items 列表而非单一 itemId
  - [x] 3.4: 修改 `SimBuildingData`：新增 `inputInventory`、`outputInventory`、`outputItemId` 字段
  - [x] 3.5: 修改 `SimBuildingResult`：新增 `inputInventory`、`outputInventory` 字段

- [x] Task 4: 重写仿真引擎核心逻辑
  - [x] 4.1: 实现传送带物品移动逻辑：每个 tick 按 dt * 0.5 推进物品 position
  - [x] 4.2: 实现物品到达传送带终点的处理：连接设备输入端口则转入 inputInventory；未连接则堆积
  - [x] 4.3: 实现物品间距控制：前方物品阻塞时后方物品等待，间距至少 1 格
  - [x] 4.4: 实现设备自动生产逻辑：检查 inputInventory 是否满足 activeRecipe，满足则消耗输入并推进 productionProgress
  - [x] 4.5: 实现生产完成逻辑：产出物品进入 outputInventory，自动上载到连接的输出传送带
  - [x] 4.6: 实现仓库取货口持续输出逻辑：根据 outputItemId 持续向输出传送带放置物品
  - [x] 4.7: 实现仓库存货口接收逻辑：接收传送带输送来的物品并销毁
  - [x] 4.8: 同步更新 `sim_worker.dart`（Isolate 模式）和 `simulation_engine.dart`（Web 回退模式）的逻辑

- [x] Task 5: 更新传送带渲染器
  - [x] 5.1: 修改 `transport_belt_renderer.dart` 中的粒子/物品渲染逻辑，根据 ConveyorItem 的 position 在传送带路径上渲染物品小图标
  - [x] 5.2: 物品图标使用对应物品的 imageAssetPath 渲染，尺寸适配传送带宽度

- [x] Task 6: 更新建筑详情弹窗
  - [x] 6.1: 修改 `_SynthesisGrid` 组件，显示设备 inputInventory/outputInventory 中的实际物品及数量
  - [x] 6.2: 在输入输出网格中间下方新增胶囊进度条（168px×12px），仅在设备生产时显示
  - [x] 6.3: 进度条上方显示当前生产所需总时间
  - [x] 6.4: 进度条按 productionProgress 填充，每完成一轮重置
  - [x] 6.5: 仓库取货口弹窗选择物品时同步更新 PlacedBuilding.outputItemId

- [x] Task 7: 更新传送带创建与状态同步
  - [x] 7.1: 修改 `TransportBeltController` 中 ConveyorBelt 构造适配新字段
  - [x] 7.2: 修改 `SimulationEngine._syncState()` 同步新字段到 Isolate
  - [x] 7.3: 修改 `SimulationEngine._applyTickResult()` 应用新字段结果

# Task Dependencies
- [Task 2] depends on [Task 1] (模型变更需同步)
- [Task 3] depends on [Task 1, Task 2] (协议依赖模型定义)
- [Task 4] depends on [Task 1, Task 2, Task 3] (引擎依赖模型和协议)
- [Task 5] depends on [Task 1] (渲染依赖新模型)
- [Task 6] depends on [Task 2, Task 4] (弹窗依赖库存数据和生产状态)
- [Task 7] depends on [Task 1, Task 2, Task 3] (同步依赖模型和协议)
