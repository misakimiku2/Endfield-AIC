part of 'transport_belt.dart';

/// 方向/寻路相关方法
extension _BeltDirectionUtils on TransportBeltController {
  ConveyorBelt? _findBridgeContinuationSourceBelt(
      Offset bridgeCell, String? outgoingDirection) {
    if (outgoingDirection == null) return null;
    final bx = bridgeCell.dx.toInt();
    final by = bridgeCell.dy.toInt();
    for (final belt in project.conveyors) {
      for (int i = 0; i < belt.path.length; i++) {
        final cell = belt.path[i];
        if (cell.dx.toInt() != bx || cell.dy.toInt() != by) continue;
        if (i != belt.path.length - 1) continue;
        if (_getBeltDirectionAtCell(belt, i) == outgoingDirection) {
          return belt;
        }
      }
    }
    return null;
  }

  /// 获取传送带的方向向量 (dx, dy)，如果无法确定则返回 null
  (int, int)? _getBeltDirectionVector(ConveyorBelt belt) {
    if (belt.path.length >= 2) {
      final beltStart = belt.path.first;
      final beltNext = belt.path[1];
      final beltDx = (beltNext.dx - beltStart.dx).toInt();
      final beltDy = (beltNext.dy - beltStart.dy).toInt();
      return (beltDx, beltDy);
    } else if (belt.forcedDirection != null) {
      final dir = belt.forcedDirection!;
      final beltDx = switch (dir) { 'right' => 1, 'left' => -1, _ => 0 };
      final beltDy = switch (dir) { 'down' => 1, 'up' => -1, _ => 0 };
      return (beltDx, beltDy);
    }
    return null;
  }

  /// 检查给定方向是否与传送带的出方向一致
  bool _directionMatchesBeltOutgoing(int dx, int dy, ConveyorBelt belt) {
    final direction = _getBeltDirectionVector(belt);
    if (direction == null) return false;
    final (beltDx, beltDy) = direction;
    return dx == beltDx && dy == beltDy;
  }

  int _clampDownstreamCount(int count, int removedPrefixLength) {
    final shifted = count - removedPrefixLength;
    return shifted > 0 ? shifted : 0;
  }

  String? _directionBetween(Offset from, Offset to) {
    final dx = (to.dx - from.dx).toInt();
    final dy = (to.dy - from.dy).toInt();
    if (dx > 0) return 'right';
    if (dx < 0) return 'left';
    if (dy > 0) return 'down';
    if (dy < 0) return 'up';
    return null;
  }

  bool _isIncomingVertical() {
    if (anchors.length < 2) return false;
    final prev = anchors[anchors.length - 2];
    final last = anchors.last;
    return (last.dy - prev.dy).abs() > (last.dx - prev.dx).abs();
  }

  String _rotateDirection(String original, int rotation) {
    const directions = ['up', 'right', 'down', 'left'];
    final idx = directions.indexOf(original);
    if (idx == -1) return original;
    return directions[(idx + rotation) % 4];
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

  List<Offset>? _findPath(Offset start, Offset end, Set<String> blocked,
      {bool verticalFirst = false}) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    // 检查终点是否为设备的输入端口
    final portInfo = _findPortAtCell(end, preferredType: 'input');
    if (portInfo != null &&
        portInfo.type == 'input' &&
        portInfo.building.building.id != TransportBeltController._beltBridgeId) {
      // 对于有多个输入端口的建筑（如汇流器），需要尝试所有可能的输入方向
      final building = portInfo.building;
      final inputPorts = building.inputPorts;
      final rot = building.rotation;
      final gw = building.building.gridWidth;
      final gh = building.building.gridHeight;
      final inputDirections = <String>[];
      for (final port in inputPorts) {
        final portGrid =
            port.gridPosition(building.gridX, building.gridY, gw, gh, rotation: rot);
        final px = portGrid.dx.round();
        final py = portGrid.dy.round();
        if (px == end.dx.round() && py == end.dy.round()) {
          inputDirections.add(_rotateDirection(port.definition.direction, rot));
        }
      }

      if (inputDirections.length <= 1) {
        // 单输入端口：使用原逻辑
        final D = portInfo.worldDirection;
        final dirOffset = switch (D) {
          'up' => const Offset(0, -1),
          'down' => const Offset(0, 1),
          'left' => const Offset(-1, 0),
          'right' => const Offset(1, 0),
          _ => const Offset(0, 0),
        };

        if (dirOffset != const Offset(0, 0)) {
          final penultimate = end + dirOffset;
          final penultimateKey =
              '${penultimate.dx.toInt()}_${penultimate.dy.toInt()}';

          if (blocked.contains(penultimateKey) && penultimateKey != startKey) {
            return null;
          }

          final tempBlocked = Set<String>.from(blocked)..add(endKey);
          final subPath = _findPath(start, penultimate, tempBlocked,
              verticalFirst: verticalFirst);
          if (subPath == null) return null;

          return _deduplicatePath([...subPath, end]);
        }
      } else {
        // 多个输入方向：按 start 相对于 end 的方向排序，优先尝试最接近的方向。
        // 否则固定按端口定义顺序（left/up/right）会始终优先连接到左边输入端口，
        // 导致从上方/右方创建传送带时被错误吸附到左边。
        final sxDiff = start.dx - end.dx;
        final syDiff = start.dy - end.dy;
        Offset dirOffsetOf(String dir) => switch (dir) {
          'up' => const Offset(0, -1),
          'down' => const Offset(0, 1),
          'left' => const Offset(-1, 0),
          'right' => const Offset(1, 0),
          _ => const Offset(0, 0),
        };
        inputDirections.sort((a, b) {
          final aOff = dirOffsetOf(a);
          final bOff = dirOffsetOf(b);
          // 点积越大，表示该输入方向越接近 start 相对于 end 的方向
          final aDot = aOff.dx * sxDiff + aOff.dy * syDiff;
          final bDot = bOff.dx * sxDiff + bOff.dy * syDiff;
          return bDot.compareTo(aDot); // 降序，点积大的优先
        });

        for (final D in inputDirections) {
          final dirOffset = dirOffsetOf(D);
          if (dirOffset == const Offset(0, 0)) continue;

          final penultimate = end + dirOffset;
          final penultimateKey =
              '${penultimate.dx.toInt()}_${penultimate.dy.toInt()}';

          if (blocked.contains(penultimateKey) && penultimateKey != startKey) {
            continue;
          }

          final tempBlocked = Set<String>.from(blocked)..add(endKey);
          final subPath = _findPath(start, penultimate, tempBlocked,
              verticalFirst: verticalFirst);
          if (subPath != null) {
            return _deduplicatePath([...subPath, end]);
          }
        }
        return null;
      }
    }

    // 仅在创建第一段时（即 anchors.length <= 1），才施加起始端口物理方向的约束，之后的中继锚点寻路自由
    final activeDirection =
        (anchors.length <= 1) ? _startingPortDirection : null;
    final allowedDirections =
        (anchors.length <= 1) ? _startingPortAllowedDirections : null;

    // 如果有端口方向约束，优先尝试按端口方向走
    final momentumPath = _calculateMomentumPath(start, end,
        verticalFirst: verticalFirst, startingDirection: activeDirection);
    bool momentumValid = true;
    for (final cell in momentumPath) {
      final key = '${cell.dx.toInt()}_${cell.dy.toInt()}';
      if (blocked.contains(key) && key != startKey) {
        momentumValid = false;
        break;
      }
    }
    // 验证首段方向是否在允许集合内（如分流器禁止往输入端down方向）
    if (momentumValid && allowedDirections != null && momentumPath.length >= 2) {
      final firstStepDir = _directionBetween(momentumPath[0], momentumPath[1]);
      if (firstStepDir != null && !allowedDirections.contains(firstStepDir)) {
        momentumValid = false;
      }
    }
    // 验证 momentum path 在物流桥格子处是否保持直线
    if (momentumValid && !_isPathValidAtBridges(momentumPath)) {
      momentumValid = false;
    }
    // 验证 momentum path 不与现有传送带平行重叠，且在交叉点处保持直线
    if (momentumValid && !_isPathValidAtBeltCrossings(momentumPath)) {
      momentumValid = false;
    }
    if (momentumValid) return _deduplicatePath(momentumPath);

    final bfsPath = _findPathBFS(start, end, blocked,
        firstStepDirection: activeDirection,
        allowedDirections: allowedDirections);
    return bfsPath != null ? _deduplicatePath(bfsPath) : null;
  }

  List<Offset> _calculateMomentumPath(Offset start, Offset end,
      {bool verticalFirst = false, String? startingDirection}) {
    final sx = start.dx.toInt();
    final sy = start.dy.toInt();
    final ex = end.dx.toInt();
    final ey = end.dy.toInt();

    if (sx == ex && sy == ey) return [start];

    final path = <Offset>[];
    int cx = sx;
    int cy = sy;

    if (startingDirection != null && (cx != ex || cy != ey)) {
      path.add(Offset(cx.toDouble(), cy.toDouble()));
      switch (startingDirection) {
        case 'up':
          cy -= 1;
          break;
        case 'down':
          cy += 1;
          break;
        case 'left':
          cx -= 1;
          break;
        case 'right':
          cx += 1;
          break;
      }
      if (cx == ex && cy == ey) {
        path.add(Offset(ex.toDouble(), ey.toDouble()));
        return path;
      }
      path.add(Offset(cx.toDouble(), cy.toDouble()));
      // 继续从新位置开始走剩余路径
    }

    // 从当前位置用原有逻辑走到终点
    if (verticalFirst) {
      if (cy != ey) {
        final dy = ey > cy ? 1 : -1;
        for (int y = cy; y != ey; y += dy) {
          if (path.isEmpty ||
              path.last.dx != cx.toDouble() ||
              path.last.dy != y.toDouble()) {
            path.add(Offset(cx.toDouble(), y.toDouble()));
          }
        }
      }
      if (cx != ex) {
        final dx = ex > cx ? 1 : -1;
        for (int x = cx; x != ex; x += dx) {
          if (path.isEmpty ||
              path.last.dx != x.toDouble() ||
              path.last.dy != ey.toDouble()) {
            path.add(Offset(x.toDouble(), ey.toDouble()));
          }
        }
      }
    } else {
      if (cx != ex) {
        final dx = ex > cx ? 1 : -1;
        for (int x = cx; x != ex; x += dx) {
          if (path.isEmpty ||
              path.last.dx != x.toDouble() ||
              path.last.dy != cy.toDouble()) {
            path.add(Offset(x.toDouble(), cy.toDouble()));
          }
        }
      }
      if (cy != ey) {
        final dy = ey > cy ? 1 : -1;
        for (int y = cy; y != ey; y += dy) {
          if (path.isEmpty ||
              path.last.dx != ex.toDouble() ||
              path.last.dy != y.toDouble()) {
            path.add(Offset(ex.toDouble(), y.toDouble()));
          }
        }
      }
    }

    path.add(Offset(ex.toDouble(), ey.toDouble()));
    return path;
  }

  List<Offset>? _findPathBFS(Offset start, Offset end, Set<String> blocked,
      {String? firstStepDirection, Set<String>? allowedDirections}) {
    final startKey = '${start.dx.toInt()}_${start.dy.toInt()}';
    final endKey = '${end.dx.toInt()}_${end.dy.toInt()}';

    if (startKey == endKey) return [start];
    if (blocked.contains(endKey)) return null;

    // 0=up [0,-1], 1=right [1,0], 2=down [0,1], 3=left [-1,0]
    const dirOffsets = [
      [0, -1], // 0: up
      [1, 0], // 1: right
      [0, 1], // 2: down
      [-1, 0], // 3: left
    ];

    int? dirNameToIndex(String? name) => switch (name) {
          'up' => 0,
          'right' => 1,
          'down' => 2,
          'left' => 3,
          _ => null,
        };

    final queue = <_BFSNode>[];
    // 在物流桥格子处，key 包含方向信息以允许不同方向到达同一格子
    final visited = <String, (String?, Offset?)>{};
    final startVisitKey = startKey;
    visited[startVisitKey] = (null, null);
    queue.add(_BFSNode(start.dx.toInt(), start.dy.toInt(), -1));

    int searched = 0;
    while (queue.isNotEmpty && searched < 5000) {
      final node = queue.removeAt(0);
      final nodeKey = '${node.x}_${node.y}';
      searched++;

      if (nodeKey == endKey) {
        // 回溯路径
        final path = <Offset>[];
        final endCellPos = Offset(node.x.toDouble(), node.y.toDouble());
        final endIsBridge = _findBeltBridgeAtCell(endCellPos) != null;
        final endBeltDir = endIsBridge
            ? null
            : _getCrossingBeltDirectionAtCell(endCellPos);
        final endUseDirKey = node.incomingDir >= 0 &&
            (endIsBridge || endBeltDir != null);
        String? vKey = endUseDirKey
            ? '${node.x}_${node.y}_${node.incomingDir}'
            : nodeKey;
        while (vKey != null) {
          final entry = visited[vKey];
          if (entry == null) break;
          final parts = vKey.split('_');
          path.add(Offset(double.parse(parts[0]), double.parse(parts[1])));
          final parentKey = entry.$1;
          vKey = parentKey;
        }
        return path.reversed.toList();
      }

      List<int> allowedDirIndices;
      if (nodeKey == startKey && allowedDirections != null) {
        // 优先使用多方向允许集合（如分流器允许 up/left/right，禁止 down）
        allowedDirIndices = allowedDirections
            .map((d) => dirNameToIndex(d))
            .whereType<int>()
            .toList();
        if (allowedDirIndices.isEmpty) allowedDirIndices = [0, 1, 2, 3];
      } else if (nodeKey == startKey && firstStepDirection != null) {
        final idx = dirNameToIndex(firstStepDirection);
        allowedDirIndices = idx != null ? [idx] : [0, 1, 2, 3];
      } else if (node.incomingDir >= 0) {
        final cellPos = Offset(node.x.toDouble(), node.y.toDouble());
        final isBridge = _findBeltBridgeAtCell(cellPos) != null;
        if (isBridge) {
          // 物流桥格子：只允许沿入方向直线通过
          allowedDirIndices = [node.incomingDir];
        } else {
          final beltDir = _getCrossingBeltDirectionAtCell(cellPos);
          if (beltDir != null) {
            // 传送带交叉点：只允许沿入方向直线通过（不能转弯）
            allowedDirIndices = [node.incomingDir];
          } else {
            allowedDirIndices = [0, 1, 2, 3];
          }
        }
      } else {
        allowedDirIndices = [0, 1, 2, 3];
      }

      for (final dirIdx in allowedDirIndices) {
        final d = dirOffsets[dirIdx];
        final nx = node.x + d[0];
        final ny = node.y + d[1];
        final nKey = '${nx}_$ny';
        if (blocked.contains(nKey) && nKey != startKey) continue;

        final neighborPos = Offset(nx.toDouble(), ny.toDouble());
        final isNeighborBridge = _findBeltBridgeAtCell(neighborPos) != null;

        // 检查是否与现有传送带平行重叠
        // 终点格子若为合并候选（传送带起点）则允许平行方向（合并连接）
        final isEndCell = nKey == endKey;
        if (!isNeighborBridge) {
          final neighborBeltDir =
              _getCrossingBeltDirectionAtCell(neighborPos);
          if (neighborBeltDir != null) {
            final (beltDx, _) = neighborBeltDir;
            final isNewDirVertical = d[0] == 0;
            final isBeltDirVertical = beltDx == 0;
            if (isNewDirVertical == isBeltDirVertical) {
              // 平行重叠
              if (isEndCell && _isMergeCandidateCell(neighborPos)) {
                // 终点是合并候选（传送带起点）：允许
              } else {
                continue; // 阻止
              }
            }
          }
        }

        // 物流桥或传送带交叉点：visited key 包含方向信息
        final neighborBeltDirForVisit = isNeighborBridge
            ? null
            : _getCrossingBeltDirectionAtCell(neighborPos);
        final useDirVisitKey =
            isNeighborBridge || neighborBeltDirForVisit != null;
        final visitKey =
            useDirVisitKey ? '${nx}_${ny}_$dirIdx' : nKey;

        if (visited.containsKey(visitKey)) continue;

        // 父节点的 visit key
        final parentCellPos =
            Offset(node.x.toDouble(), node.y.toDouble());
        final parentIsBridge =
            _findBeltBridgeAtCell(parentCellPos) != null;
        final parentBeltDir = parentIsBridge
            ? null
            : _getCrossingBeltDirectionAtCell(parentCellPos);
        final parentUseDirKey =
            node.incomingDir >= 0 &&
                (parentIsBridge || parentBeltDir != null);
        final parentVisitKey = parentUseDirKey
            ? '${node.x}_${node.y}_${node.incomingDir}'
            : nodeKey;

        visited[visitKey] =
            (parentVisitKey, Offset(node.x.toDouble(), node.y.toDouble()));
        queue.add(_BFSNode(nx, ny, dirIdx));
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

  final int incomingDir;
  _BFSNode(this.x, this.y, this.incomingDir);
}
