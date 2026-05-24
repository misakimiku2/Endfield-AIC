import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'sim_protocol.dart';

/// 计算 Isolate 的入口函数
/// 必须是顶层函数或静态方法，才能被 Isolate.spawn 调用
void simWorkerEntry(SendPort mainSendPort) {
  final worker = _SimWorker(mainSendPort);
  worker._init();
}

class _SimWorker {
  final SendPort _mainSendPort;
  late ReceivePort _receivePort;
  Timer? _tickTimer;

  // 计算 Isolate 持有的状态副本
  List<SimBuildingData> _buildings = [];
  List<SimConveyorData> _conveyors = [];
  List<SimRecipeData> _recipes = [];
  double _speedMultiplier = 1.0;
  bool _isRunning = false;

  static const double _tickRate = 20.0;
  static const double _cellSize = 48.0;
  static const double _portConnectionThreshold = 30.0;

  _SimWorker(this._mainSendPort);

  void _init() {
    _receivePort = ReceivePort();
    // 发送 ReceivePort 给主 Isolate，建立双向通信
    _mainSendPort.send(_receivePort.sendPort);
    _receivePort.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'] as String;
      switch (type) {
        case 'sync':
          _onSync(message['data'] as Map<String, dynamic>);
          break;
        case 'start':
          _onStart();
          break;
        case 'stop':
          _onStop();
          break;
        case 'setSpeed':
          _speedMultiplier = (message['data']['speedMultiplier'] as num).toDouble();
          break;
      }
    }
  }

  void _onSync(Map<String, dynamic> data) {
    final state = SimSyncState.fromJson(data);
    _buildings = state.buildings;
    _conveyors = state.conveyors;
    _recipes = state.recipes;
    _speedMultiplier = state.speedMultiplier;
  }

  void _onStart() {
    if (_isRunning) return;
    _isRunning = true;
    _tickTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _tickRate).round()),
      (_) => _onTick(),
    );
  }

  void _onStop() {
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  void _onTick() {
    final dt = _speedMultiplier / _tickRate;

    _updateConveyors(dt);
    _updateBuildings(dt);

    // 发送轻量结果回主 Isolate
    final result = SimTickResult(
      buildings: _buildings.map((b) => SimBuildingResult(
        id: b.id,
        isBlocked: _buildingBlocked[b.id] ?? false,
        productionProgress: _buildingProgress[b.id] ?? 0.0,
      )).toList(),
      conveyors: _conveyors.map((c) => SimConveyorResult(
        id: c.id,
        itemId: c.itemId,
        flowProgress: c.flowProgress,
        isBlocked: c.isBlocked,
      )).toList(),
    );

    _mainSendPort.send(result.toJson());
  }

  // 临时存储计算结果，避免在 _buildings 上添加额外字段
  final Map<String, bool> _buildingBlocked = {};
  final Map<String, double> _buildingProgress = {};

  void _updateConveyors(double dt) {
    for (int i = 0; i < _conveyors.length; i++) {
      final belt = _conveyors[i];
      if (belt.isBlocked) continue;

      // 更新流动进度
      _conveyors[i] = SimConveyorData(
        id: belt.id,
        path: belt.path,
        itemId: belt.itemId,
        flowProgress: belt.flowProgress + dt * 60,
        isBlocked: belt.isBlocked,
      );
      if (_conveyors[i].flowProgress > 100000) {
        _conveyors[i] = SimConveyorData(
          id: belt.id,
          path: belt.path,
          itemId: belt.itemId,
          flowProgress: 0,
          isBlocked: belt.isBlocked,
        );
      }

      // 检查源设备是否阻塞
      final startPos = _beltStart(belt);
      final sourceBuilding = _findSourceBuilding(startPos);
      if (sourceBuilding != null && (_buildingBlocked[sourceBuilding.id] ?? false)) {
        _conveyors[i] = SimConveyorData(
          id: belt.id,
          path: belt.path,
          itemId: belt.itemId,
          flowProgress: _conveyors[i].flowProgress,
          isBlocked: true,
        );
      } else {
        _conveyors[i] = SimConveyorData(
          id: belt.id,
          path: belt.path,
          itemId: belt.itemId,
          flowProgress: _conveyors[i].flowProgress,
          isBlocked: false,
        );
      }
    }
  }

  void _updateBuildings(double dt) {
    for (final pb in _buildings) {
      if (pb.activeRecipeId == null) continue;
      final recipe = _recipes.where((r) => r.id == pb.activeRecipeId).firstOrNull;
      if (recipe == null) continue;

      final hasInputs = _checkInputsAvailable(pb, recipe);
      final hasOutputSpace = _checkOutputSpace(pb);

      if (!hasInputs || !hasOutputSpace) {
        _buildingBlocked[pb.id] = true;
        _buildingProgress[pb.id] = (_buildingProgress[pb.id] ?? 0.0) * 0.9;
        continue;
      }

      _buildingBlocked[pb.id] = false;
      _buildingProgress[pb.id] = (_buildingProgress[pb.id] ?? 0.0) + dt / recipe.processTimeSeconds;

      if (_buildingProgress[pb.id]! >= 1.0) {
        _buildingProgress[pb.id] = 0.0;
        _consumeInputs(pb, recipe);
        _produceOutputs(pb, recipe);
      }
    }
  }

  bool _checkInputsAvailable(SimBuildingData pb, SimRecipeData recipe) {
    for (final input in recipe.inputs) {
      bool found = false;
      for (final belt in _conveyors) {
        for (final port in pb.inputPorts) {
          final portWorld = _portWorldPosition(port, pb);
          if ((_beltEnd(belt) - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId == input.itemId) {
              found = true;
              break;
            }
          }
        }
        if (found) break;
      }
      if (!found) return false;
    }
    return true;
  }

  bool _checkOutputSpace(SimBuildingData pb) {
    if (_buildingBlocked[pb.id] ?? false) return false;
    for (final port in pb.outputPorts) {
      final portWorld = _portWorldPosition(port, pb);
      for (final belt in _conveyors) {
        if ((_beltStart(belt) - portWorld).distance < _portConnectionThreshold) {
          if (belt.itemId.isEmpty) return true;
        }
      }
    }
    return false;
  }

  void _consumeInputs(SimBuildingData pb, SimRecipeData recipe) {
    for (final input in recipe.inputs) {
      for (final port in pb.inputPorts) {
        final portWorld = _portWorldPosition(port, pb);
        for (int i = 0; i < _conveyors.length; i++) {
          final belt = _conveyors[i];
          if ((_beltEnd(belt) - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId == input.itemId) {
              _conveyors[i] = SimConveyorData(
                id: belt.id,
                path: belt.path,
                itemId: '',
                flowProgress: belt.flowProgress,
                isBlocked: belt.isBlocked,
              );
              break;
            }
          }
        }
      }
    }
  }

  void _produceOutputs(SimBuildingData pb, SimRecipeData recipe) {
    for (final output in recipe.outputs) {
      for (final port in pb.outputPorts) {
        final portWorld = _portWorldPosition(port, pb);
        for (int i = 0; i < _conveyors.length; i++) {
          final belt = _conveyors[i];
          if ((_beltStart(belt) - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId.isEmpty) {
              _conveyors[i] = SimConveyorData(
                id: belt.id,
                path: belt.path,
                itemId: output.itemId,
                flowProgress: belt.flowProgress,
                isBlocked: belt.isBlocked,
              );
              break;
            }
          }
        }
      }
    }
  }

  // === 辅助方法 ===

  SimBuildingData? _findSourceBuilding(Offset worldPos) {
    for (final pb in _buildings) {
      for (final port in pb.outputPorts) {
        final portWorld = _portWorldPosition(port, pb);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  Offset _portWorldPosition(SimPortData port, SimBuildingData pb) {
    double relativeX = port.relativeX;
    double relativeY = port.relativeY;

    double localGridX = (relativeX == 1.0) ? (pb.gridWidth - 1).toDouble() : (relativeX * pb.gridWidth).floorToDouble();
    double localGridY = (relativeY == 1.0) ? (pb.gridHeight - 1).toDouble() : (relativeY * pb.gridHeight).floorToDouble();

    double rx = localGridX + 0.5;
    double ry = localGridY + 0.5;

    double cx = rx - pb.gridWidth / 2.0;
    double cy = ry - pb.gridHeight / 2.0;

    double rcx, rcy;
    switch (pb.rotation % 4) {
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

    double wx = pb.gridX + rcx + pb.gridWidth / 2.0;
    double wy = pb.gridY + rcy + pb.gridHeight / 2.0;

    return Offset(wx * _cellSize, wy * _cellSize);
  }

  Offset _beltStart(SimConveyorData belt) {
    if (belt.path.isEmpty) return Offset.zero;
    return Offset(
      belt.path.first.dx * _cellSize + _cellSize / 2,
      belt.path.first.dy * _cellSize + _cellSize / 2,
    );
  }

  Offset _beltEnd(SimConveyorData belt) {
    if (belt.path.isEmpty) return Offset.zero;
    return Offset(
      belt.path.last.dx * _cellSize + _cellSize / 2,
      belt.path.last.dy * _cellSize + _cellSize / 2,
    );
  }
}
