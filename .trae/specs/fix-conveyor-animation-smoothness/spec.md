# 传送带动画平滑性修复 Spec

## Why
传送带存在两个动画逻辑问题，严重影响视觉体验：
1. **堵塞消失后物品位置跳变**：当物品队列因堵塞而冻结后，堵塞消失（延长传送带或输入设备有空位）时，物品会突然向后跳约半格再继续前进。在汇流器上尤为明显。
2. **不同物品队列停滞刷新**：当传送带上有不同 itemId 的物品时，首个物品正常前进，后方不同物品会反复"停滞→突然刷新"，无法连续移动。

两个问题的共同根因是 **freezeProgress 冻结/解冻状态机缺少平滑解冻过渡**：冻结时物品停在 0.5（格子中央），解冻时直接跳到当前 arrowProgress 值，造成视觉跳变。

## What Changes
- **新增解冻过渡状态 `-3.0`**：当物品从冻结状态（0.5）解冻时，不直接清除 freezeProgress，而是过渡到 `-3.0` 状态。该状态下物品渲染为 `max(0.5, arrowProgress)`——即不低于 0.5（不后跳），且当 arrowProgress > 0.5 时跟随全局相位前进。在下一次 tick 推进时由 `advanceItemSegments` 清除为 null。
- **移除解冻的 `isDeadEnd` 门控**：当前渲染器中解冻逻辑（lines 560-564）仅对死胡同传送带生效，连接建筑输入端口的传送带不执行渲染器解冻。修改为所有传送带统一使用 `-3.0` 过渡状态解冻。
- **恢复非末段物品的冻结**：在 `_freezeReadyOutputSegments` 和渲染器 `shouldFreezeSegment` 中，恢复非末段物品在 `fillCount >= limit` 时的冻结。此前移除该冻结导致了不同物品的停滞刷新问题（Bug 2）。配合 `-3.0` 平滑解冻，此前移除冻结时引发的"分批次移动"问题将不再出现。
- **统一 `freezeDeadEndSegments` 与 `_freezeReadyOutputSegments` 的冻结逻辑**：确保两者对非末段物品的冻结行为一致。

## Impact
- Affected code:
  - [transport_belt_renderer.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/AIC/Logistics%20Units/transport_belt_renderer.dart) — freezeProgress 状态机（lines 516-568）、每格进度选择（lines 842-877）
  - [belt_simulation_logic.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/canvas/belt_simulation_logic.dart) — `_freezeReadyOutputSegments`（lines 712-740）
  - [project.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/models/project.dart) — `freezeDeadEndSegments`（lines 903-922）、`advanceItemSegments`（lines 814-896）
- 不影响：传送带基础渲染、物品段数据模型、tick 驱动机制、分流器/物流桥/冶炼炉等其他设备

## ADDED Requirements

### Requirement: 平滑解冻过渡（-3.0 状态）
系统 SHALL 在物品从冻结状态解冻时，通过 `-3.0` 中间状态平滑过渡，避免位置跳变。

#### Scenario: 堵塞消失后物品不后跳
- **WHEN** 传送带上冻结在 0.5（格子中央）的物品因堵塞消失而需要解冻
- **THEN** 物品过渡到 `-3.0` 状态，渲染为 `max(0.5, arrowProgress)`，即从 0.5 开始跟随 arrowProgress 前进，绝不向后跳
- **AND** 在下一次 tick 时，`advanceItemSegments` 推进物品段并清除 freezeProgress 为 null，物品正常进入下一格

#### Scenario: 解冻后堵塞再次出现
- **WHEN** 物品处于 `-3.0` 解冻过渡状态时，`shouldFreezeSegment` 再次变为 true（堵塞返回）
- **THEN** 物品回退到 `0.5` 冻结状态（可能产生微小回跳，仅出现在堵塞立即返回的边缘情况，可接受）

#### Scenario: -3.0 状态的渲染
- **WHEN** 物品段的 freezeProgress 为 `-3.0`
- **THEN** 渲染时 cellArrowProgress = `max(0.5, arrowProgress)`，确保物品从中央位置开始平滑前进

### Requirement: 非末段物品冻结恢复
系统 SHALL 对所有物品段（包括非末段）在 `fillCount >= limit` 时执行冻结，防止不同 itemId 的物品在传送带上停滞刷新。

#### Scenario: 不同物品连续移动无停滞
- **GIVEN** 传送带上有 A、B 两个不同 itemId 的物品，A 在前方（末段），B 在后方（非末段）
- **WHEN** A 因到达极限而冻结在格子中央，B 也到达 A 的 drainCount 位置
- **THEN** B 也被冻结在格子中央（不跟随 arrowProgress 循环跳动）
- **AND** 当 A 前进时，B 的 limit 增加，B 通过 `-3.0` 平滑解冻并跟随前进，不出现"停滞→刷新"现象

## MODIFIED Requirements

### Requirement: freezeProgress 状态机
freezeProgress 状态机增加 `-3.0` 解冻过渡状态，完整状态流转如下：

| 值 | 含义 | 渲染值 | 转移条件 |
|---|---|---|---|
| `null` | 未冻结，跟随全局 arrowProgress | arrowProgress | shouldFreeze=true 时 → -1.0 |
| `-1.0` | 刚到达停止位置，等待 | arrowProgress | arrowProgress < 0.5 时 → -0.5 |
| `-0.5` | 等待 arrowProgress 回升 | arrowProgress | arrowProgress >= 0.5 时 → 0.5 |
| `0.5` | 冻结在格子中央 | 0.5 | shouldFreeze=false 时 → -3.0 |
| `-2.0` | 推进后临时冻结（遗留） | 0.5 | arrowProgress >= 0.5 时 → null |
| **`-3.0`** | **解冻过渡中** | **max(0.5, arrowProgress)** | **tick 推进时 → null；shouldFreeze=true 时 → 0.5** |

### Requirement: shouldFreezeSegment 判定
`shouldFreezeSegment` 判定修改为对所有物品段（不再区分 isLastSegment）在 `fillCount >= limit` 时返回 true：

```
shouldFreezeSegment = sourceSegment.freezeProgress != null || segment.fillCount >= limit
```

此前 `isLastSegment &&` 门控被移除，非末段物品也会在到达前方物品位置时冻结。

### Requirement: 解冻逻辑移除 isDeadEnd 门控
渲染器中的解冻逻辑不再依赖 `isDeadEnd`，所有传送带统一使用 `-3.0` 过渡状态：

```
// 旧逻辑（仅死胡同）:
if (!shouldFreezeSegment && isDeadEnd && freezeProgress != null)
    freezeProgress = null;

// 新逻辑（所有传送带）:
if (!shouldFreezeSegment && freezeProgress == 0.5)
    freezeProgress = -3.0;  // 平滑解冻过渡
if (shouldFreezeSegment && freezeProgress == -3.0)
    freezeProgress = 0.5;   // 堵塞返回，回退冻结
```

### Requirement: _freezeReadyOutputSegments 冻结所有段
`_freezeReadyOutputSegments` 修改为对所有物品段（不再仅 isLastSegment）在 `fillCount >= segLimit` 时设置 `freezeProgress = -1.0`，与 `freezeDeadEndSegments` 行为一致。
