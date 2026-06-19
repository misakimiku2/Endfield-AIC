# 07 — AIC 设备模块

> 对应目录：`lib/AIC/`

AIC 目录下的文件可分为三类：
- **配置类（Config）**：纯静态常量定义（id、尺寸、端口列表）
- **渲染器类（Renderer）**：负责将建筑绘制到 Canvas
- **控制器类（Controller）**：`TransportBeltController`，唯一包含复杂业务逻辑

```
lib/AIC/
├── Production I/
│   └── refining_unit.dart              精炼炉（3x3）配置 + 渲染器
├── Depot Access/
│   └── depot_access.dart               仓库存货口/取货口（3x1）配置 + 渲染器
└── Logistics Units/
    ├── belt_bridge.dart                物流桥（1x1）配置
    ├── converger.dart                  汇流器（1x1）配置
    ├── splitter.dart                   分流器（1x1）配置
    ├── item_control_port.dart          物品准入口（1x1）配置
    ├── logistics_unit_renderer.dart    物流单元共用渲染器
    ├── transport_belt.dart             传送带控制器（路径规划核心）
    └── transport_belt_renderer.dart    传送带渲染器
```

> 传送带控制器与渲染器是项目最复杂的模块，单独成章：[08-传送带系统](./08-传送带系统.md)。

---

## 7.1 `Production I/refining_unit.dart` — 精炼炉

定义精炼炉（3x3，4 输入 4 输出，含固体与液体端口）的配置常量及模块化 SVG 渲染器。

### `RefiningUnitConfig`（static const）

| 字段 | 值 | 说明 |
|------|----|------|
| `id` | `'refining_unit_3x3'` | 唯一标识 |
| `name` | `'精炼炉'` | 显示名称 |
| `gridWidth` / `gridHeight` | 3 / 3 | 占地尺寸 |
| `color` | `'#E8751A'` | 颜色 |
| `category` | `'basic_production'` | 分类 |
| `maxInputs` / `maxOutputs` | 4 / 4 | 端口数 |
| `inputPorts` | 3 固体底边 `down` + 1 液体左边 `left` | 输入端口 |
| `outputPorts` | 3 固体顶边 `up` + 1 液体右边 `right` | 输出端口 |

### `RefiningUnitRenderer`

模块化加载 4 个 SVG，按端口连接状态动态着色，Logo 双层绘制（背景层 150% 缩放 40% 透明 + 前景层原尺寸）。

**关键常量**：
- 颜色：`_frameColor`、`_cellBorderColor`、`_bodyColor`
- 尺寸：`_frameStrokeWidth=3.0`、`_cellBorderStrokeWidth=0.8`、`_baseSvgSize=50.8`
- 模块相对定位：`_liquidExportRelX/Y/W/H`、`_liquidImportRelX/Y/W/H`、`_logoRelX/Y/W/H`

**关键方法**：
- `static Future<void> init({VoidCallback? onReady})` — 加载 `3x3_unit.svg`、`liquid_export.svg`、`liquid_import.svg`、`LOGO/Refining_Unit_Logo.svg`，生成默认状态 SVG（base 默认 key `'000000'`，液体端口默认 key `'0'`），清理后解析缓存
- `static String _cleanInkscapeSvg(String svg)` — 清理 Inkscape 命名空间等 flutter_svg 不兼容元素
- `static bool get isReady` — 4 个 PictureInfo 全部加载完成
- `static void render(Canvas, Building, gridX, gridY, cellSize, rotation, {activeRecipe, isBlocked, productionProgress, portConnections, detailLevel})` — 旋转后调用 `_drawSvgBody`
- `static void renderPlaceholder(...)` — 半透明预览，蓝/红着色，调用 `BuildingRenderer.drawPortArrows`，再单独 `renderLogo`
- `static void renderLogo(Canvas, x, y, w, h, buildingRotation, canvasRotation, {opacity, tintBlue, tintRed})` — **双层 Logo 绘制**：背景层 150% 缩放 + 40% 透明度，前景层原尺寸；均用 `counterAngle = -(buildingAngle + canvasRotation)` 反向旋转保持正向
- `static String _getSolidConnectionKey(portConnections)` — 生成 6 位固体端口连接键 `"OOOIII"`（output_0/1/2 + input_0/1/2）
- `static String _getLiquidExportKey(portConnections)` — 左侧出水口键（input_3）
- `static String _getLiquidImportKey(portConnections)` — 右侧进水口键（output_3）
- `static String _generateBaseModifiedSvg(baseSvg, key)` — 按 6 位 key 改写 6 个固体端口的颜色（每个端口 2 个 rect：背景 `#cbc9c9` + 前景 `#e0dede`），'1'→黄 `#ffef00`、'2'→蓝 `#44aaff`、其他→默认灰
- `static String _generateLiquidExportModifiedSvg(svg, key)` — 改写 `circle73` 颜色（默认 `#ffef00`，'2'→蓝）
- `static String _generateLiquidImportModifiedSvg(svg, key)` — 改写 `path79` 颜色（默认白，'1'→黄，'2'→蓝）
- `static void _preloadBaseSvgForState(solidKey)` / `_preloadLiquidExportSvgForState(exportKey)` / `_preloadLiquidImportSvgForState(importKey)` — 异步预生成各状态 SVG 缓存
- `static void _drawSvgBody(Canvas, w, h, {opacity, portConnections, tintBlue, tintRed})` — 组合绘制：基础 3x3 单元（铺满）+ 左出水口 + 右进水口

> **注意**：本文件不含生产循环逻辑。`render` 方法接收 `activeRecipe` 和 `productionProgress` 参数但仅用于签名兼容，未在方法体内使用。生产循环由 [仿真引擎](./06-仿真引擎.md) 驱动。

---

## 7.2 `Depot Access/depot_access.dart` — 仓库存取口

定义仓库存货口/取货口的配置常量及其模块化 SVG 渲染器。

### `DepotLoaderConfig`（仓库存货口，static const）

| 字段 | 值 |
|------|----|
| `id` | `'depot_loader_3x1'` |
| `name` | `'仓库存货口'` |
| `gridWidth` / `gridHeight` | 3 / 1 |
| `color` | （具体值见源码） |
| `category` | `'depot_access'` |
| `maxInputs` / `maxOutputs` | 1 / 0 |
| `inputPorts` | 1 个固体端口 |
| `outputPorts` | 空 |

### `DepotUnloaderConfig`（仓库取货口，static const）

| 字段 | 值 |
|------|----|
| `id` | `'depot_unloader_3x1'` |
| `name` | `'仓库取货口'` |
| `gridWidth` / `gridHeight` | 3 / 1 |
| `category` | `'depot_access'` |
| `maxInputs` / `maxOutputs` | 0 / 1 |
| `inputPorts` | 空 |
| `outputPorts` | 1 个固体端口 |

### `DepotAccessRenderer`

存/取货口共用渲染器，模块化加载并绘制 SVG，Logo 始终不随设备/画布旋转。

**关键方法**：
- `static Future<void> init({VoidCallback? onReady})` — 异步加载 `Depot.svg` + 两个 Logo SVG，清理 Inkscape 标签后解析为 PictureInfo 并缓存
- `static String _cleanInkscapeSvg(String svg)` — 移除 sodipodi/inkscape 命名空间、path-effect、image 标签等 flutter_svg 不兼容元素
- `static bool get isReady` — 所有 SVG 加载完成的判定
- `static void render(Canvas, Building, gridX, gridY, cellSize, rotation, {activeRecipe, isBlocked, productionProgress, portConnections, detailLevel})` — 渲染设备主体（不含 Logo），含旋转与阻塞遮罩
- `static void renderPlaceholder(Canvas, Building, gridX, gridY, cellSize, opacity, {rotation, isBlocked, canvasRotation})` — 半透明放置预览，蓝/红着色，调用 `BuildingRenderer.drawPortArrows`
- `static void renderLogo(Canvas, x, y, w, h, buildingId, buildingRotation, canvasRotation, {opacity, tintBlue, tintRed})` — 单独绘制 Logo，用 `counterAngle = -(buildingAngle + canvasRotation)` 反向旋转抵消设备与画布旋转，保持 Logo 始终正向
- `static String _generateBaseModifiedSvg(String baseSvg, String state)` — 根据端口连接状态（'0'未连/'1'已连黄/'2'预览蓝）改写 `rect1` 的 fill 颜色
- `static String _getConnectionKey(String buildingId, Map<String,int>? portConnections)` — Loader 取 `input_0`、Unloader 取 `output_0` 作为状态键

---

## 7.3 `Logistics Units/logistics_unit_renderer.dart` — 物流单元共用渲染器

物流单元（物流桥/分流器/汇流器/物品准入口）的统一 SVG 渲染器，集中管理 id 常量与 SVG 资源加载/缓存/绘制。

### `LogisticsUnitRenderer`

**id 常量**：
- `beltBridgeId = 'belt_bridge_1x1'`
- `splitterId = 'splitter_1x1'`
- `convergerId = 'converger_1x1'`
- `itemControlPortId = 'item_control_port_1x1'`
- `logisticsUnitIds`（`Set<String>`）：上述 4 个 id 的集合

**关键方法**：
- `static bool isLogisticsUnit(String buildingId)` — 判断 id 是否属于物流单元
- `static Future<void> init({VoidCallback? onReady})` — 遍历 `_assetPaths`，加载原始 SVG → `_cleanInkscapeSvg` → `vg.loadPicture` 存入 `_pictures`；再用 `_makePreviewSvg` 生成预览版存入 `_previewPictures`
- `static void render(Canvas, Building, gridX, gridY, cellSize, rotation, {activeRecipe, isBlocked, productionProgress, portConnections, detailLevel})` — 平移到格子中心 → 按 rotation 旋转 → 绘制 SVG（或回退矩形）→ 阻塞遮罩
- `static void renderPlaceholder(Canvas, Building, gridX, gridY, cellSize, opacity, {rotation, isBlocked, canvasRotation, previewColorOverride})` — 半透明预览，用 `saveLayer + ColorFilter.mode(previewColor, BlendMode.srcATop)` 着色
- `static String _cleanInkscapeSvg(String svg)` — 9 步清理：移除 sodipodi:namedview、defs、inkscape:path-effect、image、inkscape/sodipodi 属性与命名空间、`fill:url(...)` 替换为 `#555555`、`stroke:url(...)` 替换为 `none`、移除 xlink 命名空间
- `static String _makePreviewSvg(String cleanedSvg)` — 将 `fill:#e4e4e4;fill-opacity:1` 替换为 `fill-opacity:0.2`，使预览时背景半透明

---

## 7.4 物流单元配置类

### `BeltBridgeConfig`（物流桥，1x1，四向）

| 字段 | 值 |
|------|----|
| `id` | `LogisticsUnitRenderer.beltBridgeId`（`'belt_bridge_1x1'`） |
| `name` | `'物流桥'` |
| `gridWidth` / `gridHeight` | 1 / 1 |
| `color` | `'#4F8BFF'` |
| `category` | `'logistics_units'` |
| `maxInputs` / `maxOutputs` | 4 / 4 |
| `transferRate` | 0.5 |
| `svgAssetPath` | `'assets/svg/Belt_Bridge.svg'` |
| `inputPorts` / `outputPorts` | 各 4 个，分别位于上(0.5,0)、下(0.5,1)、左(0,0.5)、右(1,0.5)，portType 均为 `'solid'` |

### `ConvergerConfig`（汇流器，1x1，3入1出）

| 字段 | 值 |
|------|----|
| `id` | `LogisticsUnitRenderer.convergerId`（`'converger_1x1'`） |
| `name` | `'汇流器'` |
| `color` | `'#49B675'` |
| `maxInputs` / `maxOutputs` | 3 / 1 |
| `transferRate` | 0.5 |
| `inputPorts` | 下(0.5,1)、左(0,0.5)、右(1,0.5) |
| `outputPorts` | 上(0.5,0) |

### `SplitterConfig`（分流器，1x1，1入3出）

| 字段 | 值 |
|------|----|
| `id` | `LogisticsUnitRenderer.splitterId`（`'splitter_1x1'`） |
| `name` | `'分流器'` |
| `color` | `'#F5A623'` |
| `maxInputs` / `maxOutputs` | 1 / 3 |
| `transferRate` | 0.5 |
| `inputPorts` | 下(0.5,1) |
| `outputPorts` | 上(0.5,0)、左(0,0.5)、右(1,0.5) |

> 与 `ConvergerConfig` 是对称设计（端口方向相反）。

### `ItemControlPortConfig`（物品准入口，1x1，1入1出）

| 字段 | 值 |
|------|----|
| `id` | `LogisticsUnitRenderer.itemControlPortId`（`'item_control_port_1x1'`） |
| `name` | `'物品准入口'` |
| `color` | `'#8D6EFA'` |
| `maxInputs` / `maxOutputs` | 1 / 1 |
| `transferRate` | **0.0**（不主动传输，仅作过滤/准入） |
| `inputPorts` | 下(0.5,1) |
| `outputPorts` | 上(0.5,0) |

---

## 7.5 跨文件关系

### 配置 → 渲染器 → 控制器的分层

```
belt_bridge.dart ──┐
converger.dart ────┤── 依赖 ──> logistics_unit_renderer.dart (id 常量 + SVG 渲染)
splitter.dart ─────┤
item_control_port.dart ─┘

transport_belt.dart (TransportBeltController)
   ├── 产生 ConveyorBelt 数据 (存入 project.conveyors)
   ├── 通过 _beltBridgeId 常量间接关联 belt_bridge.dart
   └── 数据被 transport_belt_renderer.dart (TransportBeltRenderer) 消费绘制

depot_access.dart (DepotLoaderConfig/DepotUnloaderConfig + DepotAccessRenderer)
refining_unit.dart (RefiningUnitConfig + RefiningUnitRenderer)
   └── 两者渲染器模式相似：模块化 SVG + Logo 反向旋转 + 端口状态着色
```

### 共同依赖

- `models/building.dart`：`Building`、`PortDefinition`（所有文件）
- `models/project.dart`：`ProjectState`、`ConveyorBelt`、`ConveyorItemSegment`、`PlacedBuilding`（transport_belt.dart、transport_belt_renderer.dart）
- `models/recipe.dart`：`Recipe`（depot_access.dart、refining_unit.dart 的 render 签名）
- `canvas/building_renderer.dart`：`BuildingRenderer.drawPortArrows`（depot_access.dart、refining_unit.dart 的预览）
- `flutter_svg`：`vg`、`SvgStringLoader`、`SvgAssetLoader`、`PictureInfo`（所有渲染器）

### 三个重点关注项的结论

**1. 物流桥轨道切换逻辑**
- `belt_bridge.dart` 仅是 1x1 四向端口配置，**无任何切换逻辑**。
- 真正的逻辑在 `transport_belt.dart`：`_autoCreateBridgesAtCrossings` 检测 fullPath 与现有传送带的垂直交叉（`_isPerpendicularCrossing`），自动在交叉点创建物流桥建筑；传送带**不再拆分**，保持完整路径穿过物流桥格子，物品直接通过。
- BFS 中物流桥格子的"轨道切换"体现为：`allowedDirIndices = [node.incomingDir]`——只允许沿入方向直线通过，不能在桥内转弯。

**2. 精炼炉生产循环**
- **本文件不含生产循环逻辑**。`RefiningUnitRenderer.render` 接收 `activeRecipe` 和 `productionProgress` 参数但方法体内未使用，仅作签名兼容。
- 生产循环（配方选择、原料消耗、产物生成、进度推进）由 [仿真引擎](./06-仿真引擎.md) 驱动。

**3. 物流桥通道容量**
- `PlacedBuilding.maxBridgeLaneItemCount = 1`（设为 1 以快速反压死胡同传送带）
- 物流桥通道键前缀 `'__bridge_lane__'`，通过 `bridgeItemIdForOutputDirection` / `bridgeItemCountForOutputDirection` / `canAcceptBridgeInputItem` / `acceptBridgeInputItem` / `consumeBridgeOutputItem` 等方法管理。
