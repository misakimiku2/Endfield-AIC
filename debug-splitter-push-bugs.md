# Debug Session: splitter-push-bugs
- **Status**: [OPEN]
- **Issue**: 分流器推送式重构后存在三个 Bug：(1) 满传送带仍短暂接收物品后消失；(2) 上方传送带物品瞬移；(3) 先创建输出带后创建输入带会合并
- **Debug Server**: http://127.0.0.1:7777/event
- **Log File**: .dbg/trae-debug-log-splitter-push-bugs.ndjson

## Reproduction Steps
1. 创建分流器，输出端布局：左2格、上3格、右5格
2. 创建输入传送带连接分流器输入端
3. 观察物品分配行为

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | `_canSplitterOutputBeltAcceptItem` 在满带检查时使用了过时的段数据（`ensureItemSegmentsFromLegacy` 从 legacy 字段重建段时丢失冻结状态），导致 `canAcceptNewItemFromStart` 误判为有空位 | High | Low | Pending |
| B | `pushSourceItem` 成功后，输出带的 tick 中 `advanceItemSegments` 将新段推进到与已冻结段重叠，随后 `_mergeAdjacentSegments` 或 `removeWhere(!hasItems)` 将其清除 | High | Medium | Pending |
| C | 上方传送带物品瞬移：分流器输出带起始格与分流器同格，`pushSourceItem` 在位置0创建段，但渲染时位置0被分流器建筑遮挡，物品从位置1开始可见，看起来像瞬移 | Medium | Low | Pending |
| D | 上方传送带物品瞬移：输出带的 `_tickSingleBeltOnce` 在同一帧内同时 `pushSourceItem` 和 `advanceItemSegments`，导致物品在一帧内从位置0跳到位置1+ | Medium | Medium | Pending |
| E | 先创建输出带后创建输入带合并：`_handleFirstAnchor` 检测到分流器格子已有传送带时，走 `_findBeltAtCell` 分支而非建筑输出端口分支，导致新带与旧带合并 | High | Low | Pending |

## Log Evidence
[待收集]

## Verification Conclusion
[待分析]
