# 传送带创建模式 HUD 修改记录

## 概述

本次修改针对传送带创建模式下屏幕空间 HUD（`ConveyorCreateModeHudPainter`）的视觉样式和动画连续性进行了全面重构，同时调整了浮动操作按钮的布局。后续又继续补充了"创建"模块的资源接入、活动范围、连续滚动与左右侧方向修正。最后增加了 HUD 错误状态动画和 Dock 栏错误提示 Toast。

## 涉及文件

| 文件 | 修改内容 |
|------|----------|
| `lib/canvas/conveyor_create_mode_hud.dart` | HUD 样式、间距、渐变、条纹方向、动画对齐、"创建"模块绘制与活动范围、错误状态动画 |
| `lib/canvas/canvas_editor.dart` | HUD 资源预加载、连续相位传入、错误提示回调 |
| `lib/widgets/floating_action_buttons.dart` | 按钮布局从横向改为竖向 |
| `lib/pages/editor_page.dart` | 错误提示 Toast 组件（红色胶囊、淡入淡出） |

---

## 一、HUD 样式修改

### 1.1 实心边框与斜条纹间距

**需求**：外侧实心长方形框距离斜条纹区域 2px。

**实现**：新增 `_gap = 5.0` 常量，斜条纹区域的起始偏移量计算为 `s = rail + _gap`。实心框宽度为 `rail`，斜条纹从 `s` 开始绘制，两者之间自然形成 2px 间隔。

### 1.2 左右侧轨向下透明渐变

**需求**：左右两侧的实心长方形框需要从上到下逐渐透明淡出。

**实现**：
- 新增 `_drawGradientRail()` 方法
- 使用 `saveLayer()` + `BlendMode.dstIn` + 线性渐变遮罩
- 渐变节点：`[0.0] 不透明 → [0.58] 半透明 → [1.0] 完全透明`
- 顶部横轨保持纯色不透明，仅左右侧轨应用渐变

### 1.3 斜条纹方向修正（右侧）

**需求**：右侧斜条纹方向需要与顶部一致形成顺时针流动效果。

**原状**：右侧为 `/` 方向（与左侧相同），导致右上角处两种方向的条纹交叉穿插。

**修复**：
- 右侧改为 `\` 方向（左上→右下）
- 路径绘制逻辑独立为 `_drawRightStripes()` 方法
- 右侧起始 Y 坐标下移至 `topHeight`（顶部条纹区域下方），避免重叠

### 1.4 顶部条纹延伸至最右边缘

**原状**：顶部条纹排除了左右侧边区域以防止角落重叠。

**修复**：顶部条纹宽度改为 `size.width - 2 * s`，覆盖全宽直达右边缘，与右侧 `\` 条纹在视觉上衔接。

### 1.5 三侧统一间距

**原状**：顶部间距 28px，侧边间距 30px，不一致导致左上角速率错位。

**修复**：统一使用 `_spacing = 28.0` 全局常量，三侧共用同一间距值。

---

## 二、条纹动画连续性（核心难点）

### 2.1 动画方向设计（顺时针旋转）

三侧条纹的运动方向模拟顺时针旋转：

| 区域 | 方向 | 运动方向 |
|------|------|----------|
| 左侧 | `/` | 向上移动 |
| 顶部 | `/` | 向右移动 |
| 右侧 | `\` | 向下移动 |

### 2.2 转角对齐问题与解决方案

**问题**：最初尝试用各侧独立的相位偏移（基于周长长度除以间距），但转角处仍存在像素级错位。

**根本原因**：每侧的迭代起点基于各自的局部坐标（`rect.top` / `rect.left`），即使相位经过周长换算，由于图案函数不同（左/顶用 `/` 方向，右侧用 `\` 方向），无法保证转角处的条纹线精确衔接。

**最终方案——统一全局图案函数**：

所有条纹由同一个数学图案函数驱动，确保任意坐标点属于同一条纹还是空白完全确定：

```
左侧 & 顶部:  pattern(x, y) = (x - y) / spacing + gp     （/ 方向）
右侧:        pattern(x, y) = (x + y) / spacing - rp       （\ 方向）
```

其中：
- `gp`（global phase）：左侧和顶部共用，来自动画控制器的 `phase % 1.0`
- `rp`（right phase）：根据右上角转角坐标计算，使 `\` 图案在该点与 `/` 图案无缝衔接

**右侧相位计算公式**：

```
cornerX = size.width - s    (右上角 X)
cornerY = topHeight         (右上角 Y)

在转角处要求:
  (cornerX - cornerY) / spacing + gp ≡ (cornerX + cornerY) / spacing - rp

解得:
  rp = (gp + 2 * cornerY / spacing) % 1.0
```

**迭代起点的推导**（从图案函数反推循环变量初始值）：

| 区域 | 图案函数 | 迭代起点 | 含义 |
|------|----------|----------|------|
| 顶部 `/` | `(x-y)/s + gp` | `xBase = rect.top + gp * s` | gp↑ → xBase↑ → 条纹右移 ✓ |
| 左侧 `/` | `(x-y)/s + gp` | `yBase = rect.left - gp * s` | gp↑ → yBase↓ → 条纹上移 ✓ |
| 右侧 `\` | `(x+y)/s - rp` | `yBase = -rect.left + rp * s` | rp↑ → yBase↑ → 条纹下移 ✓ |

这样无论屏幕尺寸如何、动画进行到哪个 phase，三侧的条纹都会像同一条连续的带子一样流过每个转角，不会出现断层或穿插。

---

## 三、浮动按钮布局调整

### 3.1 改为竖向排列

**文件**：`lib/widgets/floating_action_buttons.dart`

**改动**：
- 外层容器从 `Row` 改为 `Column`
- 间距从 `SizedBox(width: 12)` 改为 `SizedBox(height: 12)`
- 传送带模式按钮（E）在上，旋转画布按钮（R）在下

### 3.2 图层关系

`FloatingActionButtons` 在 `editor_page.dart` 的 Stack 中位于 `CanvasEditor` 之后（子列表靠后），因此渲染层级天然高于 CanvasEditor 内部绘制的 HUD 层，无需额外调整。

---

## 四、“创建”模块补充

### 4.1 资源接入与初始化

**新增资源**：`assets/svg/HUD_create_text.svg`

**实现**：
- 在 `ConveyorCreateModeHudPainter` 中新增 `init()`，使用 `flutter_svg` 的 `vg.loadPicture()` 预加载 `PictureInfo`
- 在 `CanvasEditor.initState()` 中调用 `ConveyorCreateModeHudPainter.init(onReady: _forceRepaint)`
- 这样 HUD 绘制阶段只负责平移、裁剪和缩放，不会在每帧重复解析 SVG

### 4.2 三侧统一条带宽高

**问题**：窗口比例变化时，顶部条带高度和左右侧条带宽度会出现不一致，导致“创建”模块与普通斜纹的视觉厚度不统一。

**修复**：
- 新增 `_stripeBand = 32.0`
- 顶部条纹区域高度固定为 `_stripeBand`
- 左右侧条纹区域宽度固定为 `_stripeBand`
- 顶部整体高度改为 `topHeight = rail + _gap + _stripeBand`

这样顶部与左右侧的斜纹带宽度始终一致，窗口拉伸时只影响长度，不影响厚度。

### 4.3 “创建”模块的统一间隔与连续滚动

**问题**：
- 模块间隔此前混入了斜切补偿，导致看起来不完全等距
- 顶部模块使用控制器 `value` 的 0~1 循环值时，会在动画循环处直接跳回开头

**修复**：
- 模块真实可视宽度定义为 `visualModuleWidth = moduleWidth + rect.height`
- 统一步进周期为 `modulePeriod = visualModuleWidth + moduleGap`
- 间隔常量统一为 `_createModuleGapCount`
- 在 `canvas_editor.dart` 中改为传入累计相位：

```dart
final hudPhase =
    (beltArrowController.lastElapsedDuration?.inMicroseconds ?? 0) /
        beltArrowController.duration!.inMicroseconds;
```

- 普通斜纹仍然使用 `phase % 1.0`
- “创建”模块则使用连续 `phase` 计算位移：`travel = phase * _spacing`

这样模块移动速度与普通斜纹同步，同时又能实现无缝循环滚动。

### 4.4 三段斜切活动范围

**问题**：最初“创建”模块分别在顶部、左侧、右侧的直角矩形区域中活动，转角处的活动范围与整体 HUD 斜切轮廓不一致。

**修复**：
- 将“创建”模块从普通斜纹绘制逻辑中拆出
- 在 `paintHud()` 末尾统一调用 `_drawCreateModules()`
- 分别为顶部、左侧、右侧定义独立的活动区裁剪路径：
  - `_topCreateAreaPath()`
  - `_leftCreateAreaPath()`
  - `_rightCreateAreaPath()`

活动范围由三段斜切区域组成：
- 顶部：下边左右各切去一个斜角
- 左侧：从左上角斜切接入，再沿左边向下
- 右侧：从右上角斜切接入，再沿右边向下

这样“创建”模块的可活动区域与 HUD 主轮廓一致，更接近完整外框一圈的视觉效果。

### 4.5 左右侧模块方向修正

**问题**：
- 左侧“创建”模块的斜边长方形方向与左侧底纹不一致
- 左侧模块动画方向一度表现为从上往下，和左侧普通斜纹的向上流动相反

**修复**：
- 左侧在 `_drawCreateModules()` 中使用：
  - `reverse: true`：使模块动画方向改为向上
  - `mirrorShape: true`：对模块本体做水平镜像
- 右侧保持 `reverse: false`，不改动已有正常效果

这样左侧“创建”模块会和左边 `\` 斜纹保持相同的视觉倾斜与运动方向。

### 4.6 文字居中缩放

**实现**：
- 使用 `_drawPictureScaled()` 将 `HUD_create_text.svg` 按目标矩形等比缩放
- 文字放置区域基于模块整体可视包围盒 `visualRect` 计算，而不是只基于上边的平边长度

这样文字能更稳定地居中于斜边模块内部，不会因斜切部分被忽略而偏移。

---

## 五、参数速查表

| 参数 | 值 | 说明 |
|------|-----|------|
| `_gap` | 2.0 px | 实心框与斜条纹区间距 |
| `_spacing` | 28.0 px | 三侧统一的条纹间距 |
| `_thickness` | 10.0 px | 单条条纹的厚度 |
| `_stripeBand` | 32.0 px | 三侧统一的条带厚度 |
| `_createModuleStripeCount` | 3.15 | 单个“创建”模块的基础长度倍数 |
| `_createModuleGapCount` | 2.7 | 相邻“创建”模块的统一间隔倍数 |
| `rail` | 10~16 px | 实心边框宽度（响应式） |
| `topHeight` | `rail + _gap + _stripeBand` | 顶部条纹区域总高度 |
| `sideWidth` | 32.0 px | 侧边条纹区域宽度 |
| 渐变节点 | [0.0, 0.58, 1.0] | 透明度 [100%, 80%, 0%] |

---

## 六、代码结构总览

```
ConveyorCreateModeHudPainter
├── init()                  — 预加载 HUD_create_text.svg + HUD_error_text.svg
├── triggerError()          — 触发 HUD 错误动画（公开方法）
├── paintHud()              — 入口：计算尺寸参数、相位分配、统一调度"创建"模块
│
├── _updateErrorState()     — 每帧计算错误动画状态（颜色/透明度/SVG混合）
├── _drawSolidRails()       — 绘制三条实心边框（含渐变）
│   └── _drawGradientRail() — 单条渐变边框（saveLayer + dstIn）
│
├── _drawTopStripes()       — 顶部 `/` 条纹，向右移动
├── _drawLeftStripes()      — 左侧 `/` 条纹，向上移动
├── _drawRightStripes()     — 右侧 `\` 条纹，向下移动
│
├── _drawCreateModules()        — 统一调度三侧"创建"模块
├── _drawTopCreateModules()     — 顶部斜切活动区
├── _drawSideCreateModules()    — 左右侧斜切活动区
├── _topCreateAreaPath()        — 顶部活动区裁剪路径
├── _leftCreateAreaPath()       — 左侧活动区裁剪路径
├── _rightCreateAreaPath()      — 右侧活动区裁剪路径
├── _drawHorizontalCreateModules() — 画单个方向上的连续模块流（含 SVG 交叉淡入淡出）
├── _drawPictureScaled()        — 居中缩放绘制 SVG（支持 tintColor 着色 + opacity 透明度）
│
└── _applyVerticalFade()    — 共享的垂直渐变遮罩（侧边用）
```

---

## 七、HUD 错误状态动画

### 7.1 需求

传送带创建失败时，HUD 需要从黄色变为红色，"创建"模块内的 `HUD_create_text.svg` 替换为 `HUD_error_text.svg`（白色），并闪烁两次后自然恢复。

### 7.2 错误触发条件

| 场景 | 触发条件 | Toast 文字 |
|------|----------|------------|
| 空白网格点击 | 进入创建模式后点击空白网格（未从设备输出端开始） | "请从设备输出端口进行创建" |
| 红色预览点击 | 传送带预览为红色时点击创建 | "设备重叠" |
| 设备放置重叠 | 放置设备时与已有建筑/传送带碰撞 | "设备重叠" |

### 7.3 错误动画时序

动画总时长 1500ms，分三个阶段：

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: 闪烁 (0~600ms)                                    │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐                               │
│ │淡出│ │淡入│ │淡出│ │淡入│  每半周期 150ms，共 2 次完整闪烁 │
│ └────┘ └────┘ └────┘ └────┘                               │
│                                                             │
│ Phase 2: 保持红色 (600~1000ms)                              │
│ ████████████████████████████                                │
│                                                             │
│ Phase 3: 过渡恢复 (1000~1500ms)                             │
│ 红色 → 黄色渐变，SVG 交叉淡入淡出                            │
└─────────────────────────────────────────────────────────────┘
```

### 7.4 实现细节

**新增状态变量**：

| 变量 | 类型 | 说明 |
|------|------|------|
| `_isError` | `bool` | 是否处于错误动画中 |
| `_errorStartTimeUs` | `int?` | 错误动画起始时间（微秒） |
| `_frameColor` | `Color` | 当前帧的主色（黄色/红色/插值） |
| `_frameOpacity` | `double` | 当前帧的全局透明度（闪烁用） |
| `_frameSvgBlend` | `double` | SVG 混合系数（0=创建，1=错误） |

**新增常量**：

| 常量 | 值 | 说明 |
|------|-----|------|
| `_red` | `0xFFFF3B30` | 错误红色 |
| `_flashHalfUs` | 150000 μs | 闪烁半周期 |
| `_holdUs` | 400000 μs | 保持红色时长 |
| `_transitionUs` | 500000 μs | 过渡恢复时长 |

**核心方法**：

- `triggerError()` — 公开方法，重置动画起始时间，触发错误状态
- `_updateErrorState()` — 每帧调用，根据经过时间计算 `_frameColor` / `_frameOpacity` / `_frameSvgBlend`

**闪烁实现**：

在 `paintHud()` 入口处调用 `_updateErrorState()`，当 `_frameOpacity < 1.0` 时，用 `saveLayer` + 半透明白色 Paint 包裹整个 HUD 绘制，实现全局透明度控制。

**颜色切换**：

所有绘制方法中原本硬编码的 `_yellow` 改为使用 `_frameColor`，包括实心轨道、斜条纹、创建模块本体。

**SVG 切换**：

- `init()` 同时加载 `HUD_create_text.svg` 和 `HUD_error_text.svg`
- `_drawHorizontalCreateModules()` 根据 `_frameSvgBlend` 交叉绘制两个 SVG
- 过渡阶段（Phase 3）中 `_frameSvgBlend` 从 1.0 线性过渡到 0.0，实现文字交叉淡入淡出

**SVG 白色着色**：

`_drawPictureScaled()` 新增 `tintColor` 和 `opacity` 参数：
- 使用 `saveLayer` + `BlendMode.srcIn` 将 SVG 原始深灰色替换为白色
- `opacity` 参数控制 SVG 透明度，用于交叉淡入淡出

---

## 八、Dock 栏错误提示 Toast

### 8.1 需求

在 Dock 栏上方显示红色胶囊形状的错误提示，文字为白色，带淡入淡出效果。

### 8.2 实现位置

Toast 组件位于 `editor_page.dart` 的 Stack 中，`bottom: 124`（Dock 栏上方），水平居中。

### 8.3 动画机制

- 使用 `AnimationController`（300ms）驱动 `FadeTransition`
- 显示时：`forward(from: 0.0)` 淡入
- 2 秒后：`reverse()` 淡出，完成后清除消息
- 新消息覆盖旧消息时，取消旧定时器并重新淡入

### 8.4 回调链路

```
CanvasEditor._handleTap() / _placeBuilding()
  → widget.onErrorToast?.call(message)
    → EditorPage._showErrorToast(message)
      → setState(_toastMessage = message)
      → _toastController.forward()
      → Timer(2s) → _toastController.reverse() → setState(_toastMessage = null)
```

### 8.5 视觉样式

| 属性 | 值 |
|------|-----|
| 背景色 | `0xCCFF3B30`（80% 不透明红色） |
| 圆角 | `20`（胶囊形状） |
| 内边距 | 水平 20，垂直 10 |
| 文字颜色 | `0xFFFFFFFF`（白色） |
| 文字大小 | 14 |
| 文字粗细 | `FontWeight.w500` |
