# 传送带物品动画闪烁与位置不一致修复

## 背景

传送带上物品图片的动画逻辑存在三个相互关联的问题，导致：
1. 物品在第一格反复出现/消失（闪烁）
2. 物品与最后一个指针（pointer）在同一格同时可见
3. 两条相同长度的传送带，物品停止时位置随机不同

## 根本原因

### 当前设计（有缺陷）

当前代码中，物品在格子内的位置由两套相互独立的系统控制：

1. **哪些格子显示物品**：由 `effectiveFillProgress` / `effectiveDrainProgress` 决定，这是一个以"单元格数"为单位的浮点数，通过 `DateTime` 时间戳 + `arrowProgress` 锚点的公式计算。

2. **物品在格子内的相对位置**：由 `arrowProgress`（AnimationController，0→1 循环，2秒一圈）决定，和箭头（pointer）使用完全相同的公式 `(0.5 - pProgress) * cellSize`。

**问题所在**：
- `effectiveFillProgress` 的计算公式为：`cycles + 1.0`，其中 `cycles = round(elapsed * 0.5 - (arrowProgress - startProgress))`，`round()` 会在 `.5` 附近震荡（1→0→1），导致第一格在"有物品"和"无物品"之间反复切换。
- 由于 `effectiveFillProgress` 和 `arrowProgress` 是两套完全独立的系统，两条传送带即使长度相同，因为 `itemFillStartTime` 时刻不同，导致 `elapsed` 不同，最终 `cycles` 不同，停止位置随机。

### 用户设想的正确模型

> 箭头和物品图片是同一类型的东西，动画形式、移动速度完全一样，只是箭头作为空白占位符。物品图片慢慢替换箭头，就像水挤压空气一样。

**这个模型的核心**: 物品图片和箭头使用完全相同的运动公式，区别只在于"哪些格子画物品图片，哪些格子画箭头"。

## 解决方案

### 核心思路

抛弃当前用时间戳计算 `itemFillProgress` 的方式，改用**纯粹基于 `arrowProgress` 的格子填充计数器**：

- `itemFillCount`（整数）：已被物品填充的格子数量，每当 `arrowProgress` 完成一个完整循环（跨过0点），`itemFillCount` 增加1（或减少1），直到达到 `path.length`。
- 物品在格子内的相对位置：和箭头完全一样，都用 `arrowProgress`。

这样两条传送带（相同长度，相同速度）的 `itemFillCount` 增加逻辑完全一致，停止位置也必然相同。

### 具体修改

#### `ConveyorBelt` 模型的变化

| 旧字段 | 新字段 | 说明 |
|--------|--------|------|
| `itemFillProgress` (double, 单位格) | `itemFillCount` (int) | 已填充格子数 |
| `itemDrainProgress` (double) | `itemDrainCount` (int) | 已排空格子数 |
| `itemFillStartTime`, `itemFillStartProgress` | **移除** | 改为事件驱动 |
| `itemDrainStartTime`, `itemDrainStartProgress` | **移除** | 改为事件驱动 |
| `lastItemFillProgress`, `lastItemDrainProgress` (double) | `lastItemFillCount`, `lastItemDrainCount` (int) | 残留物品同理 |
| `lastItemDrainStartTime`, `lastItemDrainStartProgress` | **移除** | 事件驱动 |
| `deadEndFreezeProgress` | **移除** | 不再需要冻结 |

#### 填充/排空触发机制

物品格子数的增减不在渲染帧里计算，而是在**每次 `arrowProgress` 跨过 `0`（完成一格的传输）** 时触发：

- `AnimationController` 增加 `addStatusListener` 监听 `repeat()`，但 `repeat()` 不提供"每次循环"的回调。
- **方案**：在 `_onTick` 里检测 `arrowProgress` 上一帧和这一帧是否跨过 0 点（即 `prev > 0.5 && curr < 0.5`），如果跨过则对所有传送带触发一次"时钟滴答"。

#### 渲染逻辑

`_renderWithSvg` 里不再计算 `effectiveFillProgress`，改为：

```dart
// 判断格子 i 是否显示物品：i < itemFillCount && i >= itemDrainCount
final cellCurrentFilled = itemImage != null && i >= drainCount && i < fillCount;
```

物品在格子内的位置直接用 `arrowProgress`，和箭头完全一样：
```dart
final double moveDist = (0.5 - arrowProgress) * cellSize;
```

#### "水龙头"效果的实现

- **源存在时**：每个时钟滴答，`itemFillCount < path.length` 时递增1
- **源断开时**：`itemFillCount` 不再递增，但 `itemDrainCount` 每个时钟滴答递增1
- **效果**：物品图片从头部逐格出现（头部格完成一格传输动画后，下一格也开始显示物品图片），直到整条传送带填满；断开后，物品图片逐格从头部消失

## 需要修改的文件

### [`ConveyorBelt`（project.dart）](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/models/project.dart)
- 替换 `itemFillProgress` 等浮点字段为 `itemFillCount` 等整数字段

### [`transport_belt_renderer.dart`](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/AIC/Logistics%20Units/transport_belt_renderer.dart)
- `renderConveyorPath`：移除所有时间戳计算逻辑，直接读取 `itemFillCount`
- `_renderWithSvg`：简化填充判断逻辑

### [`canvas_editor.dart`](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/canvas/canvas_editor.dart)
- `_EditorPainter.paint`：在渲染循环外，检测 `arrowProgress` 是否跨零，如果跨零则对所有传送带执行一次"时钟滴答"

### [`simulation_engine.dart`](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/canvas/simulation_engine.dart) 和 [`sim_worker.dart`](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/canvas/sim_worker.dart)
- 同步更新字段名（`itemFillProgress` → `itemFillCount` 等）

### [`sim_protocol.dart`](file:///C:/Users/Misaki/Desktop/git/Endfield/lib/canvas/sim_protocol.dart)
- 更新协议中的字段类型

## Open Questions

> [!IMPORTANT]
> **关于 `itemFillCount` 的初始状态**：当传送带刚连接到输出源时，应该立即将 `itemFillCount` 设为 0，然后等待时钟滴答递增。但源的 `itemId` 是通过仿真引擎的 `_applyTickResult` 推送过来的，时序上可能有延迟。需要确认：当 `itemId` 从空变为非空时，是否立即初始化 `itemFillCount = 0`。

> [!NOTE]
> **关于断头传送带（dead end）**：当前代码对断头传送带有特殊处理（物品到达尽头后停止移动）。新方案中断头传送带的 `itemFillCount` 在达到 `path.length` 后停止递增，这与原来行为一致。

## 验证计划

1. 创建一条连接仓库取货口的传送带，设置物品后检查：
   - 物品从传送带起点逐格出现，无闪烁
   - 物品位置与箭头动画同步
2. 创建两条相同长度的传送带，同时连接同一源，检查物品停止位置是否相同
3. 移动仓库取货口断开连接，检查传送带上的物品是否逐格从头部消失（被箭头替换）
