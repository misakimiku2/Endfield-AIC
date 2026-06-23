part of 'transport_belt.dart';

/// 路径验证相关方法
extension _BeltPathValidation on TransportBeltController {
  bool _isPathPrefix(List<Offset> prefix, List<Offset> path) {
    if (prefix.length > path.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (prefix[i].dx.toInt() != path[i].dx.toInt() ||
          prefix[i].dy.toInt() != path[i].dy.toInt()) {
        return false;
      }
    }
    return true;
  }

  /// 验证路径在物流桥格子处是否保持直线（不能在物流桥内转弯）
  bool _isPathValidAtBridges(List<Offset> path) {
    for (int i = 0; i < path.length; i++) {
      if (_findBeltBridgeAtCell(path[i]) == null) continue;
      // 物流桥格子：前后方向必须一致
      final dirIn = i > 0 ? _directionBetween(path[i - 1], path[i]) : null;
      final dirOut =
          i < path.length - 1 ? _directionBetween(path[i], path[i + 1]) : null;
      if (dirIn != null && dirOut != null && dirIn != dirOut) {
        return false; // 在物流桥处转弯，路径无效
      }
    }
    return true;
  }

  /// 检查新路径在连接点处的方向是否与目标传送带起始方向一致
  bool _isDirectionCompatible(List<Offset> newPath, ConveyorBelt targetBelt) {
    if (newPath.length < 2) return false;

    // 新路径在连接点处的方向（倒数第二格 -> 最后一格）
    final lastCell = newPath.last;
    final prevCell = newPath[newPath.length - 2];
    final newDx = lastCell.dx - prevCell.dx;
    final newDy = lastCell.dy - prevCell.dy;

    // 目标传送带在起点处的方向
    final direction = _getBeltDirectionVector(targetBelt);
    if (direction == null) return false;
    final (beltDx, beltDy) = direction;

    // 方向兼容：不允许反方向合并（新路径到达方向与目标传送带出方向相反）
    // 直线合并和转角合并都允许
    return !(newDx == -beltDx && newDy == -beltDy);
  }

  /// 查找指定格子上的传送带方向向量（排除物流桥、已提交传送带、合并目标）。
  /// 用于检测路径是否与现有传送带平行重叠或在交叉点转弯。
  /// 返回 (dx, dy) 方向向量，如果格子不在任何传送带上则返回 null。
  (int, int)? _getCrossingBeltDirectionAtCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      for (int j = 0; j < belt.path.length; j++) {
        if (belt.path[j].dx.toInt() == gx &&
            belt.path[j].dy.toInt() == gy) {
          final dir = _getBeltDirectionAtCell(belt, j);
          if (dir == null) return null;
          final dx = switch (dir) { 'right' => 1, 'left' => -1, _ => 0 };
          final dy = switch (dir) { 'down' => 1, 'up' => -1, _ => 0 };
          return (dx, dy);
        }
      }
    }
    return null;
  }

  /// 验证路径不与现有传送带平行重叠，且在交叉点处保持直线（不能转弯）。
  /// 跳过起点（分叉/延长点）。
  /// 终点格子若为合并候选（传送带起点）则允许平行方向（合并连接）。
  bool _isPathValidAtBeltCrossings(List<Offset> path) {
    for (int i = 1; i < path.length; i++) {
      final cell = path[i];
      // 物流桥格子由 _isPathValidAtBridges 处理
      if (_findBeltBridgeAtCell(cell) != null) continue;

      final beltDir = _getCrossingBeltDirectionAtCell(cell);
      if (beltDir == null) continue; // 不在任何传送带上

      // 物流桥不能在转角传送带格子上创建：穿过转角格子则路径无效
      if (_isCrossingBeltCellTurn(cell)) return false;

      final (beltDx, _) = beltDir;
      final dirIn = _directionBetween(path[i - 1], path[i]);
      final dirOut = i + 1 < path.length
          ? _directionBetween(path[i], path[i + 1])
          : null;
      if (dirIn == null) continue;

      final pathDx = switch (dirIn) { 'right' => 1, 'left' => -1, _ => 0 };
      final isPathDirVertical = pathDx == 0;
      final isBeltDirVertical = beltDx == 0;

      // 平行重叠检查
      if (isPathDirVertical == isBeltDirVertical) {
        // 终点格子若为合并候选（传送带起点）则允许
        if (i == path.length - 1 && _isMergeCandidateCell(cell)) {
          // 允许合并连接
        } else {
          return false;
        }
      }

      // 交叉点处必须直线通过（不能转弯）
      if (dirOut != null && dirIn != dirOut) {
        return false;
      }
    }
    return true;
  }

  /// 检查格子是否为合并候选（传送带起点，排除已提交传送带和合并目标）
  bool _isMergeCandidateCell(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      if (belt.path.isNotEmpty &&
          belt.path.first.dx.toInt() == gx &&
          belt.path.first.dy.toInt() == gy) {
        return true;
      }
    }
    return false;
  }

  /// 判断两个方向是否垂直交叉（一个水平一个垂直）
  bool _isPerpendicularCrossing(String? dir1, String? dir2) {
    if (dir1 == null || dir2 == null) return false;
    final isVertical1 = dir1 == 'up' || dir1 == 'down';
    final isVertical2 = dir2 == 'up' || dir2 == 'down';
    return isVertical1 != isVertical2;
  }

  /// 获取传送带在指定格子处的移动方向
  String? _getBeltDirectionAtCell(ConveyorBelt belt, int cellIndex) {
    if (belt.path.length < 2) return belt.forcedDirection;
    if (cellIndex > 0 && cellIndex < belt.path.length) {
      return _directionBetween(belt.path[cellIndex - 1], belt.path[cellIndex]);
    }
    if (cellIndex == 0 && belt.path.length >= 2) {
      return _directionBetween(belt.path[0], belt.path[1]);
    }
    return null;
  }

  /// 判断已有传送带的指定格子是否是转角（与 canvas_editor 中 _isStraightBeltCell 相反）
  /// 物流桥不能在转角传送带格子上创建
  bool _isBeltCellTurn(ConveyorBelt belt, int cellIndex) {
    final path = belt.path;
    if (path.isEmpty || cellIndex < 0 || cellIndex >= path.length) {
      return false;
    }

    // 单格路径：仅当入方向与强制方向都存在且不同时为转角
    if (path.length == 1) {
      final incoming = belt.incomingDirection;
      final forced = belt.forcedDirection;
      return incoming != null && forced != null && incoming != forced;
    }

    // 首格：需要 incomingDirection 与出方向比较
    if (cellIndex == 0) {
      final incoming = belt.incomingDirection;
      if (incoming == null) return false;
      final outgoing = _directionBetween(path[0], path[1]);
      if (outgoing == null) return false;
      return incoming != outgoing;
    }

    // 末格：与 _isStraightBeltCell 一致，末格不算转角
    if (cellIndex == path.length - 1) return false;

    // 中间格：入方向与出方向不同则为转角
    final dirIn = _directionBetween(path[cellIndex - 1], path[cellIndex]);
    final dirOut = _directionBetween(path[cellIndex], path[cellIndex + 1]);
    if (dirIn == null || dirOut == null) return false;
    return dirIn != dirOut;
  }

  /// 检查指定格子处的已有传送带格子是否是转角（排除已提交传送带和合并目标）
  bool _isCrossingBeltCellTurn(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      if (_committedBeltId != null && belt.id == _committedBeltId) continue;
      if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
      for (int j = 0; j < belt.path.length; j++) {
        if (belt.path[j].dx.toInt() == gx &&
            belt.path[j].dy.toInt() == gy) {
          return _isBeltCellTurn(belt, j);
        }
      }
    }
    return false;
  }

  /// 获取路径在指定索引处的移动方向
  String? _getPathDirectionAtIndex(List<Offset> path, int index) {
    if (path.length < 2) return null;
    if (index > 0) {
      return _directionBetween(path[index - 1], path[index]);
    }
    if (index == 0 && path.length >= 2) {
      return _directionBetween(path[0], path[1]);
    }
    return null;
  }
}
