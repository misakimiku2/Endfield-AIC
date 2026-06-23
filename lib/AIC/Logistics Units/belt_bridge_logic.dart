part of 'transport_belt.dart';

/// 物流桥相关方法
extension _BeltBridgeLogic on TransportBeltController {
  bool _isBlockedBridgeStartSegment(List<Offset> segment) {
    if (segment.length < 2) return false;
    if (_findBeltBridgeAtCell(segment.first) == null) return false;
    return _findBeltAtCell(segment[1]) != null;
  }

  /// 检测 fullPath 与已有传送带的垂直交叉，自动放置物流桥建筑
  /// 不再拆分被交叉的传送带——传送带保持完整路径，物品直接穿过物流桥格子
  void _autoCreateBridgesAtCrossings() {
    // 1. 收集所有交叉点
    final crossings = <Offset>[];

    for (int i = 0; i < fullPath.length; i++) {
      final cell = fullPath[i];
      final newDir = _getPathDirectionAtIndex(fullPath, i);

      for (final belt in project.conveyors) {
        // Skip committed belt and merge target
        if (_committedBeltId != null && belt.id == _committedBeltId) continue;
        if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;

        for (int j = 0; j < belt.path.length; j++) {
          if (belt.path[j].dx.toInt() == cell.dx.toInt() &&
              belt.path[j].dy.toInt() == cell.dy.toInt()) {
            final beltDir = _getBeltDirectionAtCell(belt, j);
            if (_isPerpendicularCrossing(newDir, beltDir)) {
              // Check if there's already a bridge at this cell
              if (_findBeltBridgeAtCell(cell) != null) continue;
              // 交叉点已有建筑（如分流器、汇流器等）时不创建物流桥
              if (_isCellOccupied(cell)) continue;
              // 物流桥不能在转角传送带格子上创建
              if (_isBeltCellTurn(belt, j)) continue;
              crossings.add(cell);
            }
          }
        }
      }
    }

    if (crossings.isEmpty) return;

    // 2. 放置所有物流桥建筑
    for (final cell in crossings) {
      // 再次检查是否已有物流桥（前面的交叉可能已经放置了）
      if (_findBeltBridgeAtCell(cell) != null) continue;
      final building = getBuilding?.call(TransportBeltController._beltBridgeId);
      if (building == null) continue;

      final newBridge = PlacedBuilding(
        id: 'building_${DateTime.now().millisecondsSinceEpoch}',
        building: building,
        gridX: cell.dx - (building.gridWidth ~/ 2).toDouble(),
        gridY: cell.dy - (building.gridHeight ~/ 2).toDouble(),
        rotation: 0,
      );
      project.buildings.add(newBridge);
    }

    // 不再拆分被交叉的传送带——传送带保持完整路径穿过物流桥
  }

  /// 计算预览路径上需要放置物流桥的交叉点（仅用于预览渲染，不实际创建建筑）
  List<Offset> _computePreviewBridgeCells() {
    if (pathInvalid) return [];
    // 构建完整预览路径（已确认段 + 实时段）
    final fullPreviewPath = <Offset>[...confirmedPath];
    if (previewPath != null) {
      // 去重：已确认段末尾和实时段开头可能重叠
      if (fullPreviewPath.isNotEmpty && previewPath!.isNotEmpty &&
          fullPreviewPath.last.dx == previewPath!.first.dx &&
          fullPreviewPath.last.dy == previewPath!.first.dy) {
        fullPreviewPath.addAll(previewPath!.skip(1));
      } else {
        fullPreviewPath.addAll(previewPath!);
      }
    }
    if (fullPreviewPath.length < 2) return [];

    final crossings = <Offset>[];
    for (int i = 0; i < fullPreviewPath.length; i++) {
      final cell = fullPreviewPath[i];
      final newDir = _getPathDirectionAtIndex(fullPreviewPath, i);
      for (final belt in project.conveyors) {
        if (_committedBeltId != null && belt.id == _committedBeltId) continue;
        if (_mergeTarget != null && identical(belt, _mergeTarget)) continue;
        for (int j = 0; j < belt.path.length; j++) {
          if (belt.path[j].dx.toInt() == cell.dx.toInt() &&
              belt.path[j].dy.toInt() == cell.dy.toInt()) {
            final beltDir = _getBeltDirectionAtCell(belt, j);
            if (_isPerpendicularCrossing(newDir, beltDir)) {
              if (_findBeltBridgeAtCell(cell) != null) continue;
              // 交叉点已有建筑（如分流器、汇流器等）时不创建物流桥
              if (_isCellOccupied(cell)) continue;
              // 物流桥不能在转角传送带格子上创建
              if (_isBeltCellTurn(belt, j)) continue;
              if (crossings.any((c) =>
                  c.dx.toInt() == cell.dx.toInt() &&
                  c.dy.toInt() == cell.dy.toInt())) {
                continue;
              }
              crossings.add(cell);
            }
          }
        }
      }
    }
    return crossings;
  }
}
