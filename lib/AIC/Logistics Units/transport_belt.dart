import 'package:flutter/material.dart';
import '../../models/project.dart';

/// 传送带创建控制器：管理锚点、路径、预览、寻路等全部状态和逻辑
class TransportBeltController {
  ProjectState project;
  final void Function(ProjectState) onProjectChanged;
  final void Function() onRebuildCache;
  final void Function() notifyListeners;

  TransportBeltController({
    required this.project,
    required this.onProjectChanged,
    required this.onRebuildCache,
    required this.notifyListeners,
  });

  // === 状态 ===
  List<Offset> anchors = [];
  List<Offset> fullPath = [];
  List<Offset> confirmedPath = [];
  bool pathInvalid = false;
  List<Offset>? previewPath;
  Set<String>? previewOccupied;
  Offset? mouseGridPos;
  ConveyorBelt? _mergeTarget;

  // === 静态工具 ===
  static const double cellSize = 48.0;

  // === 公开 API ===

  void reset() {
    anchors = [];
    fullPath = [];
    confirmedPath = [];
    pathInvalid = false;
    previewPath = null;
    previewOccupied = null;
    _mergeTarget = null;
  }

  /// 返回 true 表示点击已被处理
  bool handleTap(Offset gridPos) {
    if (anchors.isEmpty) {
      return _handleFirstAnchor(gridPos);
    }
    return _handleSubsequentAnchor(gridPos);
  }

  void handleHover(Offset gridPos) {
    if (mouseGridPos == gridPos) return;
    mouseGridPos = gridPos;
    _updatePreview();
    notifyListeners();
  }

  void handleRightClick() {
    _finish();
    notifyListeners();
  }

  /// 返回 true 表示 ESC 已被处理
  bool handleKeyEscape() {
    if (anchors.isNotEmpty) {
      _finish();
      notifyListeners();
      return true;
    }
    return false;
  }

  // === 内部实现 ===

  bool _handleFirstAnchor(Offset gridPos) {
    final belt = _findBeltAtCell(gridPos);
    if (belt != null) {
      fullPath = _traceBeltToCell(belt, gridPos);
      anchors.add(gridPos);
      _updatePreview();
      notifyListeners();
      return true;
    }
    if (_isCellInBuilding(gridPos)) {
      anchors.add(gridPos);
      _updatePreview();
      notifyListeners();
      return true;
    }
    return false;
  }

  bool _handleSubsequentAnchor(Offset gridPos) {
    if (anchors.last == gridPos) return false;

    // 检查是否点击了某条传送带的起点（合并候选）
    final mergeBelt = _findBeltStartCell(gridPos);
    if (mergeBelt != null) {
      // 不允许与路径中已包含的传送带合并（避免回环）
      final alreadyInPath = fullPath.any(
          (c) => c.dx == gridPos.dx && c.dy == gridPos.dy);
      if (!alreadyInPath) {
        final blocked = _buildBlockedSet(excludeCell: gridPos);
        final verticalFirst = _isIncomingVertical();
        final segment = _findPath(anchors.last, gridPos, blocked,
            verticalFirst: verticalFirst);
        if (segment != null &&
            segment.length >= 2 &&
            _isDirectionCompatible(segment, mergeBelt)) {
          if (fullPath.isEmpty) {
            fullPath.addAll(segment);
          } else {
            if (segment.length > 1) {
              fullPath.addAll(segment.sublist(1));
            }
          }
          anchors.add(gridPos);
          _mergeTarget = mergeBelt;
          _finish(); // 合并时自动完成创建
          notifyListeners();
          return true;
        }
      }
      // 方向不兼容或路径不通，返回 false 让预览显示红色
      return false;
    }

    if (_isCellOccupied(gridPos)) return false;

    final blocked = _buildBlockedSet();
    final verticalFirst = _isIncomingVertical();

    final segment = _findPath(anchors.last, gridPos, blocked, verticalFirst: verticalFirst);
    if (segment == null || segment.length < 2) return false;

    if (fullPath.isEmpty) {
      fullPath.addAll(segment);
    } else {
      if (segment.length > 1) {
        fullPath.addAll(segment.sublist(1));
      }
    }

    anchors.add(gridPos);
    _updatePreview();
    notifyListeners();
    return true;
  }

  void _finish() {
    if (anchors.length >= 2 && fullPath.length >= 2) {
      // 合并：将合并目标的路径追加到 fullPath（跳过首格，因为已包含）
      if (_mergeTarget != null && _mergeTarget!.path.length > 1) {
        fullPath.addAll(_mergeTarget!.path.sublist(1));
      }

      final belt = ConveyorBelt(
        id: 'belt_${DateTime.now().millisecondsSinceEpoch}',
        path: List<Offset>.from(fullPath),
        itemId: '',
        isBlocked: false,
      );

      // 检查新传送带的起点是否在某条旧传送带的节点上，进行截断与拆分
      // 使用 anchors.first（用户实际点击的位置）作为分叉点，而非 fullPath.first
      final startCell = anchors.first;
      final toRemove = <ConveyorBelt>[];
      final toAdd = <ConveyorBelt>[];

      for (final oldBelt in project.conveyors) {
        // 跳过合并目标（会单独移除）
        if (_mergeTarget != null && identical(oldBelt, _mergeTarget)) continue;

        int forkIdx = -1;
        for (int i = 0; i < oldBelt.path.length; i++) {
          if (oldBelt.path[i].dx == startCell.dx && oldBelt.path[i].dy == startCell.dy) {
            forkIdx = i;
            break;
          }
        }

        if (forkIdx >= 0) {
          toRemove.add(oldBelt);
          // 保留分叉点之后的下游部分
          if (forkIdx + 1 < oldBelt.path.length) {
            final downstream = oldBelt.path.sublist(forkIdx + 1);
            if (downstream.length >= 2) {
              toAdd.add(ConveyorBelt(
                id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${oldBelt.id}',
                path: downstream,
                itemId: oldBelt.itemId,
                isBlocked: oldBelt.isBlocked,
              ));
            }
          }
        }
      }

      // 移除合并目标
      if (_mergeTarget != null) {
        toRemove.add(_mergeTarget!);
      }

      for (final old in toRemove) {
        project.conveyors.remove(old);
      }
      for (final newBelt in toAdd) {
        project.conveyors.add(newBelt);
      }

      project.conveyors.add(belt);
      project.offsetX; // no-op to ensure project reference works
      onProjectChanged(project);
      onRebuildCache();
    }

    reset();
  }

  // === 辅助方法 ===

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

  /// 检查新路径在连接点处的方向是否与目标传送带起始方向一致
  bool _isDirectionCompatible(List<Offset> newPath, ConveyorBelt targetBelt) {
    if (newPath.length < 2 || targetBelt.path.length < 2) return false;

    // 新路径在连接点处的方向（倒数第二格 → 最后一格）
    final lastCell = newPath.last;
    final prevCell = newPath[newPath.length - 2];
    final newDx = lastCell.dx - prevCell.dx;
    final newDy = lastCell.dy - prevCell.dy;

    // 目标传送带在起点处的方向（第一格 → 第二格）
    final beltStart = targetBelt.path.first;
    final beltNext = targetBelt.path[1];
    final beltDx = beltNext.dx - beltStart.dx;
    final beltDy = beltNext.dy - beltStart.dy;

    return newDx == beltDx && newDy == beltDy;
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
      final bx = pb.gridX.toInt();
      final by = pb.gridY.toInt();
      if (gx >= bx && gx < bx + pb.building.gridWidth &&
          gy >= by && gy < by + pb.building.gridHeight) {
        return true;
      }
    }
    return false;
  }

  bool _isCellOccupied(Offset gridPos) {
    final gx = gridPos.dx.toInt();
    final gy = gridPos.dy.toInt();
    for (final belt in project.conveyors) {
      for (final cell in belt.path) {
        if (cell.dx.toInt() == gx && cell.dy.toInt() == gy) return true;
      }
    }
    for (final pb in project.buildings) {
      final bx = pb.gridX.toInt();
      final by = pb.gridY.toInt();
      final bw = pb.building.gridWidth;
      final bh = pb.building.gridHeight;
      if (gx >= bx && gx < bx + bw && gy >= by && gy < by + bh) return true;
    }
    return false;
  }

  Set<String> _getOccupiedCellSet() {
    final cells = <String>{};
    for (final belt in project.conveyors) {
      for (final cell in belt.path) {
        cells.add('${cell.dx.toInt()}_${cell.dy.toInt()}');
      }
    }
    for (final pb in project.buildings) {
      final bx = pb.gridX.toInt();
      final by = pb.gridY.toInt();
      for (int dx = 0; dx < pb.building.gridWidth; dx++) {
        for (int dy = 0; dy < pb.building.gridHeight; dy++) {
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

    if (anchors.isNotEmpty) {
      blocked.remove('${anchors.last.dx.toInt()}_${anchors.last.dy.toInt()}');
    }
    if (excludeCell != null) {
      blocked.remove('${excludeCell.dx.toInt()}_${excludeCell.dy.toInt()}');
    }
    return blocked;
  }

  bool _isIncomingVertical() {
    if (anchors.length < 2) return false;
    final prev = anchors[anchors.length - 2];
    final last = anchors.last;
    return (last.dy - prev.dy).abs() > (last.dx - prev.dx).abs();
  }

  // === 预览 ===

  void _updatePreview() {
    if (anchors.isEmpty || mouseGridPos == null) {
      previewPath = null;
      previewOccupied = null;
      confirmedPath = [];
      pathInvalid = false;
      return;
    }

    final lastAnchor = anchors.last;

    // 检查鼠标是否悬停在某条传送带的起点（合并候选）
    final mergeBelt = _findBeltStartCell(mouseGridPos!);
    Offset? excludeCell;
    if (mergeBelt != null) {
      final alreadyInPath = fullPath.any(
          (c) => c.dx == mouseGridPos!.dx && c.dy == mouseGridPos!.dy);
      if (!alreadyInPath) {
        excludeCell = mouseGridPos!;
      }
    }

    final blocked = _buildBlockedSet(excludeCell: excludeCell);
    final verticalFirst = _isIncomingVertical();

    final livePath = _findPath(lastAnchor, mouseGridPos!, blocked, verticalFirst: verticalFirst);
    if (livePath == null) {
      confirmedPath = fullPath.length > 1 ? fullPath.sublist(0, fullPath.length - 1) : <Offset>[];
      previewPath = _calculateStraightPath(lastAnchor, mouseGridPos!);
      previewOccupied = null;
      pathInvalid = true;
    } else {
      confirmedPath = fullPath.length > 1 ? fullPath.sublist(0, fullPath.length - 1) : <Offset>[];
      previewPath = livePath;
      previewOccupied = null;

      // 悬停在传送带起点时，检查方向兼容性
      if (mergeBelt != null && excludeCell != null) {
        if (!_isDirectionCompatible(livePath, mergeBelt)) {
          pathInvalid = true;
        } else {
          pathInvalid = false;
        }
      } else {
        pathInvalid = false;
      }
    }
  }

  List<Offset> _deduplicatePath(List<Offset> path) {
    if (path.length < 2) return path;
    final result = <Offset>[path.first];
    for (int i = 1; i < path.length; i++) {
      if (path[i] != path[i - 1]) {
        result.add(path[i]);
      }
    }
    return result;
  }

  // === 寻路 ===

  List<Offset>? _findPath(Offset start, Offset end, Set<String> blocked, {bool verticalFirst = false}) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    final momentumPath = _calculateMomentumPath(start, end, verticalFirst: verticalFirst);
    bool momentumValid = true;
    for (final cell in momentumPath) {
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      if (blocked.contains(key) && key != startKey) {
        momentumValid = false;
        break;
      }
    }
    if (momentumValid) return _deduplicatePath(momentumPath);

    final bfsPath = _findPathBFS(start, end, blocked);
    return bfsPath != null ? _deduplicatePath(bfsPath) : null;
  }

  List<Offset> _calculateMomentumPath(Offset start, Offset end, {bool verticalFirst = false}) {
    final sx = start.dx.toInt();
    final sy = start.dy.toInt();
    final ex = end.dx.toInt();
    final ey = end.dy.toInt();

    if (sx == ex && sy == ey) return [start];

    final path = <Offset>[];

    if (verticalFirst) {
      if (sy != ey) {
        final dy = ey > sy ? 1 : -1;
        for (int y = sy; y != ey; y += dy) {
          path.add(Offset(sx.toDouble(), y.toDouble()));
        }
      }
      if (sx != ex) {
        final dx = ex > sx ? 1 : -1;
        for (int x = sx; x != ex; x += dx) {
          path.add(Offset(x.toDouble(), ey.toDouble()));
        }
      }
    } else {
      if (sx != ex) {
        final dx = ex > sx ? 1 : -1;
        for (int x = sx; x != ex; x += dx) {
          path.add(Offset(x.toDouble(), sy.toDouble()));
        }
      }
      if (sy != ey) {
        final dy = ey > sy ? 1 : -1;
        for (int y = sy; y != ey; y += dy) {
          path.add(Offset(ex.toDouble(), y.toDouble()));
        }
      }
    }

    path.add(Offset(ex.toDouble(), ey.toDouble()));
    return path;
  }

  List<Offset>? _findPathBFS(Offset start, Offset end, Set<String> blocked) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    final queue = <_BFSNode>[];
    final visited = <String, Offset?>{startKey: null};
    queue.add(_BFSNode(start.dx.toInt(), start.dy.toInt()));

    const dirs = [
      [0, -1],
      [0, 1],
      [-1, 0],
      [1, 0],
    ];

    int searched = 0;
    while (queue.isNotEmpty && searched < 5000) {
      final node = queue.removeAt(0);
      final nodeKey = '${node.x}_${node.y}';
      searched++;

      if (nodeKey == endKey) {
        final path = <Offset>[];
        String? key = endKey;
        while (key != null) {
          final parts = key.split('_');
          path.add(Offset(double.parse(parts[0]), double.parse(parts[1])));
          final parent = visited[key];
          key = parent == null ? null : '${parent.dx.toInt()}_${parent.dy.toInt()}';
        }
        return path.reversed.toList();
      }

      for (final d in dirs) {
        final nx = node.x + d[0];
        final ny = node.y + d[1];
        final nKey = '${nx}_$ny';
        if (blocked.contains(nKey) && nKey != startKey) continue;
        if (visited.containsKey(nKey)) continue;
        visited[nKey] = Offset(node.x.toDouble(), node.y.toDouble());
        queue.add(_BFSNode(nx, ny));
      }
    }

    return null;
  }

  List<Offset> _calculateStraightPath(Offset startGrid, Offset endGrid) {
    final sx = startGrid.dx.toInt();
    final sy = startGrid.dy.toInt();
    final ex = endGrid.dx.toInt();
    final ey = endGrid.dy.toInt();

    if (sx == ex && sy == ey) return [startGrid];

    final path = <Offset>[];

    if (sx != ex) {
      final dx = ex > sx ? 1 : -1;
      for (int x = sx; x != ex; x += dx) {
        path.add(Offset(x.toDouble(), sy.toDouble()));
      }
    }

    if (sy != ey) {
      final dy = ey > sy ? 1 : -1;
      for (int y = sy; y != ey; y += dy) {
        path.add(Offset(ex.toDouble(), y.toDouble()));
      }
    }

    path.add(Offset(ex.toDouble(), ey.toDouble()));
    return path;
  }
}

class _BFSNode {
  final int x, y;
  _BFSNode(this.x, this.y);
}