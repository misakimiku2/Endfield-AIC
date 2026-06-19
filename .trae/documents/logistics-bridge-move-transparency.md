# 物流桥移动时传送带透明化方案

## 问题描述
当前点击移动物流桥时，进入移动预览后，物流桥下方的传送带格子仍然正常显示（不透明）。只有确认移动后，`_removePortBeltCells` 才会移除该格传送带。正确行为应为：
- **进入移动预览时**：物流桥网格处的传送带格子背景变为透明，物品正常传输
- **确认移动时**：该格传送带被移除（现有逻辑）
- **取消移动时**：传送带恢复正常显示

## 当前状态分析

### 关键文件
1. **`lib/canvas/canvas_editor.dart`** — 移动模式入口、渲染循环
2. **`lib/AIC/Logistics Units/transport_belt_renderer.dart`** — 传送带渲染器

### 现有机制
- `_enterMoveMode()` (L1165) / `startMoveFromDialog()` (L678)：进入移动模式，设置 `_movingBuilding`
- `_placeMovingBuilding()` (L1433)：确认移动时调用 `_removePortBeltCells()` 移除端口传送带
- `cancelMoveMode()` (L1424)：取消移动，仅清空 `_movingBuilding`
- 渲染循环中 (L2131)：`if (pb == movingBuilding) continue;` 跳过移动中建筑的渲染
- 物流桥所有端口（4入4出）的 `gridPosition` 都等于物流桥自身网格坐标，因此 `_removePortBeltCells` 会拆分物流桥位置的传送带

### 已有类似机制
- `hideTerminalBackground` 参数：跳过传送带最后一格的背景绘制，但物品仍正常渲染
- 实现位置：`_renderWithSvg()` L687-688，`if (hideTerminalBackground && i == path.length - 1) continue;`

## 修改方案

### 1. 新增状态变量（canvas_editor.dart）
在 `CanvasEditorState` 中添加：
```dart
Offset? _bridgeMoveHiddenCell; // 物流桥移动时需要隐藏背景的格子
```

### 2. 进入移动模式时记录隐藏格子（canvas_editor.dart）
在 `_enterMoveMode()` 和 `startMoveFromDialog()` 中，如果移动的是物流桥，记录其网格位置：
```dart
if (_movingBuilding!.isBeltBridge) {
  _bridgeMoveHiddenCell = Offset(
    _movingBuilding!.gridX.toDouble(),
    _movingBuilding!.gridY.toDouble(),
  );
}
```

### 3. 渲染时传递隐藏格子信息（canvas_editor.dart）
在传送带渲染循环中（L1899-2042），将 `_bridgeMoveHiddenCell` 传递给 `renderConveyorPath`：
- 新增参数 `hiddenBackgroundCells`（`Set<Offset>?` 类型）
- 当 `_bridgeMoveHiddenCell != null` 时，构建 `{_bridgeMoveHiddenCell!}` 传入

### 4. 传送带渲染器支持隐藏指定格子背景（transport_belt_renderer.dart）
在 `renderConveyorPath()` 和 `_renderWithSvg()` 中新增参数：
```dart
Set<Offset>? hiddenBackgroundCells,
```
在背景绘制循环中，增加跳过逻辑：
```dart
if (hiddenBackgroundCells != null && hiddenBackgroundCells.contains(cell)) continue;
```
这与 `hideTerminalBackground` 逻辑类似，但基于格子坐标集合判断。

### 5. 确认移动时清除状态（canvas_editor.dart）
在 `_placeMovingBuilding()` 中，移动确认后清空：
```dart
_bridgeMoveHiddenCell = null;
```
（`_removePortBeltCells` 已有逻辑会实际移除该格传送带）

### 6. 取消移动时清除状态（canvas_editor.dart）
在 `cancelMoveMode()` 中清空：
```dart
_bridgeMoveHiddenCell = null;
```
（取消后传送带自动恢复正常渲染）

## 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `lib/canvas/canvas_editor.dart` | 1. 新增 `_bridgeMoveHiddenCell` 状态变量<br>2. `_enterMoveMode()` 中记录物流桥格子<br>3. `startMoveFromDialog()` 中记录物流桥格子<br>4. 渲染循环中传递 `hiddenBackgroundCells`<br>5. `_placeMovingBuilding()` 中清除状态<br>6. `cancelMoveMode()` 中清除状态 |
| `lib/AIC/Logistics Units/transport_belt_renderer.dart` | 1. `renderConveyorPath()` 新增 `hiddenBackgroundCells` 参数<br>2. `_renderWithSvg()` 新增 `hiddenBackgroundCells` 参数<br>3. 背景绘制循环中跳过隐藏格子 |

## 验证步骤
1. 放置物流桥和穿过它的传送带
2. 点击物流桥的移动按钮，确认传送带格子背景变透明、物品正常传输
3. 确认移动后，原位置传送带被正确移除
4. 再次测试：进入移动预览后按 ESC 取消，确认传送带恢复正常显示
5. 运行 `dart analyze` 确保无静态分析错误
