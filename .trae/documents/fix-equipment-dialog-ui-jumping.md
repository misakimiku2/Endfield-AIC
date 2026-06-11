# 修复设备弹窗输入格图片消失、配方区域UI跳动与全部收取按钮

## 问题概述

设备弹窗存在三个UI问题：

1. **输入/输出格图片消失**：当生产消耗掉最后一个输入物品时，`inputItemCount` 变为 0，导致物品图片消失（因为代码仅在 count > 0 时才显示图片）。
2. **配方区域UI跳动**：`isProducing` 的判断条件为 `_activeRecipe != null && productionProgress > 0`，当生产完成时 `productionProgress` 瞬间重置为 0，导致 `isProducing` 在 true/false 之间快速切换，配方卡片内容在两种布局间来回跳动。
3. **全部收取按钮闪烁**：按钮仅在 `isProducing || hasCollectableOutput` 时显示，随 `isProducing` 切换而出现/消失，造成UI跳动。

## 当前状态分析

### 问题1：输入/输出格图片消失

文件：[building\_detail\_dialog.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/widgets/building_detail_dialog.dart#L1660-L1668)

```dart
final dataItem = widget.isInput
    ? (inventoryItemId != null && inventoryItemId.isNotEmpty && inventoryCount > 0
        ? widget.dataLoader.getItem(inventoryItemId) : null)
    : (outputItemId != null && outputCount > 0
        ? widget.dataLoader.getItem(outputItemId) : null);
```

* 输入侧：仅当 `inventoryCount > 0` 时才获取 `dataItem`

* 输出侧：仅当 `outputCount > 0` 时才获取 `dataItem`

* `dataItem` 为 null 时，网格只显示灰色底板，不显示物品图片（第1715行）

### 问题2：配方区域UI跳动

文件：[building\_detail\_dialog.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/widgets/building_detail_dialog.dart#L957-L958)

```dart
final isProducing = _activeRecipe != null && widget.placedBuilding.productionProgress > 0;
```

当生产完成时，`simulation_engine.dart` 中 `productionProgress` 从 1.0 重置为 0.0（第390行），此时 `isProducing` 变为 false。但下一 tick 又会重新开始生产，`productionProgress` 重新 > 0，`isProducing` 又变为 true。这导致：

* 配方卡片内容在 Column（生产中：物品图标+运行指示器）和 Row（空闲：图标+文字）之间切换（第1014-1103行）

* `_InformationBackground` 的 `hideNo` 属性来回切换（第1001行）

* "全部收取"按钮出现/消失（第1118行）

## 修改方案

### 修改1：输入/输出格在 count=0 时仍显示物品图片

**文件**：[building\_detail\_dialog.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/widgets/building_detail_dialog.dart#L1660-L1668)

**修改逻辑**：将 `dataItem` 的判断条件从"有物品且有数量"改为"有物品ID就显示"，不再依赖 count > 0：

```dart
// 输入侧：只要有 inventoryItemId 就显示图片，不管数量是否为0
final dataItem = widget.isInput
    ? (inventoryItemId != null && inventoryItemId.isNotEmpty
        ? widget.dataLoader.getItem(inventoryItemId) : null)
    : (outputItemId != null
        ? widget.dataLoader.getItem(outputItemId) : null);
```

同时，当 count 为 0 时，物品图片应该降低透明度以表示"空"状态，避免与有物品时视觉上无区别。在第1715行的图片渲染处添加 opacity：

```dart
if (dataItem != null && dataItem.imageAssetPath.isNotEmpty)
  Center(
    child: Opacity(
      opacity: totalAmount > 0 ? 1.0 : 0.3,
      child: Image.asset(
        dataItem.imageAssetPath,
        ...
      ),
    ),
  )
```

### 修改2：配方区域基于 activeRecipeId 而非 productionProgress 判断状态

**文件**：[building\_detail\_dialog.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/widgets/building_detail_dialog.dart#L957-L958)

**修改逻辑**：将 `isProducing` 改为基于是否有激活配方判断，而非生产进度：

```dart
final isProducing = _activeRecipe != null;
```

这样，只要设备有激活的配方（`activeRecipeId != null`），配方区域就始终显示"生产中"的布局，不会因为 `productionProgress` 瞬间为 0 而切换到空闲布局。

**影响范围确认**：

* 第965行 `Visibility(visible: isProducing, ...)` — 标题"当前自动生产中的配方"：有配方时始终显示，合理

* 第1001行 `hideNo: isProducing` — `_InformationBackground`：有配方时隐藏 NO 标签，合理

* 第1014行 `isProducing ? Column(...) : Row(...)` — 配方卡片内容：有配方时显示物品图标+运行指示器，合理

* 第1118行 `if (isProducing || hasCollectableOutput)` — "全部收取"按钮：有配方或有可收取产出时显示，需改为始终显示（见修改3）

### 修改3：全部收取按钮始终显示，无产出时灰色不可按

**文件**：[building\_detail\_dialog.dart](file:///c:/Users/Misaki/Desktop/git/Endfield/lib/widgets/building_detail_dialog.dart#L1118-L1132)

**当前代码**：按钮通过 `if (isProducing || hasCollectableOutput)` 条件渲染，不满足时完全不存在于 widget 树中。

**修改逻辑**：

1. 移除 `if` 条件，按钮始终渲染在 `Positioned` 中
2. 给 `_CollectAllButton` 添加 `enabled` 参数（bool，默认 true）
3. 当 `!hasCollectableOutput` 时 `enabled = false`：

   * 按钮背景色变为 `#373737`（灰色）

   * 文字颜色相应变灰

   * `onTap` 不执行（传 null 或空回调）

   * 鼠标悬停不显示点击光标

   * 不播放 hover 缩放动画

**具体改动**：

a) 第1118行，移除 `if` 条件：

```dart
// 之前：if (isProducing || hasCollectableOutput)
Positioned(
  left: 424,
  top: (76.8 - 87.59967 * 0.78) / 2,
  child: _CollectAllButton(
    width: 300,
    height: 68.32774,
    enabled: hasCollectableOutput,  // 新增参数
    onTap: () {
      setState(() {
        widget.placedBuilding.outputItems.clear();
      });
      widget.onInventoryChanged?.call();
    },
  ),
),
```

b) `_CollectAllButton` 类添加 `enabled` 参数：

```dart
class _CollectAllButton extends StatefulWidget {
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool enabled;

  const _CollectAllButton({
    required this.width,
    required this.height,
    required this.onTap,
    this.enabled = true,
  });
  ...
}
```

c) `_CollectAllButtonState.build()` 中根据 `enabled` 状态调整：

* `enabled` 为 false 时：背景 SVG 用 `ColorFiltered` 或 `Opacity` 变为灰色(#373737)，文字颜色变灰，cursor 为 default，不响应 onTap，不播放 hover 动画

## 验证步骤

1. 启动应用，在仓库取货口设置源矿，用传送带连接到精炼炉
2. 观察精炼炉弹窗：

   * 输入格在源矿被消耗后应仍显示源矿图片（半透明），而非消失

   * 输出格在晶体外壳产出前应显示晶体外壳图片（半透明）

   * 配方区域应始终显示"当前自动生产中的配方"状态，不会跳动

   * 全部收取按钮始终显示，无可收取产出时为灰色(#373737)不可按
3. 运行 `flutter test` 确保无回归

