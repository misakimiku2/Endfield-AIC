# 传送带动画平滑性修复 - 实现计划

## [x] Task 1: 在渲染器中实现 -3.0 解冻过渡状态
- **Priority**: high
- **Depends On**: None
- **Description**:
  - 修改 [transport_belt_renderer.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/AIC/Logistics%20Units/transport_belt_renderer.dart) 的 freezeProgress 状态机（lines 516-568）：
    - 新增 `-3.0` 解冻过渡状态的转移逻辑：
      - 当 `!shouldFreezeSegment && freezeProgress == 0.5` 时：`freezeProgress = -3.0`（开始平滑解冻）
      - 当 `!shouldFreezeSegment && freezeProgress == -3.0` 时：保持 `-3.0`（等待 tick 推进）
      - 当 `shouldFreezeSegment && freezeProgress == -3.0` 时：`freezeProgress = 0.5`（堵塞返回，回退冻结）
    - 移除原有解冻逻辑中的 `isDeadEnd` 门控（lines 560-564），替换为上述 `-3.0` 过渡逻辑
    - 对 `-1.0` 和 `-0.5` 状态也需处理：当 `!shouldFreezeSegment` 时直接过渡到 `-3.0`
  - 修改每格进度选择逻辑（lines 856-860），增加 `-3.0` 的渲染：
    ```dart
    if (frozen == -3.0) {
      cellArrowProgress = arrowProgress < 0.5 ? 0.5 : arrowProgress;
    } else if (frozen != null && (frozen > 0 || frozen == -2.0)) {
      cellArrowProgress = frozen == -2.0 ? 0.5 : frozen;
    }
    ```
- **Acceptance Criteria Addressed**: Bug 1（堵塞消失后位置跳变）
- **Test Requirements**:
  - `programmatic` TR-1.1: 代码编译通过，无语法错误
  - `human-judgement` TR-1.2: 死胡同传送带堵塞消失后，物品从中央位置平滑前进，不后跳

## [x] Task 2: 恢复非末段物品的冻结逻辑
- **Priority**: high
- **Depends On**: Task 1
- **Description**:
  - 修改 [transport_belt_renderer.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/AIC/Logistics%20Units/transport_belt_renderer.dart) 的 `shouldFreezeSegment` 判定（lines 541-543）：
    - 旧：`sourceSegment.freezeProgress != null || (isLastSegment && segment.fillCount >= limit)`
    - 新：`sourceSegment.freezeProgress != null || segment.fillCount >= limit`
    - 移除 `isLastSegment` 门控，使非末段物品也按 `fillCount >= limit` 冻结
    - 更新相关注释说明：配合 -3.0 平滑解冻，非末段冻结不再导致分批次移动
  - 修改 [belt_simulation_logic.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/canvas/belt_simulation_logic.dart) 的 `_freezeReadyOutputSegments`（lines 712-740）：
    - 旧：`if (isLastSegment && segment.fillCount >= segLimit && segment.freezeProgress == null)`
    - 新：`if (segment.fillCount >= segLimit && segment.freezeProgress == null)`
    - 移除 `isLastSegment` 门控，使所有物品段在到达极限时冻结
    - 更新相关注释
- **Acceptance Criteria Addressed**: Bug 2（不同物品停滞刷新）
- **Test Requirements**:
  - `programmatic` TR-2.1: 代码编译通过
  - `human-judgement` TR-2.2: 传送带上有不同 itemId 的 A、B 物品时，B 不再停滞刷新，跟随 A 平滑前进

## [x] Task 3: 验证 advanceItemSegments 对 -3.0 状态的处理
- **Priority**: high
- **Depends On**: Task 1
- **Description**:
  - 检查 [project.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/models/project.dart) 的 `advanceItemSegments`（lines 814-896）：
    - 确认当物品段推进时（fillCount++/drainCount++），`freezeProgress = null` 已正确清除 `-3.0` 状态（现有代码已覆盖此情况）
    - 确认当物品段无法推进时（fillCount >= limit），`freezeProgress` 保持 `-3.0` 不变（现有代码不修改未推进段的 freezeProgress，已覆盖）
    - 确认 `freezeDeadEndSegments`（lines 903-922）不会覆盖 `-3.0` 状态（仅当 `freezeProgress == null` 时设置 -1.0，已覆盖）
  - 如有遗漏，补充必要的保护逻辑
- **Acceptance Criteria Addressed**: Bug 1
- **Test Requirements**:
  - `programmatic` TR-3.1: 代码编译通过
  - `human-judgement` TR-3.2: 物品在 -3.0 状态下推进后正常进入下一格，不残留异常状态

## [x] Task 4: 功能测试与动画验证
- **Priority**: high
- **Depends On**: Task 2, Task 3
- **Description**:
  - 启动 flutter 应用进行全面测试：
    1. **Bug 1 验证 - 死胡同传送带**：创建死胡同传送带，填满物品使其冻结，然后延长传送带，观察物品是否从中央位置平滑前进不后跳
    2. **Bug 1 验证 - 建筑输入端口**：传送带连接到满输入设备，物品冻结，然后让设备有空位，观察物品是否平滑前进不后跳
    3. **Bug 1 验证 - 汇流器**：汇流器输入带物品冻结，汇流器处理完物品后，输入带物品是否平滑前进不后跳
    4. **Bug 2 验证 - 不同物品**：传送带上有 A、B 两个不同 itemId 的物品，A 在前方冻结，B 在后方是否也冻结不刷新，A 前进时 B 是否平滑跟随
    5. **Bug 2 验证 - 汇流器输出**：汇流器输出带上有不同物品时，是否连续移动无分批次
    6. **回归测试 - 分流器**：分流器物品分流动画正常
    7. **回归测试 - 物流桥**：物流桥跨层传输正常
    8. **回归测试 - 冶炼炉等设备**：生产设备输入输出正常
    9. **回归测试 - 传送带创建/延伸/删除**：操作正常
  - 发现问题及时修复
- **Acceptance Criteria Addressed**: 所有验收标准
- **Test Requirements**:
  - `human-judgement` TR-4.1: Bug 1 和 Bug 2 的视觉验证通过
  - `human-judgement` TR-4.2: 分流器和其他设备无回归 bug
  - `programmatic` TR-4.3: flutter analyze 无新增错误

# Task Dependencies
- [Task 2] depends on [Task 1]（-3.0 解冻状态必须先实现，否则恢复非末段冻结会导致分批次移动回归）
- [Task 3] depends on [Task 1]（验证 -3.0 状态处理需要先实现该状态）
- [Task 4] depends on [Task 2, Task 3]（全面测试需要所有修改完成）
