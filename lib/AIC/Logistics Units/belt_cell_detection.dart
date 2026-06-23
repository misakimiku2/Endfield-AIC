part of 'transport_belt.dart';

/// 单元格/建筑/端口检测相关方法
extension _BeltCellDetection on TransportBeltController {
  /// 查找以 gridPos 为起点的传送带（合并候选）
  ConveyorBelt? _findBeltStartCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (belt.path.isNotEmpty) {
        final start = belt.path.first;
        if (start.dx.toInt() == gx && start.dy.toInt() == gy) {
          return belt;
        }
      }
    }
    return null;
  }

  /// 查找与 fromCell 相邻且方向兼容的传送带起点（转角吸附）
  /// 返回 (传送带, 起点坐标) 或 null
  /// 只有当从 fromCell 到相邻起点的方向与传送带出方向一致时才吸附，
  /// 这样确保路径在连接点处与传送带方向吻合，不会产生 S 弯
  (ConveyorBelt, Offset)? _findAdjacentBeltStart(Offset fromCell) {
    final fx = fromCell.dx.toInt();
    final fy = fromCell.dy.toInt();
    // 检查四个方向
    const dirs = [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)];
    for (final d in dirs) {
      final nx = fx + d.dx.toInt();
      final ny = fy + d.dy.toInt();
      final neighbor = Offset(nx.toDouble(), ny.toDouble());
      final belt = _findBeltStartCell(neighbor);
      if (belt == null) continue;
      // 排除已在路径中的格子
      if (fullPath.any((c) => c.dx == neighbor.dx && c.dy == neighbor.dy)) {
        continue;
      }
      // 排除 anchors 中的格子（路径起点），防止转角吸附导致路径回环
      // 如从分流器向左创建传送带时，预览末尾检测到分流器格子上已有传送带起点，
      // 导致预览路径回环到起点形成 U 型弯
      if (anchors.any((a) => a.dx == neighbor.dx && a.dy == neighbor.dy)) {
        continue;
      }
      // 检查方向兼容性：从 fromCell 到 neighbor 的方向必须与传送带出方向一致
      final toDx = d.dx.toInt();
      final toDy = d.dy.toInt();
      if (_directionMatchesBeltOutgoing(toDx, toDy, belt)) {
        return (belt, neighbor);
      }
    }
    return null;
  }

  ConveyorBelt? _findBeltAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return belt;
      }
    }
    return null;
  }

  /// 查找包含指定格子的传送带，排除指定 ID 的传送带
  ConveyorBelt? _findBeltAtCellExcluding(Offset gridPos, String? excludeId) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (excludeId != null && belt.id == excludeId) continue;
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return belt;
      }
    }
    return null;
  }

  List<Offset> _traceBeltToCell(ConveyorBelt belt, Offset cell) {
    final result = <Offset>[];
    final cx = cell.dx.toInt();
    final cy = cell.dy.toInt();
    for (final c in belt.path) {
      result.add(c);
      if (c.dx.toInt() == cx && c.dy.toInt() == cy) break;
    }
    return result;
  }

  bool _isCellInBuilding(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 查找指定格子上的物流桥建筑
  PlacedBuilding? _findBeltBridgeAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (!pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return pb;
      }
    }

    return null;
  }

  bool _isCellOccupied(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    // Belt cells are not considered occupied (belts can cross each other)
    for (final pb in project.buildings) {
      // 物流桥格子不视为已占用（传送带可穿过）
      if (pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  Set<String> _getOccupiedCellSet() {
    final cells = <String>{};
    // Do NOT add belt cells - belts can cross each other perpendicularly
    for (final pb in project.buildings) {
      // 物流桥格子不视为已占用（传送带可穿过）
      if (pb.isBeltBridge) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      for (int dx = 0; dx < pb.effectiveWidth; dx++) {
        for (int dy = 0; dy < pb.effectiveHeight; dy++) {
          cells.add('${bx + dx}_${by + dy}');
        }
      }
    }
    return cells;
  }

  Set<String> _buildBlockedSet({Offset? excludeCell}) {
    final blocked = _getOccupiedCellSet();

    for (final cell in fullPath) {
      blocked.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
    }

    // 截断创建时，原传送带截断点之后的剩余格子视为阻挡
    for (final cell in _truncatedBeltTail) {
      blocked.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
    }

    if (anchors.isNotEmpty) {
      blocked.remove('${anchors.last.dx.toInt()}_${anchors.last.dy.toInt()}');
    }
    if (excludeCell != null) {
      blocked.remove('${excludeCell.dx.toInt()}_${excludeCell.dy.toInt()}');
    }
    return blocked;
  }

  // === 设备端口检测 ===

  /// 在 gridPos 处查找设备端口，返回 (设备, 端口定义, 'input'/'output', 旋转后的世界方向)
  ({
    PlacedBuilding building,
    PortDefinition definition,
    String type,
    String worldDirection
  })? _findPortAtCell(Offset gridPos, {String? preferredType, String? incomingDirection}) {
    final gx = gridPos.dx.round();
    final gy = gridPos.dy.round();

    ({
      PlacedBuilding building,
      PortDefinition definition,
      String type,
      String worldDirection
    })? findPortOfType(PlacedBuilding pb, String type) {
      final rot = pb.rotation;
      final gw = pb.building.gridWidth;
      final gh = pb.building.gridHeight;
      final ports = type == 'input' ? pb.inputPorts : pb.outputPorts;
      final matches = <({PlacedBuilding building, PortDefinition definition, String type, String worldDirection})>[];
      for (final port in ports) {
        final portGrid =
            port.gridPosition(pb.gridX, pb.gridY, gw, gh, rotation: rot);
        final px = portGrid.dx.round();
        final py = portGrid.dy.round();
        if (px == gx && py == gy) {
          final worldDir = _rotateDirection(port.definition.direction, rot);
          // 如果指定了来向，优先匹配方向与来向一致的端口
          if (incomingDirection != null && worldDir == incomingDirection) {
            return (
              building: pb,
              definition: port.definition,
              type: type,
              worldDirection: worldDir,
            );
          }
          matches.add((
            building: pb,
            definition: port.definition,
            type: type,
            worldDirection: worldDir,
          ));
        }
      }
      // 没有精确匹配时返回第一个匹配
      return matches.isNotEmpty ? matches.first : null;
    }

    for (final pb in project.buildings) {
      if (preferredType != null) {
        final preferred = findPortOfType(pb, preferredType);
        if (preferred != null) return preferred;
        final fallback =
            findPortOfType(pb, preferredType == 'input' ? 'output' : 'input');
        if (fallback != null) return fallback;
      } else {
        final input = findPortOfType(pb, 'input');
        if (input != null) return input;
        final output = findPortOfType(pb, 'output');
        if (output != null) return output;
      }
    }
    return null;
  }

  /// 检查路径中是否至少有一个不在任何设备内部的格子（独立传送带格子）
  /// 设备输入/输出端口之间必须预留至少一格给传送带显示
  /// 物流桥格子视为可穿过，不算作设备内部
  bool _hasIndependentBeltCell(List<Offset> path) {
    for (final cell in path) {
      if (!_isCellInBuilding(cell)) {
        return true;
      }
      // 物流桥格子视为独立格子（传送带可穿过）
      if (_findBeltBridgeAtCell(cell) != null) {
        return true;
      }
    }
    return false;
  }

  /// 检查 gridPos 是否为设备的输入端口格子
  bool _isCellDeviceInputPort(Offset gridPos) {
    final portInfo = _findPortAtCell(gridPos, preferredType: 'input');
    return portInfo != null && portInfo.type == 'input';
  }

  /// 检查 gridPos 是否在某个有输入端口的建筑内（如1x1分流器）。
  /// _isCellDeviceInputPort 对1x1建筑无效（端口在格边缘），此函数补检。
  bool _buildingAtCellHasInputPort(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (pb.inputPorts.isEmpty) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 检查目标格子是否被有输出端口的建筑占据（不依赖端口坐标，解决 1x1 建筑坐标偏差问题）
  bool _buildingAtCellHasOutputPort(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final pb in project.buildings) {
      if (pb.outputPorts.isEmpty) continue;
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx >= bx &&
          gx < bx + pb.effectiveWidth &&
          gy >= by &&
          gy < by + pb.effectiveHeight) {
        return true;
      }
    }
    return false;
  }

  /// 计算建筑在 gridPos 处的所有输出端口旋转后的世界方向集合。
  /// 用于限制传送带首段只能沿这些方向创建，阻止往输入端方向创建。
  Set<String>? _computeAllowedDirectionsForBuilding(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    final dirs = <String>{};
    for (final pb in project.buildings) {
      final bx = pb.effectiveGridX.toInt();
      final by = pb.effectiveGridY.toInt();
      if (gx < bx || gx >= bx + pb.effectiveWidth ||
          gy < by || gy >= by + pb.effectiveHeight) {
        continue;
      }
      final rot = pb.rotation;
      for (final port in pb.outputPorts) {
        final worldDir = _rotateDirection(port.definition.direction, rot);
        if (worldDir.isNotEmpty) dirs.add(worldDir);
      }
    }
    return dirs.isNotEmpty ? dirs : null;
  }
}
