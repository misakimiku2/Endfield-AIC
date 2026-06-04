# 传送带物品输送与生产系统 Spec

## Why
当前传送带仅有流动动画和简单的 itemId 标记，无法实际输送物品；设备生产逻辑依赖传送带 itemId 匹配而非物品实际到达输入端口；仓库取货口选择物品后无实际输出行为。需要实现完整的物品输送、设备输入/输出库存、自动配方匹配生产和进度条显示。

## What Changes
- **ConveyorBelt 模型重构**：从单一 `itemId` + `flowProgress` 改为支持多个物品在传送带上以独立位置移动的队列模型
- **PlacedBuilding 模型扩展**：新增 `inputInventory`（输入库存）和 `outputInventory`（输出库存），追踪实际到达和产出的物品数量
- **仿真引擎重写**：物品以 0.5 格/秒速度沿传送带移动；物品到达设备输入端口时转入设备输入库存；输入库存满足配方时自动开始生产；生产完成后物品进入输出库存；输出库存物品自动上载到输出传送带
- **仓库取货口输出逻辑**：选择物品后持续向连接的传送带输出物品
- **仓库存货口接收逻辑**：持续接收传送带输送来的物品
- **设备弹窗 UI 更新**：输入/输出网格显示实际库存数量；输入输出网格中间下方增加胶囊进度条（168px×12px），显示单次生产进度和所需时间
- **传送带渲染更新**：在传送带上渲染实际移动的物品图标

## Impact
- Affected specs: 仿真引擎核心逻辑、传送带数据模型、设备数据模型、建筑详情弹窗
- Affected code:
  - `lib/models/project.dart` — ConveyorBelt、PlacedBuilding 模型
  - `lib/canvas/simulation_engine.dart` — 仿真引擎主逻辑
  - `lib/canvas/sim_worker.dart` — Isolate 计算工作线程
  - `lib/canvas/sim_protocol.dart` — 仿真通信协议
  - `lib/widgets/building_detail_dialog.dart` — 建筑详情弹窗
  - `lib/AIC/Logistics Units/transport_belt_renderer.dart` — 传送带渲染器
  - `lib/AIC/Depot Access/depot_access.dart` — 仓库取货口/存货口配置

## ADDED Requirements

### Requirement: 传送带物品输送
系统 SHALL 支持物品在传送带上以 0.5 格/秒的速度从起点向终点移动。每个物品占据 1 格空间。

#### Scenario: 仓库取货口输出物品到传送带
- **WHEN** 用户在仓库取货口弹窗中选择一个物品，且该取货口的输出端口已连接传送带
- **THEN** 该物品会从取货口输出端口出发，以 0.5 格/秒的速度沿传送带移动
- **AND** 取货口会源源不断地输出所选物品（前一个物品离开输出端口位置后立即输出下一个）

#### Scenario: 物品到达设备输入端口
- **WHEN** 传送带上的物品移动到传送带终点，且终点连接了设备的输入端口
- **THEN** 物品从传送带移除，该设备的输入库存中对应物品数量 +1

#### Scenario: 传送带尽头无设备时物品堆积
- **WHEN** 传送带上的物品移动到传送带终点，且终点没有连接任何设备的输入端口
- **THEN** 物品在传送带尽头堆积（不再移动），后续物品在距离前一个物品 1 格处排队等待

#### Scenario: 仓库存货口接收物品
- **WHEN** 传送带上的物品到达仓库存货口的输入端口
- **THEN** 物品被存货口接收并消失（存货口无限接收）

### Requirement: 设备自动生产
系统 SHALL 在设备输入库存满足某个配方要求时自动开始该配方的生产。

#### Scenario: 输入物品匹配配方自动生产
- **GIVEN** 设备已通过弹窗选定了一个配方（activeRecipeId）
- **WHEN** 传送带输送的物品到达设备输入端口，使输入库存中该物品数量达到配方要求
- **THEN** 设备自动消耗所需数量的输入物品，开始生产
- **AND** 生产进度按配方所需时间推进

#### Scenario: 生产完成产出物品
- **WHEN** 设备生产进度达到 100%
- **THEN** 产出物品进入设备输出库存
- **AND** 如果输出端口连接了传送带且传送带有空间，物品自动上载到传送带
- **AND** 进度重置，若输入库存仍满足配方则立即开始下一轮生产

#### Scenario: 输入不足时暂停生产
- **WHEN** 设备正在生产但输入库存不足以开始新一轮生产
- **THEN** 当前轮次正常完成，完成后不开始新轮次，等待输入补充

### Requirement: 设备弹窗生产进度条
系统 SHALL 在设备弹窗的输入输出网格中间下方显示生产进度条。

#### Scenario: 生产中显示进度条
- **WHEN** 设备正在进行生产
- **THEN** 在输入输出网格中间下方显示一个 168px×12px 的胶囊长条进度条
- **AND** 进度条上方显示当前生产所需的总时间（如"2.0s"）
- **AND** 进度条按当前生产进度填充

#### Scenario: 非生产时隐藏进度条
- **WHEN** 设备未在进行生产
- **THEN** 进度条不显示

#### Scenario: 每轮生产重置进度条
- **WHEN** 一轮生产完成
- **THEN** 进度条重置为 0 并开始下一轮的填充（若仍有输入）

### Requirement: 设备弹窗输入输出库存显示
系统 SHALL 在设备弹窗的输入/输出网格中显示实际库存数量。

#### Scenario: 输入库存显示
- **WHEN** 设备输入库存中有物品
- **THEN** 输入网格显示对应物品图标及实际数量

#### Scenario: 输出库存显示
- **WHEN** 设备输出库存中有物品
- **THEN** 输出网格显示对应物品图标及实际数量

### Requirement: 传送带物品渲染
系统 SHALL 在传送带上渲染实际移动的物品图标。

#### Scenario: 物品在传送带上可见
- **WHEN** 传送带上有物品正在移动
- **THEN** 在物品对应的传送带位置渲染物品的小图标
- **AND** 图标随物品移动而平滑移动

## MODIFIED Requirements

### Requirement: 传送带数据模型
ConveyorBelt 模型 SHALL 支持多个物品在传送带上以独立位置移动。

**变更内容**：
- 移除单一 `itemId` 和 `particles` 字段
- 新增 `items` 列表，每个元素包含 `itemId`（物品ID）和 `position`（在传送带路径上的位置，单位为格，0=起点）
- 保留 `isBlocked` 字段
- 物品位置以格为单位，从起点（0）到终点（path.length - 1）

### Requirement: PlacedBuilding 数据模型
PlacedBuilding SHALL 追踪输入和输出库存。

**变更内容**：
- 新增 `inputInventory`：`Map<String, int>` 记录输入端口接收的物品及数量
- 新增 `outputInventory`：`Map<String, int>` 记录生产产出但尚未被传送带带走的物品及数量
- 新增 `outputItemId`：`String?` 仓库取货口专用，记录选择的输出物品ID

### Requirement: 仿真引擎逻辑
仿真引擎 SHALL 实现基于物品位置的输送逻辑。

**变更内容**：
- 每个 tick 按 dt 推进所有传送带上物品的位置（0.5 格/秒）
- 物品到达传送带终点时：若连接设备输入端口则转入输入库存；若未连接则堆积
- 设备检查输入库存是否满足 activeRecipe 配方，满足则消耗输入开始生产
- 生产完成后产出进入输出库存，输出库存物品自动上载到连接的输出传送带
- 仓库取货口持续向输出传送带输出所选物品
- 物品间距至少 1 格，前方物品阻塞时后方物品等待

## REMOVED Requirements

### Requirement: 传送带单一 itemId 匹配检查
**Reason**: 物品输送改为基于位置的队列模型，不再使用单一 itemId 进行配方输入匹配
**Migration**: 传送带 itemId 字段被 items 列表替代；配方输入检查改为检查设备输入库存
