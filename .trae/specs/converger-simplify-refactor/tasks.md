# 汇流器（Converger）简化重构 - The Implementation Plan

## [ ] Task 1: 清理PlacedBuilding模型中的汇流器缓冲机制
- **Priority**: high
- **Depends On**: None
- **Description**: 
  - 从 [project.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/models/project.dart) 中移除 convergerBuffer 相关字段和方法：
    - 移除 `_convergerSlotKey` 常量
    - 移除 `convergerBufferOccupied` getter
    - 移除 `convergerBufferedItemId` getter
    - 移除 `convergerBufferedInputDirection` getter
    - 移除 `acceptIntoConvergerBuffer()` 方法
    - 移除 `consumeFromConvergerBuffer()` 方法
  - 保留并简化 `convergerArrivalTimestamps`（仅用于FCFS，不再与缓冲耦合）
  - 检查是否有其他地方引用了这些方法并同步清理
- **Acceptance Criteria Addressed**: AC-7
- **Test Requirements**:
  - `programmatic` TR-1.1: 项目能正常编译，无未定义方法/字段错误
  - `programmatic` TR-1.2: 所有对已移除方法的引用都已清理或替换
- **Notes**: convergerArrivalTimestamps 保留用于FCFS，但逻辑会在后续任务中简化

## [ ] Task 2: 简化belt_simulation_logic.dart中的_canBeltOutputEnterBuilding汇流器门控逻辑
- **Priority**: high
- **Depends On**: Task 1
- **Description**: 
  - 修改 [belt_simulation_logic.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/canvas/belt_simulation_logic.dart) 中 `_canBeltOutputEnterBuilding` 方法的汇流器分支：
    - 当前逻辑：只要outputBelt != null就返回true（让物品都到达末端排队）
    - 新逻辑：需要同时满足两个条件才返回true：
      1. outputBelt存在且outputBelt.canAcceptNewItemFromStart()返回true（输出带有空间接收新物品）
      2. 当前是FCFS选中的方向（最早到达的方向）
    - 这确保了：只有汇流器空闲且轮到该方向时，物品才能进入；其他方向物品在输入带上自然堵塞
  - 移除isInputToConverger特殊处理：不再需要对汇流器输入带采用"先消费再推进"的特殊顺序
    - 删除 `final isInputToConverger = inputBuilding != null && inputBuilding.isConverger;`
    - 删除 `String? activeSourceItemId = (isProducing && !isInputToConverger) ? sourceItemId : null;` 中的 `!isInputToConverger` 条件
    - 删除输入带处理顺序的if/else分支，统一使用先推进再消费的顺序（与其他设备一致）
- **Acceptance Criteria Addressed**: AC-1, AC-5, AC-6
- **Test Requirements**:
  - `programmatic` TR-2.1: 代码编译通过，无语法错误
  - `human-judgement` TR-2.2: 当汇流器正在处理一个物品时，其他输入带视觉上堵塞（变红），物品在带面上排队
- **Notes**: canAcceptNewItemFromStart需要传入正确的terminalLimit（与其他情况一致）

## [ ] Task 3: 简化_transferBeltOutputToBuilding中的汇流器物品传输逻辑
- **Priority**: high
- **Depends On**: Task 2
- **Description**: 
  - 重写 `_transferBeltOutputToBuilding` 方法中汇流器分支的逻辑：
    - 移除缓冲相关逻辑（不再尝试acceptIntoConvergerBuffer）
    - 移除_drainConvergerBuffer调用（整个方法删除）
    - 新逻辑：
      1. 验证是FCFS选中的方向（双重检查，与_canBeltOutputEnterBuilding一致）
      2. 获取输出带，检查canAcceptNewItemFromStart（双重检查）
      3. 直接调用outputBelt.pushSourceItem()，**不使用skipAdvanceOnce参数**（默认为false）
      4. 推送成功后：
         - 调用belt.removeOutputReadyItem()从输入带移除物品
         - 从convergerArrivalTimestamps中清除该方向的时间戳（允许下一个方向被选中）
         - 返回true
      5. 推送失败：返回false（下次tick重试）
  - 移除 `_drainConvergerBuffer` 方法（不再需要缓冲排空）
  - 清理相关的辅助方法中对缓冲的引用
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-4, AC-7
- **Test Requirements**:
  - `programmatic` TR-3.1: 代码编译通过
  - `human-judgement` TR-3.2: 物品从输入带到输出带平滑过渡，无箭头闪烁
  - `human-judgement` TR-3.3: 多个物品连续通过时，输出带物品紧密排列连续移动，无分批次卡顿
- **Notes**: 参考分流器的实现风格，但分流器有splitterBuffer是为了处理输出带暂时满的情况——汇流器也可以考虑保留类似的1物品缓冲处理输出带瞬满情况，但优先尝试"无缓冲直接推送+失败返回false重试"的极简方案

## [ ] Task 4: 简化_getAvailableOutputItemIdForBeltStart和_consumeOutputItemForBeltStart
- **Priority**: high
- **Depends On**: Task 3
- **Description**: 
  - 修改 `_getAvailableOutputItemIdForBeltStart` 中汇流器分支：
    - 当前逻辑：检查convergerBufferOccupied并返回bufferedItemId
    - 新逻辑：移除整个汇流器分支！因为汇流器不再是"生产者"（不像设备持续输出物品），物品是从输入带直接push到输出带的，输出带不应该从汇流器"拉取"物品
  - 修改 `_consumeOutputItemForBeltStart` 中汇流器分支：
    - 当前逻辑：消费convergerBuffer中的物品
    - 新逻辑：移除整个汇流器分支！物品在pushSourceItem成功时已经从输入带移除了，不需要在消费时再处理
  - 这是一个关键改动：汇流器不再作为输出带的"源建筑"持续提供物品，物品传输是一次性的push操作，与分流器的处理方式一致（参考分流器的处理：物品是在_transferBeltOutputToBuilding中直接被push到输出带的，而不是让输出带来拉取）
- **Acceptance Criteria Addressed**: AC-2, AC-4, AC-7
- **Test Requirements**:
  - `programmatic` TR-4.1: 代码编译通过
  - `human-judgement` TR-4.2: 物品正确从输入带移动到输出带，不会消失或重复
- **Notes**: 需要仔细对比分流器的处理方式——分流器输出带的物品来源是splitterBuffer，而分流器在_transferBeltOutputToBuilding中直接pushSourceItem到输出带（立即进入itemSegments），同时从输入带移除。这说明pushSourceItem直接将物品放入输出带的itemSegments，输出带正常推进即可，不需要源持续提供物品。这是关键理解点！

## [ ] Task 5: 移除skipAdvanceOnce相关的特殊处理
- **Priority**: high
- **Depends On**: Task 4
- **Description**: 
  - 检查并清理belt_simulation_logic.dart中所有与汇流器相关的skipAdvanceOnce逻辑：
    - pushSourceItem调用中不再传skipAdvanceOnce: true
    - 检查_tickSingleBeltOnce中处理skipAdvanceOnce标志的代码：
      ```dart
      if (firstSegment.skipAdvanceOnce) {
        // 分流器/汇流器推送后首次tick...
      }
      ```
      确保汇流器不再设置skipAdvanceOnce，这段代码如果是为分流器保留的则保留，但要确保不影响汇流器
    - 检查pushSourceItem内部是否有skipAdvanceOnce相关逻辑需要保留（给分流器用）
- **Acceptance Criteria Addressed**: AC-2, AC-4, AC-7
- **Test Requirements**:
  - `programmatic` TR-5.1: 搜索代码确认汇流器相关代码中不再出现skipAdvanceOnce
  - `human-judgement` TR-52: 物品推送后不会在position 0额外停留，直接开始平滑移动
- **Notes**: skipAdvanceOnce可能分流器还在使用（如果分流器也有问题则后续修复），本次只确保汇流器不再使用它

## [ ] Task 6: 清理冗余辅助方法和简化FCFS逻辑
- **Priority**: medium
- **Depends On**: Task 5
- **Description**: 
  - 检查并删除以下不再需要的方法（如果确认没有其他用途）：
    - _drainConvergerBuffer（已在Task 3删除）
    - _canConvergerOutputBeltAcceptItem（如果逻辑已合并到_canBeltOutputEnterBuilding和直接调用canAcceptNewItemFromStart）
  - 简化_findEarliestArrivalConvergerDirection方法：
    - 移除与缓冲相关的清理逻辑（如果有的话）
    - 保留核心的FCFS逻辑：清理过期方向、为新到达方向分配序号、返回最早方向
  - 检查_getBeltForConvergerInputDirection、_getBeltForConvergerOutputDirection、_getConnectedConvergerInputDirections等辅助方法是否还需要，做必要的简化
  - 确保 _beltArrivalDirection、_arrivalDirToInputPort、_inputPortToArrivalDir 等方向转换方法正确无误
- **Acceptance Criteria Addressed**: AC-7
- **Test Requirements**:
  - `programmatic` TR-6.1: 代码编译通过
  - `programmatic` TR-6.2: 无未使用的方法/变量警告（如果有分析器）
- **Notes**: 保持代码整洁，删除的方法要确认确实没有其他地方调用

## [ ] Task 7: 功能测试与动画验证
- **Priority**: high
- **Depends On**: Task 6
- **Description**: 
  - 启动flutter应用进行全面测试：
    1. 单输入单输出场景：一条输入带→汇流器→一条输出带，验证物品平滑通过
    2. 三输入场景：左、上、右三条输入带都供料，验证FCFS顺序
    3. 输出带堵塞场景：输出带末端放一个满的设备或死胡同，验证输入堵塞
    4. 输出带长队列场景：多个物品连续通过汇流器，验证输出带物品紧密排列无分批
    5. 分流器对比测试：测分流器是否工作正常，无回归
    6. 其他设备回归测试：物流桥、冶炼炉、仓库设备等是否正常
  - 发现问题及时修复
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-8
- **Test Requirements**:
  - `human-judgement` TR-7.1: 所有验收标准的视觉验证通过
  - `human-judgement` TR-7.2: 分流器和其他设备无回归bug
  - `programmatic` TR-7.3: flutter analyze无新增错误
- **Notes**: 这是最终验证环节，需要仔细观察动画流畅度
