import 'dart:math' as math;
import 'dart:ui';
import 'building.dart';

class PortState {
  final int index;
  final String type;
  final PortDefinition definition;
  bool connected;
  String? linkedItemId;

  PortState({
    required this.index,
    required this.type,
    required this.definition,
    this.connected = false,
    this.linkedItemId,
  });

  Offset worldPosition(double gridX, double gridY, double cellSize,
      int gridWidth, int gridHeight,
      {int rotation = 0}) {
    double rX = definition.relativeX;
    double rY = definition.relativeY;

    double localGridX = (rX == 1.0)
        ? (gridWidth - 1).toDouble()
        : (rX * gridWidth).floorToDouble();
    double localGridY = (rY == 1.0)
        ? (gridHeight - 1).toDouble()
        : (rY * gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - gridWidth / 2.0;
    double cy = ry - gridHeight / 2.0;

    double rcx, rcy;
    switch (rotation % 4) {
      case 1:
        rcx = -cy;
        rcy = cx;
        break;
      case 2:
        rcx = -cx;
        rcy = -cy;
        break;
      case 3:
        rcx = cy;
        rcy = -cx;
        break;
      case 0:
      default:
        rcx = cx;
        rcy = cy;
        break;
    }

    double wx = gridX + rcx + gridWidth / 2.0;
    double wy = gridY + rcy + gridHeight / 2.0;

    return Offset(wx * cellSize, wy * cellSize);
  }

  Offset gridPosition(double gridX, double gridY, int gridWidth, int gridHeight,
      {int rotation = 0}) {
    double rX = definition.relativeX;
    double rY = definition.relativeY;

    double localGridX = (rX == 1.0)
        ? (gridWidth - 1).toDouble()
        : (rX * gridWidth).floorToDouble();
    double localGridY = (rY == 1.0)
        ? (gridHeight - 1).toDouble()
        : (rY * gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - gridWidth / 2.0;
    double cy = ry - gridHeight / 2.0;

    double rcx, rcy;
    switch (rotation % 4) {
      case 1:
        rcx = -cy;
        rcy = cx;
        break;
      case 2:
        rcx = -cx;
        rcy = -cy;
        break;
      case 3:
        rcx = cy;
        rcy = -cx;
        break;
      case 0:
      default:
        rcx = cx;
        rcy = cy;
        break;
    }

    double wx = gridX + rcx + gridWidth / 2.0;
    double wy = gridY + rcy + gridHeight / 2.0;

    return Offset(wx.floorToDouble(), wy.floorToDouble());
  }
}

class PlacedBuilding {
  static const int maxInputItemCount = 50;
  static const int maxOutputItemCount = 50;
  /// 物流桥通道容量：传送带不再在物流桥处拆分，但以物流桥为终点/起点的
  /// 传送带仍通过通道机制中转。容量设为1确保反压快速传播。
  static const int maxBridgeLaneItemCount = 1;
  static const String _beltBridgeId = 'belt_bridge_1x1';
  static const String _bridgeLanePrefix = '__bridge_lane__';

  final String id;
  final Building building;
  double gridX;
  double gridY;
  int rotation;
  String? activeRecipeId;
  String? depotOutputItemId;
  String? inputItemId;
  int inputItemCount;
  Map<String, int> outputItems;
  List<PortState> inputPorts;
  List<PortState> outputPorts;
  bool isBlocked;
  double productionProgress;
  bool isPaused;

  PlacedBuilding({
    required this.id,
    required this.building,
    required this.gridX,
    required this.gridY,
    this.rotation = 0,
    this.activeRecipeId,
    this.depotOutputItemId,
    this.inputItemId,
    this.inputItemCount = 0,
    Map<String, int>? outputItems,
    this.isBlocked = false,
    this.productionProgress = 0.0,
    this.isPaused = false,
  })  : outputItems = outputItems ?? {},
        inputPorts = List.generate(
          building.ports.inputs.length,
          (i) => PortState(
            index: i,
            type: 'input',
            definition: building.ports.inputs[i],
          ),
        ),
        outputPorts = List.generate(
          building.ports.outputs.length,
          (i) => PortState(
            index: i,
            type: 'output',
            definition: building.ports.outputs[i],
          ),
        );

  int get totalOutputCount =>
      outputItems.values.fold<int>(0, (sum, count) => sum + count);

  bool canAcceptOutputItem(String itemId) {
    return totalOutputCount < maxOutputItemCount;
  }

  void addOutputItem(String itemId, int amount) {
    outputItems[itemId] = (outputItems[itemId] ?? 0) + amount;
  }

  bool hasOutputItem(String itemId, [int amount = 1]) {
    return (outputItems[itemId] ?? 0) >= amount;
  }

  bool consumeOutputItem(String itemId, int amount) {
    if (!hasOutputItem(itemId, amount)) return false;
    outputItems[itemId] = outputItems[itemId]! - amount;
    if (outputItems[itemId]! <= 0) {
      outputItems.remove(itemId);
    }
    return true;
  }

  bool canAcceptInputItem(String itemId) {
    if (itemId.isEmpty || inputItemCount >= maxInputItemCount) return false;
    return inputItemCount == 0 || inputItemId == null || inputItemId == itemId;
  }

  bool acceptInputItem(String itemId) {
    if (!canAcceptInputItem(itemId)) return false;
    inputItemId = itemId;
    inputItemCount++;
    return true;
  }

  bool hasInputItems(String itemId, int amount) {
    return inputItemId == itemId && inputItemCount >= amount;
  }

  bool consumeInputItems(String itemId, int amount) {
    if (!hasInputItems(itemId, amount)) return false;
    inputItemCount -= amount;
    if (inputItemCount <= 0) {
      inputItemCount = 0;
      inputItemId = null;
    }
    return true;
  }

  bool get isBeltBridge => building.id == _beltBridgeId;

  String _normalizeBridgeDirection(String direction) {
    switch (direction) {
      case 'up':
      case 'down':
      case 'left':
      case 'right':
        return direction;
      default:
        return 'up';
    }
  }

  String _bridgeLanePrefixFor(String outputDirection) =>
      '$_bridgeLanePrefix${_normalizeBridgeDirection(outputDirection)}__';

  String _bridgeLaneKey(String outputDirection, String itemId) =>
      '${_bridgeLanePrefixFor(outputDirection)}$itemId';

  String? bridgeItemIdForOutputDirection(String outputDirection) {
    if (!isBeltBridge) return null;
    final prefix = _bridgeLanePrefixFor(outputDirection);
    for (final entry in outputItems.entries) {
      if (entry.value <= 0 || !entry.key.startsWith(prefix)) continue;
      return entry.key.substring(prefix.length);
    }
    return null;
  }

  int bridgeItemCountForOutputDirection(String outputDirection) {
    if (!isBeltBridge) return 0;
    final prefix = _bridgeLanePrefixFor(outputDirection);
    var count = 0;
    for (final entry in outputItems.entries) {
      if (entry.key.startsWith(prefix)) {
        count += entry.value;
      }
    }
    return count;
  }

  bool canAcceptBridgeInputItem(String itemId, String outputDirection) {
    if (!isBeltBridge || itemId.isEmpty) return false;
    if (bridgeItemCountForOutputDirection(outputDirection) >=
        maxBridgeLaneItemCount) {
      return false;
    }
    final currentItemId = bridgeItemIdForOutputDirection(outputDirection);
    return currentItemId == null || currentItemId == itemId;
  }

  bool acceptBridgeInputItem(String itemId, String outputDirection) {
    if (!canAcceptBridgeInputItem(itemId, outputDirection)) return false;
    final key = _bridgeLaneKey(outputDirection, itemId);
    outputItems[key] = (outputItems[key] ?? 0) + 1;
    return true;
  }

  bool consumeBridgeOutputItem(String itemId, String outputDirection) {
    if (!isBeltBridge || itemId.isEmpty) return false;
    final key = _bridgeLaneKey(outputDirection, itemId);
    final current = outputItems[key] ?? 0;
    if (current <= 0) return false;
    if (current == 1) {
      outputItems.remove(key);
    } else {
      outputItems[key] = current - 1;
    }
    return true;
  }

  /// 旋转后的有效宽度（90°/270° 时宽高互换）
  int get effectiveWidth =>
      (rotation % 2 == 1) ? building.gridHeight : building.gridWidth;

  /// 旋转后的有效高度（90°/270° 时宽高互换）
  int get effectiveHeight =>
      (rotation % 2 == 1) ? building.gridWidth : building.gridHeight;

  /// 旋转后的有效网格 X（调整原点使旋转后占地居中于同一中心点）
  double get effectiveGridX =>
      gridX + (building.gridWidth - effectiveWidth) / 2.0;

  /// 旋转后的有效网格 Y（调整原点使旋转后占地居中于同一中心点）
  double get effectiveGridY =>
      gridY + (building.gridHeight - effectiveHeight) / 2.0;

  Rect getBounds(double cellSize) {
    return Rect.fromLTWH(
      effectiveGridX * cellSize,
      effectiveGridY * cellSize,
      effectiveWidth * cellSize,
      effectiveHeight * cellSize,
    );
  }

  bool overlaps(Rect other, double cellSize) {
    return getBounds(cellSize).overlaps(other);
  }

  Map<String, bool> conveyorPortConnections(
    Iterable<ConveyorBelt> conveyors, {
    double cellSize = 48.0,
    double threshold = 30.0,
  }) {
    final connections = <String, bool>{};
    for (final belt in conveyors) {
      for (final port in inputPorts) {
        if (_isPortConnectedToBelt(port, belt, cellSize, threshold)) {
          connections['input_${port.index}'] = true;
        }
      }
      for (final port in outputPorts) {
        if (_isPortConnectedToBelt(port, belt, cellSize, threshold)) {
          connections['output_${port.index}'] = true;
        }
      }
    }
    return connections;
  }

  bool _isPortConnectedToBelt(
    PortState port,
    ConveyorBelt belt,
    double cellSize,
    double threshold,
  ) {
    if (belt.path.length < 2) return false;

    final portWorld = port.worldPosition(
      gridX,
      gridY,
      cellSize,
      building.gridWidth,
      building.gridHeight,
      rotation: rotation,
    );
    final beltEndpoint = port.type == 'input' ? belt.end : belt.start;
    return (beltEndpoint - portWorld).distance < threshold;
  }
}

class ConveyorItemSegment {
  String itemId;
  int fillCount;
  int drainCount;
  double? freezeProgress;

  ConveyorItemSegment({
    required this.itemId,
    required this.fillCount,
    this.drainCount = 0,
    this.freezeProgress,
  });

  bool get hasItems => itemId.isNotEmpty && fillCount > drainCount;

  ConveyorItemSegment copyWith({
    String? itemId,
    int? fillCount,
    int? drainCount,
    double? freezeProgress,
  }) {
    return ConveyorItemSegment(
      itemId: itemId ?? this.itemId,
      fillCount: fillCount ?? this.fillCount,
      drainCount: drainCount ?? this.drainCount,
      freezeProgress: freezeProgress ?? this.freezeProgress,
    );
  }

  ConveyorItemSegment shifted(
    int offset, {
    bool clearFreezeProgress = false,
  }) {
    return ConveyorItemSegment(
      itemId: itemId,
      fillCount: fillCount + offset,
      drainCount: drainCount + offset,
      freezeProgress: clearFreezeProgress ? null : freezeProgress,
    );
  }

  ConveyorItemSegment? clipped(
    int start,
    int end, {
    bool clearFreezeProgress = false,
  }) {
    final newDrain = drainCount < start ? start : drainCount;
    final newFill = fillCount > end ? end : fillCount;
    if (newFill <= newDrain) return null;
    final newLength = end - start;
    return ConveyorItemSegment(
      itemId: itemId,
      fillCount: newFill - start,
      drainCount: newDrain - start,
      freezeProgress:
          !clearFreezeProgress && newLength > 0 ? freezeProgress : null,
    );
  }
}

class ConveyorBelt {
  final String id;
  final List<Offset> path;
  String itemId;
  String lastItemId;
  List<ConveyorItemSegment> itemSegments;
  List<Offset> particles;
  double flowProgress;
  int itemFillCount;
  int itemDrainCount;
  bool isBlocked;
  final String? forcedDirection;
  final String? incomingDirection;
  double phaseOffset;

  // 残留物品（源断开后的旧物品，正在排空中）
  int lastItemFillCount;
  int lastItemDrainCount;

  // 断头传送带满载时冻结的 arrowProgress 值，用于平滑过渡
  double? deadEndFreezeProgress;
  double? lastItemFreezeProgress;

  ConveyorBelt({
    required this.id,
    required this.path,
    required this.itemId,
    String? lastItemId,
    List<ConveyorItemSegment>? itemSegments,
    List<Offset>? particles,
    this.flowProgress = 0.0,
    this.itemFillCount = 0,
    this.itemDrainCount = 0,
    this.isBlocked = false,
    this.forcedDirection,
    this.incomingDirection,
    this.phaseOffset = 0.0,
    this.lastItemFillCount = 0,
    this.lastItemDrainCount = 0,
    this.deadEndFreezeProgress,
    this.lastItemFreezeProgress,
  })  : particles = particles ?? [],
        itemSegments = List<ConveyorItemSegment>.from(itemSegments ?? const []),
        lastItemId = lastItemId ?? itemId {
    if (this.itemSegments.isNotEmpty) {
      syncLegacyFromSegments();
    }
  }

  static const double _cellSize = 48.0;

  Offset get start => path.isNotEmpty
      ? Offset(path.first.dx * _cellSize + _cellSize / 2,
          path.first.dy * _cellSize + _cellSize / 2)
      : Offset.zero;

  Offset get end => path.isNotEmpty
      ? Offset(path.last.dx * _cellSize + _cellSize / 2,
          path.last.dy * _cellSize + _cellSize / 2)
      : Offset.zero;

  double get length => path.length > 1 ? (path.length - 1) * _cellSize : 0.0;

  double animationProgress(double globalProgress) {
    final progress = (globalProgress - phaseOffset) % 1.0;
    return progress < 0 ? progress + 1.0 : progress;
  }

  bool get hasStoppedLastItems {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isNotEmpty) {
      final downstream = itemSegments.last;
      return path.isNotEmpty &&
          downstream.fillCount >= path.length &&
          downstream.fillCount > downstream.drainCount;
    }
    return path.isNotEmpty &&
        lastItemFillCount >= path.length &&
        lastItemFillCount > lastItemDrainCount;
  }

  bool get hasLastItems {
    ensureItemSegmentsFromLegacy();
    return itemSegments.length > 1 || lastItemFillCount > lastItemDrainCount;
  }

  int get stoppedLastItemStartIndex => hasStoppedLastItems
      ? (itemSegments.isNotEmpty
          ? itemSegments.last.drainCount.clamp(0, path.length).toInt()
          : lastItemDrainCount.clamp(0, path.length).toInt())
      : path.length;

  int get currentItemFillLimit {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.length > 1) {
      return itemSegments[1].drainCount.clamp(0, path.length).toInt();
    }
    return hasLastItems
        ? lastItemDrainCount.clamp(0, path.length).toInt()
        : path.length;
  }

  void ensureItemSegmentsFromLegacy() {
    if (itemSegments.isNotEmpty) return;
    if (itemId.isNotEmpty && itemFillCount > itemDrainCount) {
      itemSegments.add(ConveyorItemSegment(
        itemId: itemId,
        fillCount: itemFillCount,
        drainCount: itemDrainCount,
        freezeProgress: deadEndFreezeProgress,
      ));
    }
    if (lastItemId.isNotEmpty && lastItemFillCount > lastItemDrainCount) {
      itemSegments.add(ConveyorItemSegment(
        itemId: lastItemId,
        fillCount: lastItemFillCount,
        drainCount: lastItemDrainCount,
        freezeProgress: lastItemFreezeProgress,
      ));
    }
    _sortItemSegments();
  }

  List<ConveyorItemSegment> shiftedItemSegments(
    int offset, {
    bool clearFreezeProgress = false,
  }) {
    ensureItemSegmentsFromLegacy();
    return itemSegments
        .map((segment) =>
            segment.shifted(offset, clearFreezeProgress: clearFreezeProgress))
        .where((segment) => segment.hasItems)
        .toList()
      ..sort((a, b) => a.drainCount.compareTo(b.drainCount));
  }

  List<ConveyorItemSegment> clippedItemSegments(
    int start,
    int end, {
    bool clearFreezeProgress = false,
  }) {
    ensureItemSegmentsFromLegacy();
    return itemSegments
        .map((segment) => segment.clipped(
              start,
              end,
              clearFreezeProgress: clearFreezeProgress,
            ))
        .whereType<ConveyorItemSegment>()
        .where((segment) => segment.hasItems)
        .toList()
      ..sort((a, b) => a.drainCount.compareTo(b.drainCount));
  }

  void syncLegacyFromSegments() {
    itemSegments.removeWhere((segment) => !segment.hasItems);
    _sortItemSegments();
    _mergeAdjacentSegments();
    if (itemSegments.isEmpty) {
      itemId = '';
      itemFillCount = 0;
      itemDrainCount = 0;
      deadEndFreezeProgress = null;
      lastItemId = '';
      lastItemFillCount = 0;
      lastItemDrainCount = 0;
      lastItemFreezeProgress = null;
      return;
    }

    final upstream = itemSegments.first;
    itemId = upstream.itemId;
    itemFillCount = upstream.fillCount;
    itemDrainCount = upstream.drainCount;
    deadEndFreezeProgress = upstream.freezeProgress;

    if (itemSegments.length > 1) {
      final downstream = itemSegments.last;
      lastItemId = downstream.itemId;
      lastItemFillCount = downstream.fillCount;
      lastItemDrainCount = downstream.drainCount;
      lastItemFreezeProgress = downstream.freezeProgress;
    } else {
      lastItemId = itemId;
      lastItemFillCount = 0;
      lastItemDrainCount = 0;
      lastItemFreezeProgress = null;
    }
  }

  bool pushSourceItem(String sourceItemId, {int? terminalLimit}) {
    if (sourceItemId.isEmpty || path.isEmpty) return false;
    ensureItemSegmentsFromLegacy();
    _sortItemSegments();
    final endLimit =
        terminalLimit?.clamp(0, path.length).toInt() ?? path.length;
    if (endLimit <= 0) return false;

    if (itemSegments.isEmpty) {
      itemSegments.add(ConveyorItemSegment(
        itemId: sourceItemId,
        fillCount: 1.clamp(0, endLimit).toInt(),
      ));
      syncLegacyFromSegments();
      return true;
    }

    final first = itemSegments.first;
    if (first.drainCount == 0 && first.itemId == sourceItemId) {
      final limit = itemSegments.length > 1
          ? itemSegments[1].drainCount.clamp(0, path.length).toInt()
          : endLimit;
      if (first.fillCount >= limit) return false;
      first.fillCount++;
      first.freezeProgress = null;
      syncLegacyFromSegments();
      return true;
    }

    if (first.drainCount <= 0) return false;
    itemSegments.insert(
      0,
      ConveyorItemSegment(
        itemId: sourceItemId,
        fillCount: 1.clamp(0, math.min(first.drainCount, endLimit)).toInt(),
      ),
    );
    syncLegacyFromSegments();
    return true;
  }

  String? outputReadyItemId() {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isEmpty || path.isEmpty) return null;
    _sortItemSegments();
    final downstream = itemSegments.last;
    if (!downstream.hasItems || downstream.fillCount < path.length) {
      return null;
    }
    return downstream.itemId;
  }

  String? downstreamItemId() {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isEmpty) return null;
    _sortItemSegments();
    final downstream = itemSegments.last;
    return downstream.hasItems ? downstream.itemId : null;
  }

  bool removeOutputReadyItem() {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isEmpty || path.isEmpty) return false;
    _sortItemSegments();
    final downstream = itemSegments.last;
    if (!downstream.hasItems || downstream.fillCount < path.length) {
      return false;
    }
    downstream.fillCount--;
    if (downstream.fillCount < path.length) {
      downstream.freezeProgress = null;
    }
    syncLegacyFromSegments();
    return true;
  }

  bool advanceItemSegments({
    required bool isDeadEnd,
    String? activeSourceItemId,
    int? terminalLimit,
  }) {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isEmpty) {
      syncLegacyFromSegments();
      return false;
    }

    bool changed = false;
    _sortItemSegments();
    final endLimit =
        terminalLimit?.clamp(0, path.length).toInt() ?? path.length;

    if (isDeadEnd) {
      for (int i = itemSegments.length - 1; i >= 0; i--) {
        final segment = itemSegments[i];
        final limit = i + 1 < itemSegments.length
            ? itemSegments[i + 1].drainCount.clamp(0, path.length).toInt()
            : endLimit;
        final isFedBySource = i == 0 &&
            segment.drainCount == 0 &&
            activeSourceItemId != null &&
            segment.itemId == activeSourceItemId;
        if (isFedBySource) continue;
        if (segment.fillCount < limit) {
          segment.fillCount++;
          segment.drainCount++;
          segment.freezeProgress = null;
          changed = true;
        }
      }
    } else {
      for (final segment in itemSegments) {
        final isFedBySource = segment.drainCount == 0 &&
            activeSourceItemId != null &&
            segment.itemId == activeSourceItemId;
        if (isFedBySource) continue;
        if (segment.drainCount < segment.fillCount) {
          segment.drainCount++;
          segment.freezeProgress = null;
          changed = true;
        }
      }
      itemSegments.removeWhere((segment) => !segment.hasItems);
    }

    syncLegacyFromSegments();
    return changed;
  }

  /// 冻结死胡同传送带中已到达各自极限的物品段。
  /// 仅在 freezeProgress 为 null 时设置为 -1.0（等待状态），
  /// 让渲染器在 arrowProgress >= 0.5 时平滑推进到 0.5，
  /// 避免物品从入口直接跳到格子中央。
  /// 不覆盖已设置的 freezeProgress（0.5 或 -1.0），防止帧间振荡。
  void freezeDeadEndSegments() {
    ensureItemSegmentsFromLegacy();
    if (itemSegments.isEmpty) {
      syncLegacyFromSegments();
      return;
    }
    _sortItemSegments();
    final endLimit = path.length;
    for (int i = 0; i < itemSegments.length; i++) {
      final segment = itemSegments[i];
      if (!segment.hasItems) continue;
      final limit = i + 1 < itemSegments.length
          ? itemSegments[i + 1].drainCount.clamp(0, endLimit).toInt()
          : endLimit;
      if (segment.fillCount >= limit && segment.freezeProgress == null) {
        segment.freezeProgress = -1.0;
      }
    }
    syncLegacyFromSegments();
  }

  void _sortItemSegments() {
    itemSegments.sort((a, b) {
      final byDrain = a.drainCount.compareTo(b.drainCount);
      if (byDrain != 0) return byDrain;
      return a.fillCount.compareTo(b.fillCount);
    });
  }

  void _mergeAdjacentSegments() {
    if (itemSegments.length < 2) return;
    final merged = <ConveyorItemSegment>[];
    for (final segment in itemSegments) {
      if (!segment.hasItems) continue;
      if (merged.isNotEmpty) {
        final prev = merged.last;
        if (prev.itemId == segment.itemId &&
            prev.fillCount >= segment.drainCount) {
          if (segment.fillCount > prev.fillCount) {
            prev.fillCount = segment.fillCount;
            prev.freezeProgress = segment.freezeProgress;
          }
          if (segment.drainCount < prev.drainCount) {
            prev.drainCount = segment.drainCount;
          }
          continue;
        }
      }
      merged.add(segment);
    }
    itemSegments = merged;
  }
}

class ProjectState {
  final List<PlacedBuilding> buildings;
  final List<ConveyorBelt> conveyors;
  double offsetX;
  double offsetY;
  double scale;

  ProjectState({
    List<PlacedBuilding>? buildings,
    List<ConveyorBelt>? conveyors,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
  })  : buildings = buildings ?? [],
        conveyors = conveyors ?? [];
}
