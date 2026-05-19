import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/recipe.dart';
import '../data/data_loader.dart';

class SimulationEngine extends ChangeNotifier {
  final DataLoader _dataLoader;
  ProjectState? _project;
  Timer? _tickTimer;
  bool _isRunning = false;
  final double _tickRate = 20.0;
  double _speedMultiplier = 1.0;

  static const double _cellSize = 48.0;
  static const double _portConnectionThreshold = 30.0;

  bool get isRunning => _isRunning;
  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double v) {
    _speedMultiplier = v.clamp(0.25, 10.0);
    notifyListeners();
  }

  SimulationEngine(this._dataLoader);

  void attach(ProjectState project) {
    _project = project;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _tickTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _tickRate).round()),
      _onTick,
    );
    notifyListeners();
  }

  void stop() {
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    notifyListeners();
  }

  void toggle() {
    if (_isRunning) {
      stop();
    } else {
      start();
    }
  }

  void _onTick(Timer timer) {
    if (_project == null) return;
    final dt = _speedMultiplier / _tickRate;

    _updateConveyors(dt);
    _updateBuildings(dt);

    notifyListeners();
  }

  void _updateConveyors(double dt) {
    if (_project == null) return;
    for (final belt in _project!.conveyors) {
      if (belt.isBlocked) continue;
      belt.flowProgress += dt * 60;
      if (belt.flowProgress > 100000) belt.flowProgress = 0;

      final sourceBuilding = _findSourceBuilding(belt.start);
      if (sourceBuilding != null && sourceBuilding.isBlocked) {
        belt.isBlocked = true;
      } else {
        belt.isBlocked = false;
      }
    }
  }

  PlacedBuilding? _findSourceBuilding(Offset worldPos) {
    if (_project == null) return null;
    for (final pb in _project!.buildings) {
      for (final port in pb.outputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
        if ((worldPos - portWorld).distance < _portConnectionThreshold) {
          return pb;
        }
      }
    }
    return null;
  }

  void _updateBuildings(double dt) {
    if (_project == null) return;
    for (final pb in _project!.buildings) {
      if (pb.activeRecipeId == null) continue;
      final recipe = _dataLoader.getRecipe(pb.activeRecipeId!);
      if (recipe == null) continue;

      final hasInputs = _checkInputsAvailable(pb, recipe);
      final hasOutputSpace = _checkOutputSpace(pb);

      if (!hasInputs || !hasOutputSpace) {
        pb.isBlocked = true;
        pb.productionProgress = pb.productionProgress * 0.9;
        continue;
      }

      pb.isBlocked = false;
      pb.productionProgress += dt / recipe.processTimeSeconds;

      if (pb.productionProgress >= 1.0) {
        pb.productionProgress = 0.0;
        _consumeInputs(pb, recipe);
        _produceOutputs(pb, recipe);
      }
    }
  }

  bool _checkInputsAvailable(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      bool found = false;
      for (final belt in _project!.conveyors) {
        for (final port in pb.inputPorts) {
          final portWorld = port.worldPosition(
              pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
          if ((belt.end - portWorld).distance < _portConnectionThreshold) {
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

  bool _checkOutputSpace(PlacedBuilding pb) {
    if (pb.isBlocked) return false;

    // Check that at least one connected output belt is empty (no item)
    for (final port in pb.outputPorts) {
      final portWorld = port.worldPosition(
          pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
      for (final belt in _project!.conveyors) {
        if ((belt.start - portWorld).distance < _portConnectionThreshold) {
          if (belt.itemId.isEmpty) return true;
        }
      }
    }
    return false;
  }

  void _consumeInputs(PlacedBuilding pb, Recipe recipe) {
    for (final input in recipe.inputs) {
      for (final port in pb.inputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
        for (final belt in _project!.conveyors) {
          if ((belt.end - portWorld).distance < _portConnectionThreshold) {
            if (belt.itemId == input.itemId) {
              belt.itemId = '';
              break;
            }
          }
        }
      }
    }
  }

  void _produceOutputs(PlacedBuilding pb, Recipe recipe) {
    for (final output in recipe.outputs) {
      for (final port in pb.outputPorts) {
        final portWorld = port.worldPosition(
            pb.gridX, pb.gridY, _cellSize, pb.building.gridWidth, pb.building.gridHeight);
        for (final belt in _project!.conveyors) {
          if ((belt.start - portWorld).distance < _portConnectionThreshold) {
            // Only assign to empty belts, skip belts that already carry items
            if (belt.itemId.isEmpty) {
              belt.itemId = output.itemId;
              port.connected = true;
              port.linkedItemId = output.itemId;
              break;
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
