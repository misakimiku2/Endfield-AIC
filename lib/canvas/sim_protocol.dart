import 'dart:ui';

// ============================================================
// 主 Isolate → 计算 Isolate 的同步消息
// ============================================================

/// 同步完整状态到计算 Isolate
class SimSyncState {
  final List<SimBuildingData> buildings;
  final List<SimConveyorData> conveyors;
  final List<SimRecipeData> recipes;
  final double speedMultiplier;

  const SimSyncState({
    required this.buildings,
    required this.conveyors,
    required this.recipes,
    required this.speedMultiplier,
  });

  Map<String, dynamic> toJson() => {
        'buildings': buildings.map((e) => e.toJson()).toList(),
        'conveyors': conveyors.map((e) => e.toJson()).toList(),
        'recipes': recipes.map((e) => e.toJson()).toList(),
        'speedMultiplier': speedMultiplier,
      };

  factory SimSyncState.fromJson(Map<String, dynamic> json) => SimSyncState(
        buildings: (json['buildings'] as List)
            .map((e) => SimBuildingData.fromJson(e as Map<String, dynamic>))
            .toList(),
        conveyors: (json['conveyors'] as List)
            .map((e) => SimConveyorData.fromJson(e as Map<String, dynamic>))
            .toList(),
        recipes: (json['recipes'] as List)
            .map((e) => SimRecipeData.fromJson(e as Map<String, dynamic>))
            .toList(),
        speedMultiplier: (json['speedMultiplier'] as num).toDouble(),
      );
}

/// 设备的可序列化数据
class SimBuildingData {
  final String id;
  final String buildingId;
  final double gridX;
  final double gridY;
  final int rotation;
  final String? activeRecipeId;
  final int gridWidth;
  final int gridHeight;
  final List<SimPortData> inputPorts;
  final List<SimPortData> outputPorts;

  const SimBuildingData({
    required this.id,
    required this.buildingId,
    required this.gridX,
    required this.gridY,
    required this.rotation,
    this.activeRecipeId,
    required this.gridWidth,
    required this.gridHeight,
    required this.inputPorts,
    required this.outputPorts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'buildingId': buildingId,
        'gridX': gridX,
        'gridY': gridY,
        'rotation': rotation,
        'activeRecipeId': activeRecipeId,
        'gridWidth': gridWidth,
        'gridHeight': gridHeight,
        'inputPorts': inputPorts.map((e) => e.toJson()).toList(),
        'outputPorts': outputPorts.map((e) => e.toJson()).toList(),
      };

  factory SimBuildingData.fromJson(Map<String, dynamic> json) => SimBuildingData(
        id: json['id'] as String,
        buildingId: json['buildingId'] as String,
        gridX: (json['gridX'] as num).toDouble(),
        gridY: (json['gridY'] as num).toDouble(),
        rotation: json['rotation'] as int,
        activeRecipeId: json['activeRecipeId'] as String?,
        gridWidth: json['gridWidth'] as int,
        gridHeight: json['gridHeight'] as int,
        inputPorts: (json['inputPorts'] as List)
            .map((e) => SimPortData.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputPorts: (json['outputPorts'] as List)
            .map((e) => SimPortData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 端口的可序列化数据
class SimPortData {
  final int index;
  final String type;
  final double relativeX;
  final double relativeY;
  final String direction;
  final String portType;

  const SimPortData({
    required this.index,
    required this.type,
    required this.relativeX,
    required this.relativeY,
    required this.direction,
    this.portType = 'solid',
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'type': type,
        'relativeX': relativeX,
        'relativeY': relativeY,
        'direction': direction,
        'portType': portType,
      };

  factory SimPortData.fromJson(Map<String, dynamic> json) => SimPortData(
        index: json['index'] as int,
        type: json['type'] as String,
        relativeX: (json['relativeX'] as num).toDouble(),
        relativeY: (json['relativeY'] as num).toDouble(),
        direction: json['direction'] as String,
        portType: (json['portType'] as String?) ?? 'solid',
      );
}

/// 传送带的可序列化数据
class SimConveyorData {
  final String id;
  final List<Offset> path;
  final String itemId;
  final double flowProgress;
  final bool isBlocked;
  final String? forcedDirection;
  final String? incomingDirection;

  const SimConveyorData({
    required this.id,
    required this.path,
    required this.itemId,
    this.flowProgress = 0.0,
    this.isBlocked = false,
    this.forcedDirection,
    this.incomingDirection,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'itemId': itemId,
        'flowProgress': flowProgress,
        'isBlocked': isBlocked,
        'forcedDirection': forcedDirection,
        'incomingDirection': incomingDirection,
      };

  factory SimConveyorData.fromJson(Map<String, dynamic> json) => SimConveyorData(
        id: json['id'] as String,
        path: (json['path'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
        itemId: json['itemId'] as String? ?? '',
        flowProgress: (json['flowProgress'] as num?)?.toDouble() ?? 0.0,
        isBlocked: json['isBlocked'] as bool? ?? false,
        forcedDirection: json['forcedDirection'] as String?,
        incomingDirection: json['incomingDirection'] as String?,
      );
}

/// 配方的可序列化数据
class SimRecipeData {
  final String id;
  final double processTimeSeconds;
  final List<SimRecipeIOData> inputs;
  final List<SimRecipeIOData> outputs;

  const SimRecipeData({
    required this.id,
    required this.processTimeSeconds,
    required this.inputs,
    required this.outputs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'processTimeSeconds': processTimeSeconds,
        'inputs': inputs.map((e) => e.toJson()).toList(),
        'outputs': outputs.map((e) => e.toJson()).toList(),
      };

  factory SimRecipeData.fromJson(Map<String, dynamic> json) => SimRecipeData(
        id: json['id'] as String,
        processTimeSeconds: (json['processTimeSeconds'] as num).toDouble(),
        inputs: (json['inputs'] as List)
            .map((e) => SimRecipeIOData.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputs: (json['outputs'] as List)
            .map((e) => SimRecipeIOData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 配方输入输出的可序列化数据
class SimRecipeIOData {
  final String itemId;
  final int amount;

  const SimRecipeIOData({required this.itemId, required this.amount});

  Map<String, dynamic> toJson() => {'itemId': itemId, 'amount': amount};

  factory SimRecipeIOData.fromJson(Map<String, dynamic> json) => SimRecipeIOData(
        itemId: json['itemId'] as String,
        amount: json['amount'] as int,
      );
}

// ============================================================
// 计算 Isolate → 主 Isolate 的 tick 结果
// ============================================================

/// 一次 tick 的计算结果（轻量，只含变化的字段）
class SimTickResult {
  final List<SimBuildingResult> buildings;
  final List<SimConveyorResult> conveyors;

  const SimTickResult({required this.buildings, required this.conveyors});

  Map<String, dynamic> toJson() => {
        'buildings': buildings.map((e) => e.toJson()).toList(),
        'conveyors': conveyors.map((e) => e.toJson()).toList(),
      };

  factory SimTickResult.fromJson(Map<String, dynamic> json) => SimTickResult(
        buildings: (json['buildings'] as List)
            .map((e) => SimBuildingResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        conveyors: (json['conveyors'] as List)
            .map((e) => SimConveyorResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 设备 tick 结果
class SimBuildingResult {
  final String id;
  final bool isBlocked;
  final double productionProgress;

  const SimBuildingResult({
    required this.id,
    required this.isBlocked,
    required this.productionProgress,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'isBlocked': isBlocked,
        'productionProgress': productionProgress,
      };

  factory SimBuildingResult.fromJson(Map<String, dynamic> json) => SimBuildingResult(
        id: json['id'] as String,
        isBlocked: json['isBlocked'] as bool,
        productionProgress: (json['productionProgress'] as num).toDouble(),
      );
}

/// 传送带 tick 结果
class SimConveyorResult {
  final String id;
  final String itemId;
  final double flowProgress;
  final bool isBlocked;

  const SimConveyorResult({
    required this.id,
    required this.itemId,
    required this.flowProgress,
    required this.isBlocked,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'flowProgress': flowProgress,
        'isBlocked': isBlocked,
      };

  factory SimConveyorResult.fromJson(Map<String, dynamic> json) => SimConveyorResult(
        id: json['id'] as String,
        itemId: json['itemId'] as String? ?? '',
        flowProgress: (json['flowProgress'] as num?)?.toDouble() ?? 0.0,
        isBlocked: json['isBlocked'] as bool? ?? false,
      );
}

// ============================================================
// 控制消息
// ============================================================

/// 主 Isolate 发送给计算 Isolate 的控制消息
class SimControlMessage {
  final String type; // 'sync', 'start', 'stop', 'setSpeed'
  final Map<String, dynamic>? data;

  const SimControlMessage({required this.type, this.data});

  Map<String, dynamic> toJson() => {'type': type, 'data': data};

  factory SimControlMessage.fromJson(Map<String, dynamic> json) => SimControlMessage(
        type: json['type'] as String,
        data: json['data'] as Map<String, dynamic>?,
      );
}
