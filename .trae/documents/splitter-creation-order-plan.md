# 分流器创建顺序分发 + 下方方向限制 实施计划

## 摘要

1. **分发顺序**：将分流器从固定 `左→上→右` 循环改为按**输出传送带创建顺序**循环
2. **方向限制**：从分流器创建传送带时，禁止往下方（输入端）拖拽，预览应显示红色

***

## 当前状态分析

### Issue 1: 分发顺序

目前 `canvas_editor.dart` 中 4 处各定义了独立的 `const cycleOrder = ['left', 'up', 'right']`：

| 行号    | 方法                                    | 用途        |
| ----- | ------------------------------------- | --------- |
| \~607 | `_peekNextAvailableSplitterDirection` | 核心循环迭代    |
| \~638 | `_findNextAvailableSplitterDirection` | 选中方向→索引映射 |
| \~665 | `_drainSplitterBuffer`                | 缓冲排出回退    |
| \~797 | `_transferBeltOutputToBuilding`       | 推送失败回滚    |

`_getConnectedSplitterOutputDirections()` 已按 `_project.conveyors` 的列表顺序（即创建顺序）返回已连接方向，但结果被固定 cycleOrder 覆盖。

### Issue 2: 下方方向限制

根因在 `transport_belt.dart` 的 `_handleFirstAnchor`（第 180 行）：

```dart
_startingPortDirection = null;  // 不限制方向
```

`_startingPortDirection` 是单值 `String?`，无法表达「允许多个方向但禁止特定方向」。当设为 `null` 时，`_findPathBFS` 允许全部 4 个方向 (`[0,1,2,3]` = up/right/down/left)。

***

## 拟议修改

### 1. 分发顺序改为创建顺序

**涉及文件**: `lib/canvas/canvas_editor.dart`

**核心思路**: 用 `_getConnectedSplitterOutputDirections()` 的返回值（已是创建顺序）替代硬编码的 `['left','up','right']`。

**修改点**:

#### a) `_peekNextAvailableSplitterDirection` (\~行 602)

* 将 `const cycleOrder = ['left', 'up', 'right']` 替换为 `final cycleOrder = connectedDirs`

* `splitterCycleIndex` 对 `cycleOrder.length` 取模（不再是固定 3）

* 移除 `connectedDirs.contains(direction)` 检查（cycleOrder 本身就是 connectedDirs）

#### b) `_findNextAvailableSplitterDirection` (\~行 632)

* 同样替换为 `cycleOrder = connectedDirs`

* 需要传入 `connectedDirs` 或在此方法内重新获取

#### c) `_drainSplitterBuffer` (\~行 665)

* 同样替换 cycleOrder

#### d) `_transferBeltOutputToBuilding` 回滚逻辑 (\~行 797)

* 回滚时使用 `connectedDirs.indexOf(direction)` 而非固定数组

**边界情况**：

* 如果中途删除某条输出带：`connectedDirs` 会移除该方向，`cycleIndex` 可能超出新 list 范围 → 需 `cycleIndex = cycleIndex.clamp(0, connectedDirs.length - 1) % connectedDirs.length`

* 如果某方向没有传送带连接：不会被包含在 `connectedDirs` 中，自然跳过

### 2. 禁止从分流器往下方创建传送带

**涉及文件**: `lib/AIC/Logistics Units/transport_belt.dart`

**核心思路**: 新增 `_startingPortAllowedDirections`（`Set<String>?`）字段，替代 `_startingPortDirection = null` 的「全向开放」行为。BFS 路径搜索时只允许集合内的方向。

#### a) 新增字段 (\~行 31 附近)

```dart
/// 首段路径允许的物理方向集合（如分流器允许 {up, left, right}）。
/// null 表示无限制，空集合也会阻止所有方向。
Set<String>? _startingPortAllowedDirections;
```

在 `reset()` 中清理此字段。

#### b) `_handleFirstAnchor` (\~行 169-184)

* 对于有输出端口的建筑，计算所有输出端口旋转后的世界方向

* 将允许的方向集合存入 `_startingPortAllowedDirections`

* 保持 `_startingPortDirection = null`（单方向锁不再需要）

同时移除该段注释中关于「限制为单一端口方向会导致无法创建某些方向」的说明——现在用集合解决。

#### c) `_findPathBFS` (\~行 1905-1926)

* 当前逻辑：`if (firstStepDirection != null)` → 单方向限制

* 新逻辑：优先检查 `_startingPortAllowedDirections`

  * 如果非 null：用集合中的方向限制第一步

  * 否则沿用原有单方向逻辑

* 方向名称到 BFS 方向索引的转换用已有的 `dirNameToIndex`

#### d) 修改 `_findPath` (\~行 1728-1730)

* 将 `_startingPortAllowedDirections` 传递到 `_findPathBFS`

* 不再仅依赖 `_startingPortDirection`

***

## 不修改的部分

* `_getConnectedSplitterOutputDirections()` — 已按创建顺序返回，无需改动

* `splitterCycleIndex` 字段定义 — 保持为 int，含义不变（索引进 connectedDirs 列表）

* `splitter.dart` — 端口定义不变

* `transport_belt_renderer.dart` — 预览渲染不变（pathInvalid 驱动红/蓝）

* `project.dart` — 模型层不变

***

## 验证步骤

1. 创建分流器，依次创建左、上、右三个方向的输出传送带
2. 连接输入传送带，放入物品，观察物品分发顺序是否与创建顺序一致
3. 删除某条输出带后重建，验证新顺序
4. 创建分流器后不连输入带，点击分流器往下方拖拽 → 预览应为红色
5. 往左/上/右拖拽 → 预览应为蓝色正常
6. `flutter analyze` 无新增错误

