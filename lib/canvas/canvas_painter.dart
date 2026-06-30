import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/building.dart';
import '../models/recipe.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../AIC/equipment.dart';
import 'grid_painter.dart';
import 'building_renderer.dart';
import 'conveyor_create_mode_hud.dart';
import 'canvas_utils.dart';

class EditorPainter extends CustomPainter {
  final int repaintTrigger;
  final ProjectState project;
  final DataLoader dataLoader;
  final double cellSize;
  final Building? placingBuilding;
  final int placingRotation;
  final Offset? mouseGridPos;
  final PlacedBuilding? hoveredBuilding;
  final bool conveyorMode;
  final List<Offset> conveyorConfirmedPath;
  final List<Offset>? conveyorPreviewPath;
  final Set<String>? conveyorPreviewOccupied;
  final bool conveyorPathInvalid;
  final Offset? conveyorForkCell;
  final bool conveyorHasCommittedPath;
  final String? conveyorIncomingDirection;
  final List<Offset>? previewContextExtension;
  final List<Offset> previewBridgeCells;
  final double displayScale;
  final double displayOffsetX;
  final double displayOffsetY;
  final double displayAngle;
  final Map<String, Map<String, bool>> portConnectionsCache;
  final bool isLongPressing;
  final Offset? longPressScreenPos;
  final double longPressProgress;
  final PlacedBuilding? movingBuilding;
  final int movingRotation;
  final Offset? bridgeMoveHiddenCell;
  final AnimationController beltArrowController;

  // 预渲染缓存: key = "buildingId_rotation_detailLevel_portsHash" -> Picture
  static final Map<String, ui.Picture> _pictureCache = {};
  static const int _maxCacheSize = 200;

  /// 清除所有静态渲染缓存
  static void clearPictureCache() {
    _pictureCache.clear();
  }

  EditorPainter({
    required this.repaintTrigger,
    required this.project,
    required this.dataLoader,
    required this.cellSize,
    this.placingBuilding,
    this.placingRotation = 0,
    this.mouseGridPos,
    this.hoveredBuilding,
    this.conveyorMode = false,
    this.conveyorConfirmedPath = const [],
    this.conveyorPreviewPath,
    this.conveyorPreviewOccupied,
    this.conveyorPathInvalid = false,
    this.conveyorForkCell,
    this.conveyorHasCommittedPath = false,
    this.conveyorIncomingDirection,
    this.previewContextExtension,
    this.previewBridgeCells = const [],
    required this.displayScale,
    required this.displayOffsetX,
    required this.displayOffsetY,
    required this.displayAngle,
    required this.portConnectionsCache,
    this.isLongPressing = false,
    this.longPressScreenPos,
    this.longPressProgress = 0.0,
    this.movingBuilding,
    this.movingRotation = 0,
    this.bridgeMoveHiddenCell,
    required this.beltArrowController,
  }) : super(repaint: Listenable.merge([beltArrowController]));

  @override
  void paint(Canvas canvas, Size size) {
    // 计算可见世界区域（视口裁剪用）
    final viewport = _computeViewport(size);

    final gridPainter = GridPainter(
      offsetX: displayOffsetX,
      offsetY: displayOffsetY,
      scale: displayScale,
      cellSize: cellSize,
      rotation: displayAngle,
    );
    gridPainter.paint(canvas, size);

    canvas.save();
    if (displayAngle != 0) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(displayAngle);
      canvas.translate(-center.dx, -center.dy);
    }
    canvas.translate(-displayOffsetX, -displayOffsetY);
    canvas.scale(displayScale);

    // LOD: 根据缩放级别决定渲染细节
    final detailLevel = displayScale < 0.35 ? 0 : (displayScale < 0.5 ? 1 : 2);

    // 获取当前正在绘制的新传送带的分叉点（用于旧道动态裁剪）
    // 使用 anchors.first（用户实际点击的位置），而非路径的 first
    // 创建过程中不打断原传送带的物品动画：不裁剪原传送带、不清空物品、不渲染已确认段预览
    const hasConfirmedForkHandoff = false;
    const Offset? startCell = null;

    // 构建 fullPathContext（已确认段 + 实时段的完整路径）
    // 不论路径有效还是无效都构建上下文，这样即使渲染红色错误预览时，转角处的纹理也能计算正确
    List<Offset>? fullPathContext;
    int previewStartIndex = conveyorConfirmedPath.length;

    if (conveyorPreviewPath != null && conveyorPreviewPath!.isNotEmpty) {
      if (conveyorConfirmedPath.isNotEmpty) {
        fullPathContext = [...conveyorConfirmedPath, ...conveyorPreviewPath!];
        // 去重：已确认段末尾和实时段开头可能重叠
        if (fullPathContext.length >= 2 &&
            fullPathContext[conveyorConfirmedPath.length - 1].dx ==
                fullPathContext[conveyorConfirmedPath.length].dx &&
            fullPathContext[conveyorConfirmedPath.length - 1].dy ==
                fullPathContext[conveyorConfirmedPath.length].dy) {
          fullPathContext.removeAt(conveyorConfirmedPath.length);
          previewStartIndex = conveyorConfirmedPath.length - 1;
        }
      } else {
        // 第一段创建时 confirmedPath 为空，仅用 previewPath 构建上下文
        fullPathContext = [...conveyorPreviewPath!];
        previewStartIndex = 0;
      }
    }

    // 追加转角上下文扩展（合并目标的路径，仅用于转角检测，不渲染为蓝色预览）
    if (previewContextExtension != null &&
        previewContextExtension!.isNotEmpty &&
        fullPathContext != null) {
      fullPathContext.addAll(previewContextExtension!);
    }

    final previewItemSegments = <ConveyorItemSegment>[];
    if (conveyorMode &&
        !conveyorHasCommittedPath &&
        !conveyorPathInvalid &&
        fullPathContext != null &&
        fullPathContext.isNotEmpty) {
      previewItemSegments.addAll(_previewItemSegmentsForPath(
        fullPathContext,
        shouldProjectForkSource: hasConfirmedForkHandoff,
        forkProjectionLimit: previewStartIndex + 1,
      ));
    }

    final livePreviewRenderPath = conveyorPreviewPath;
    final livePreviewContextStartIndex = previewStartIndex;
    final hiddenPreviewTerminal =
        conveyorPreviewPath != null && conveyorPreviewPath!.length > 1
            ? conveyorPreviewPath!.first
            : null;

    // 物流桥移动时，隐藏其下方传送带格子的背景
    final bridgeHiddenCells = bridgeMoveHiddenCell != null
        ? <Offset>{bridgeMoveHiddenCell!}
        : null;

    // 检查分叉点是否在物流桥上：如果是，则不应裁剪只是穿过物流桥的传送带
    // （传送带从物流桥开始创建，并非从穿过物流桥的传送带分叉）
    bool isForkAtBridge = false;
    if (startCell != null) {
      final sx = startCell.dx.toInt();
      final sy = startCell.dy.toInt();
      for (final pb in project.buildings) {
        if (!pb.isBeltBridge) continue;
        final bx = pb.effectiveGridX.toInt();
        final by = pb.effectiveGridY.toInt();
        if (sx >= bx && sx < bx + pb.effectiveWidth &&
            sy >= by && sy < by + pb.effectiveHeight) {
          isForkAtBridge = true;
          break;
        }
      }
    }

    // 调试：视口与裁剪统计（有裁剪时才输出，且每2秒最多一次）
    for (final belt in project.conveyors) {
      // 动态裁剪：如果当前正在绘制且起点在旧传送带上，裁剪分叉点之前的部分
      List<Offset> renderPath = belt.path;
      int forkIdx = -1;
      final hidesTerminalCell = hiddenPreviewTerminal != null &&
          belt.path.isNotEmpty &&
          _sameCell(belt.path.last, hiddenPreviewTerminal);
      if (startCell != null) {
        for (int i = 0; i < belt.path.length; i++) {
          if (belt.path[i].dx == startCell.dx &&
              belt.path[i].dy == startCell.dy) {
            forkIdx = i;
            break;
          }
        }
        // 如果分叉点在物流桥上，且分叉点在传送带路径中间（非终点），
        // 则不裁剪该传送带——传送带只是穿过物流桥，并非从该传送带分叉
        if (isForkAtBridge && forkIdx >= 0 && forkIdx < belt.path.length - 1) {
          forkIdx = -1;
        }
        if (forkIdx >= 0 && forkIdx < belt.path.length - 1) {
          // 分叉点在中间：裁剪分叉点之后的路径段
          renderPath = belt.path.sublist(forkIdx + 1);
        } else if (forkIdx >= 0 && forkIdx >= belt.path.length - 1) {
          // 分叉点在末尾或之后：整条旧道被替代改为保留原样
          // 当用户从传送带末尾格开始延伸时（forkIdx == path.length - 1），
          // 传送带尚未被实际拆分，应继续渲染原传送带及其物品
          renderPath = belt.path;
        } else {
          // 没有分叉：继续使用 renderPath
        }
      }
      if (hidesTerminalCell) {
        // 不裁剪路径：保留完整路径以便物品能自然传输到终点格。
        // 终点格的背景由预览覆盖，通过 hideTerminalBackground 标志
        // 在渲染器中跳过背景绘制，但物品仍正常渲染。
      }

      if (renderPath.isEmpty) {
        continue;
      }
      final visible = _isPathVisible(renderPath, viewport);
      if (!visible) {
        continue;
      }
      final effectiveItemId =
          belt.itemId.isNotEmpty ? belt.itemId : belt.lastItemId;
      final item = dataLoader.getItem(effectiveItemId);
      // 残留物品：当 lastItemFillCount > 0 且 lastItemId 与当前 itemId 不同时
      final lastItem = belt.lastItemFillCount > 0 &&
              belt.lastItemId.isNotEmpty &&
              belt.lastItemId != belt.itemId
          ? dataLoader.getItem(belt.lastItemId)
          : null;
      // 如果路径被裁剪，创建临时 ConveyorBelt 用于渲染
      if (!identical(renderPath, belt.path)) {
        // 单格下游：从旧传送带推断原始方向
        String? forcedDir;
        // 下游首格的入方向：从分叉点指向下游首格
        String? incomingDir;
        if (hidesTerminalCell && renderPath.isNotEmpty) {
          final dx = belt.path.last.dx - renderPath.last.dx;
          final dy = belt.path.last.dy - renderPath.last.dy;
          if (dx > 0) {
            forcedDir = 'right';
          } else if (dx < 0) {
            forcedDir = 'left';
          } else if (dy > 0) {
            forcedDir = 'down';
          } else if (dy < 0) {
            forcedDir = 'up';
          }
          incomingDir = belt.incomingDirection;
        } else if (forkIdx >= 0 && forkIdx + 1 < belt.path.length) {
          final dx = belt.path[forkIdx + 1].dx - belt.path[forkIdx].dx;
          final dy = belt.path[forkIdx + 1].dy - belt.path[forkIdx].dy;
          if (dx > 0) {
            incomingDir = 'right';
          } else if (dx < 0) {
            incomingDir = 'left';
          } else if (dy > 0) {
            incomingDir = 'down';
          } else if (dy < 0) {
            incomingDir = 'up';
          }
          if (renderPath.length == 1) {
            // 如果仅剩最后一格，且原传送带定义了 forcedDirection，则保留原转向
            forcedDir = belt.forcedDirection ?? incomingDir;
          }
        }
        final clippedBelt = ConveyorBelt(
          id: belt.id,
          path: renderPath,
          itemId: belt.itemId,
          lastItemId: belt.lastItemId,
          itemSegments: hidesTerminalCell
              ? belt.clippedItemSegments(0, renderPath.length)
              : forkIdx >= 0
                  ? belt.clippedItemSegments(forkIdx + 1, belt.path.length)
                  : belt.shiftedItemSegments(0),
          itemFillCount: hidesTerminalCell
              ? math.min(belt.itemFillCount, renderPath.length)
              : forkIdx >= 0
                  ? math.max(0, belt.itemFillCount - (forkIdx + 1))
                  : belt.itemFillCount,
          itemDrainCount: hidesTerminalCell
              ? math.min(belt.itemDrainCount, renderPath.length)
              : forkIdx >= 0
                  ? math.max(0, belt.itemDrainCount - (forkIdx + 1))
                  : belt.itemDrainCount,
          isBlocked: belt.isBlocked,
          forcedDirection: forcedDir,
          incomingDirection: incomingDir,
          phaseOffset: belt.phaseOffset,
          lastItemFillCount: hidesTerminalCell
              ? math.min(belt.lastItemFillCount, renderPath.length)
              : belt.lastItemFillCount > 0 && forkIdx >= 0
                  ? math.max(0, belt.lastItemFillCount - (forkIdx + 1))
                  : belt.lastItemFillCount,
          lastItemDrainCount: hidesTerminalCell
              ? math.min(belt.lastItemDrainCount, renderPath.length)
              : belt.lastItemFillCount > 0 && forkIdx >= 0
                  ? math.max(0, belt.lastItemDrainCount - (forkIdx + 1))
                  : belt.lastItemDrainCount,
          deadEndFreezeProgress: belt.deadEndFreezeProgress,
          lastItemFreezeProgress: belt.lastItemFreezeProgress,
        );
        TransportBeltRenderer.renderConveyorPath(
            canvas, clippedBelt, item, cellSize, project.buildings,
            detailLevel: detailLevel,
            arrowProgress:
                clippedBelt.animationProgress(beltArrowController.value),
            lastItem: lastItem,
            allItems: dataLoader.items,
            hiddenBackgroundCells: bridgeHiddenCells,
            conveyors: project.conveyors);
      } else {
        TransportBeltRenderer.renderConveyorPath(
            canvas, belt, item, cellSize, project.buildings,
            detailLevel: detailLevel,
            arrowProgress: belt.animationProgress(beltArrowController.value),
            lastItem: lastItem,
            allItems: dataLoader.items,
            hideTerminalBackground: hidesTerminalCell,
            hiddenBackgroundCells: bridgeHiddenCells,
            conveyors: project.conveyors);
      }
    }

    // Build previewSet for checking which ports are currently covered by preview path
    final Set<Offset> previewSet = {};
    if (conveyorMode) {
      if (!conveyorHasCommittedPath && conveyorConfirmedPath.isNotEmpty) {
        previewSet.addAll(conveyorConfirmedPath);
      }
      if (livePreviewRenderPath != null &&
          livePreviewRenderPath.isNotEmpty &&
          (!conveyorHasCommittedPath || conveyorPreviewPath!.length > 1)) {
        previewSet.addAll(livePreviewRenderPath);
      }
    }

    // 已确认段不单独渲染预览，原传送带在创建过程中保持完整渲染，动画不中断

    // 实时段根据有效/无效状态分别渲染 - (放到建筑下方渲染)
    if (conveyorPathInvalid) {
      // 无效状态：仅实时段标红，但是同样传入 fullPathContext 使得转弯样式能与已确认段进行平滑衔接
      if (livePreviewRenderPath != null &&
          livePreviewRenderPath.isNotEmpty &&
          (!conveyorHasCommittedPath || conveyorPreviewPath!.length > 1)) {
        TransportBeltRenderer.renderPreviewPath(
          canvas,
          livePreviewRenderPath,
          cellSize,
          <String>{},
          project.buildings,
          isInvalid: true,
          fullPathContext: fullPathContext,
          contextStartIndex: livePreviewContextStartIndex,
          incomingDirection: conveyorIncomingDirection,
          arrowProgress: beltArrowController.value,
          itemSegments: previewItemSegments,
          allItems: dataLoader.items,
          opaqueItems: hasConfirmedForkHandoff,
          itemArrowProgress: 0.5,
        );
      }
    } else {
      // 有效状态：实时段为蓝色预览
      if (livePreviewRenderPath != null &&
          livePreviewRenderPath.isNotEmpty &&
          (!conveyorHasCommittedPath || conveyorPreviewPath!.length > 1)) {
        TransportBeltRenderer.renderPreviewPath(
          canvas,
          livePreviewRenderPath,
          cellSize,
          <String>{},
          project.buildings,
          fullPathContext: fullPathContext,
          contextStartIndex: livePreviewContextStartIndex,
          incomingDirection: conveyorIncomingDirection,
          arrowProgress: beltArrowController.value,
          itemSegments: previewItemSegments,
          allItems: dataLoader.items,
          opaqueItems: hasConfirmedForkHandoff,
          itemArrowProgress: 0.5,
        );
      } else if (conveyorMode &&
          mouseGridPos != null &&
          conveyorConfirmedPath.isEmpty) {
        // 传送带处于尚未锚定的预备状态且当前空节点鼠标浮动时，高亮选中指示格
        TransportBeltRenderer.renderHoverHighlight(
            canvas, mouseGridPos!, cellSize);
      }
    }

    // 渲染物流桥预览：在传送带交叉点显示灰色半透明物流桥
    if (conveyorMode && previewBridgeCells.isNotEmpty && !conveyorPathInvalid) {
      final bridgeBuilding = dataLoader.getBuilding('belt_bridge_1x1');
      if (bridgeBuilding != null) {
        for (final cell in previewBridgeCells) {
          LogisticsUnitRenderer.renderPlaceholder(
            canvas,
            bridgeBuilding,
            cell.dx - (bridgeBuilding.gridWidth ~/ 2).toDouble(),
            cell.dy - (bridgeBuilding.gridHeight ~/ 2).toDouble(),
            cellSize,
            0.6,
            rotation: 0,
            previewColorOverride: const Color(0xFF3D3D3D),
          );
        }
      }
    }

    for (final pb in project.buildings) {
      if (pb == movingBuilding) continue;
      if (!_isBuildingVisible(pb, viewport)) continue;

      // Compute combined port states (actual + preview connections)
      final combinedPorts = <String, int>{};
      final actualConns = portConnectionsCache[pb.id] ?? <String, bool>{};
      actualConns.forEach((key, isConnected) {
        if (isConnected) {
          combinedPorts[key] = 1; // 1 = connected yellow
        }
      });

      if (conveyorMode) {
        bool containsGrid(Offset portGrid) {
          final px = portGrid.dx.round();
          final py = portGrid.dy.round();
          for (final cell in previewSet) {
            if (cell.dx.round() == px && cell.dy.round() == py) {
              return true;
            }
          }
          return false;
        }

        for (int i = 0; i < pb.inputPorts.length; i++) {
          final port = pb.inputPorts[i];
          final portGrid = port.gridPosition(
            pb.gridX,
            pb.gridY,
            pb.building.gridWidth,
            pb.building.gridHeight,
            rotation: pb.rotation,
          );
          if (containsGrid(portGrid)) {
            combinedPorts['input_$i'] = 2; // 2 = preview blue
          }
        }
        for (int i = 0; i < pb.outputPorts.length; i++) {
          final port = pb.outputPorts[i];
          final portGrid = port.gridPosition(
            pb.gridX,
            pb.gridY,
            pb.building.gridWidth,
            pb.building.gridHeight,
            rotation: pb.rotation,
          );
          if (containsGrid(portGrid)) {
            combinedPorts['output_$i'] = 2; // 2 = preview blue
          }
        }
      }

      // 预渲染缓存 key
      final sortedEntries = combinedPorts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final portsHash =
          sortedEntries.map((e) => '${e.key}:${e.value}').join(',');
      final assetVersion = LogisticsUnitRenderer.isLogisticsUnit(pb.building.id)
          ? LogisticsUnitRenderer.cacheVersion
          : 0;
      final cacheKey =
          '${pb.building.id}_${pb.rotation}_${detailLevel}_${assetVersion}_$portsHash';

      final x = pb.gridX * cellSize;
      final y = pb.gridY * cellSize;
      final w = pb.building.gridWidth * cellSize;
      final h = pb.building.gridHeight * cellSize;

      ui.Picture? cachedPicture = _pictureCache[cacheKey];
      if (cachedPicture == null) {
        final recorder = ui.PictureRecorder();
        final recordCanvas = Canvas(recorder);
        recordCanvas.translate(w / 2, h / 2);
        recordCanvas.rotate(pb.rotation * math.pi / 2);
        recordCanvas.translate(-w / 2, -h / 2);

        _renderBuildingStatic(
            recordCanvas, pb, cellSize, detailLevel, combinedPorts);

        cachedPicture = recorder.endRecording();
        if (_pictureCache.length >= _maxCacheSize) {
          _pictureCache.remove(_pictureCache.keys.first);
        }
        _pictureCache[cacheKey] = cachedPicture;
      }

      canvas.save();
      canvas.translate(x, y);
      canvas.drawPicture(cachedPicture);
      canvas.restore();

      // Logo 单独绘制（不缓存），始终不随设备/画布旋转
      if (pb.building.id == RefiningUnitConfig.id &&
          RefiningUnitRenderer.isReady) {
        RefiningUnitRenderer.renderLogo(
          canvas,
          x,
          y,
          w,
          h,
          pb.rotation,
          displayAngle,
        );
      } else if ((pb.building.id == DepotLoaderConfig.id ||
              pb.building.id == DepotUnloaderConfig.id) &&
          DepotAccessRenderer.isReady) {
        DepotAccessRenderer.renderLogo(
          canvas,
          x,
          y,
          w,
          h,
          pb.building.id,
          pb.rotation,
          displayAngle,
        );
      }
    }

    if (placingBuilding != null && mouseGridPos != null) {
      final cx =
          mouseGridPos!.dx - (placingBuilding!.gridWidth ~/ 2).toDouble();
      final cy =
          mouseGridPos!.dy - (placingBuilding!.gridHeight ~/ 2).toDouble();
      final isBlocked =
          _isPreviewBlocked(placingBuilding!, cx, cy, placingRotation);

      if (placingBuilding!.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas,
          placingBuilding!,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: placingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (placingBuilding!.id == DepotLoaderConfig.id ||
          placingBuilding!.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas,
          placingBuilding!,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: placingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (LogisticsUnitRenderer.isLogisticsUnit(placingBuilding!.id)) {
        LogisticsUnitRenderer.renderPlaceholder(
          canvas,
          placingBuilding!,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: placingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas,
          placingBuilding!,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: placingRotation,
          isBlocked: isBlocked,
        );
      }

      // 碰撞时绘制阻拦对象红色叠加
      if (isBlocked) {
        _drawBlockedOverlays(canvas, placingBuilding!, cx, cy, placingRotation);
      }
    }

    // 移动中的建筑预览
    if (movingBuilding != null && mouseGridPos != null) {
      final mb = movingBuilding!;
      final cx = mouseGridPos!.dx - (mb.building.gridWidth ~/ 2).toDouble();
      final cy = mouseGridPos!.dy - (mb.building.gridHeight ~/ 2).toDouble();
      final isBlocked = _isPreviewBlocked(mb.building, cx, cy, movingRotation);

      if (mb.building.id == RefiningUnitConfig.id) {
        RefiningUnitRenderer.renderPlaceholder(
          canvas,
          mb.building,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: movingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (mb.building.id == DepotLoaderConfig.id ||
          mb.building.id == DepotUnloaderConfig.id) {
        DepotAccessRenderer.renderPlaceholder(
          canvas,
          mb.building,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: movingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else if (LogisticsUnitRenderer.isLogisticsUnit(mb.building.id)) {
        LogisticsUnitRenderer.renderPlaceholder(
          canvas,
          mb.building,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: movingRotation,
          isBlocked: isBlocked,
          canvasRotation: displayAngle,
        );
      } else {
        BuildingRenderer.renderPlaceholder(
          canvas,
          mb.building,
          cx,
          cy,
          cellSize,
          0.6,
          rotation: movingRotation,
          isBlocked: isBlocked,
        );
      }

      // 碰撞时绘制阻拦对象红色叠加
      if (isBlocked) {
        _drawBlockedOverlays(canvas, mb.building, cx, cy, movingRotation);
      }
    }

    // 悬停高亮白框
    if (hoveredBuilding != null &&
        placingBuilding == null &&
        movingBuilding == null) {
      final hb = hoveredBuilding!;
      final hx = hb.gridX * cellSize;
      final hy = hb.gridY * cellSize;
      final hw = hb.building.gridWidth * cellSize;
      final hh = hb.building.gridHeight * cellSize;

      canvas.save();
      canvas.translate(hx + hw / 2, hy + hh / 2);
      canvas.rotate(hb.rotation * math.pi / 2);
      canvas.translate(-hw / 2, -hh / 2);

      final highlightPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(0, 0, hw, hh), highlightPaint);

      canvas.restore();
    }

    canvas.restore();

    // 长按圆形进度条（屏幕空间绘制，进度超过阈值才显示，避免快速点击闪烁）
    if (isLongPressing &&
        longPressScreenPos != null &&
        longPressProgress > 0.15) {
      final center = longPressScreenPos!;
      const radius = 24.0;
      const strokeW = 4.0;

      // 背景圆环
      final bgPaint = Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;
      canvas.drawCircle(center, radius, bgPaint);

      // 蓝色填充弧（顺时针，从顶部开始）
      final progressPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // 12点方向
      final sweepAngle = 2 * math.pi * longPressProgress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }

    if (conveyorMode) {
      final hudPhase =
          (beltArrowController.lastElapsedDuration?.inMicroseconds ?? 0) /
              beltArrowController.duration!.inMicroseconds;
      ConveyorCreateModeHudPainter.paintHud(
        canvas,
        size,
        hudPhase,
      );
    }
  }

  /// 对坐标点进行逆旋转变换（绕原点旋转 -θ）
  Offset _inverseRotate(Offset pos, double cosA, double sinA) {
    return Offset(
      pos.dx * cosA + pos.dy * sinA,
      -pos.dx * sinA + pos.dy * cosA,
    );
  }

  /// 计算可见世界坐标区域（考虑旋转的轴对齐包围盒）
  Viewport _computeViewport(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cosA = math.cos(displayAngle);
    final sinA = math.sin(displayAngle);

    // 屏幕四角逆变换到世界坐标
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final corner in corners) {
      var pos = corner;
      // 逆变换: translate(-center) → inverse-rotate → translate(center) → translate(+offset) → unscale
      pos = Offset(pos.dx - center.dx, pos.dy - center.dy);
      pos = _inverseRotate(pos, cosA, sinA);
      pos = Offset(pos.dx + center.dx, pos.dy + center.dy);
      pos = Offset(pos.dx + displayOffsetX, pos.dy + displayOffsetY);
      pos = Offset(pos.dx / displayScale, pos.dy / displayScale);

      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    return Viewport(minX, minY, maxX, maxY);
  }

  /// 判断预览建筑是否与现有建筑或传送带碰撞
  bool _isPreviewBlocked(
      Building building, double gridX, double gridY, int rotation) {
    final tempPb = PlacedBuilding(
      id: '_preview',
      building: building,
      gridX: gridX,
      gridY: gridY,
      rotation: rotation,
    );
    final bounds = tempPb.getBounds(cellSize);

    // 检测与现有建筑的碰撞
    for (final pb in project.buildings) {
      if (pb.overlaps(bounds, cellSize)) return true;
    }

    // 检测与传送带的碰撞
    final previewCells = _getGridCells(building, gridX, gridY, rotation);
    for (final belt in project.conveyors) {
      for (int i = 0; i < belt.path.length; i++) {
        if (previewCells.contains(normalizedGridCell(belt.path[i])) &&
            !canBuildingOverlapBeltCell(building, belt, i)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 获取建筑占用的网格坐标集合
  Set<Offset> _getGridCells(
      Building building, double gridX, double gridY, int rotation) {
    final cells = <Offset>{};
    // 考虑旋转后的有效尺寸
    int effW, effH;
    double effX, effY;
    if (rotation % 2 == 1) {
      effW = building.gridHeight;
      effH = building.gridWidth;
    } else {
      effW = building.gridWidth;
      effH = building.gridHeight;
    }
    effX = gridX + (building.gridWidth - effW) / 2.0;
    effY = gridY + (building.gridHeight - effH) / 2.0;

    for (int dx = 0; dx < effW; dx++) {
      for (int dy = 0; dy < effH; dy++) {
        cells.add(
            Offset((effX + dx).roundToDouble(), (effY + dy).roundToDouble()));
      }
    }
    return cells;
  }

  /// 绘制碰撞对象的红色叠加层
  void _drawBlockedOverlays(Canvas canvas, Building building, double gridX,
      double gridY, int rotation) {
    final previewCells = _getGridCells(building, gridX, gridY, rotation);
    final previewSet =
        previewCells.map((c) => '${c.dx.toInt()}_${c.dy.toInt()}').toSet();

    // 阻拦的建筑：整体变红
    for (final pb in project.buildings) {
      final tempPb = PlacedBuilding(
        id: '_temp',
        building: pb.building,
        gridX: pb.gridX,
        gridY: pb.gridY,
        rotation: pb.rotation,
      );
      final bounds = tempPb.getBounds(cellSize);
      final testPb = PlacedBuilding(
        id: '_preview',
        building: building,
        gridX: gridX,
        gridY: gridY,
        rotation: rotation,
      );
      if (!testPb.overlaps(bounds, cellSize)) continue;

      final x = pb.gridX * cellSize;
      final y = pb.gridY * cellSize;
      final w = pb.building.gridWidth * cellSize;
      final h = pb.building.gridHeight * cellSize;

      canvas.save();
      canvas.translate(x + w / 2, y + h / 2);
      canvas.rotate(pb.rotation * math.pi / 2);
      canvas.translate(-w / 2, -h / 2);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0x55FF4444),
      );
      canvas.restore();
    }

    // 阻拦的传送带：使用红色传送带预览渲染
    for (final belt in project.conveyors) {
      final blockedKeys = <String>{};
      for (int i = 0; i < belt.path.length; i++) {
        final key = gridCellKey(belt.path[i]);
        if (previewSet.contains(key) &&
            !canBuildingOverlapBeltCell(building, belt, i)) {
          blockedKeys.add(key);
        }
      }
      if (blockedKeys.isNotEmpty) {
        TransportBeltRenderer.renderBlockedBeltCells(
          canvas,
          belt.path,
          cellSize,
          blockedKeys,
          project.buildings,
          incomingDirection: belt.incomingDirection,
        );
      }
    }
  }

  /// 判断设备是否在视口内
  bool _isBuildingVisible(PlacedBuilding pb, Viewport vp) {
    final x = pb.gridX * cellSize;
    final y = pb.gridY * cellSize;
    final w = pb.building.gridWidth * cellSize;
    final h = pb.building.gridHeight * cellSize;
    // AABB 碰撞检测
    return x + w > vp.minX && x < vp.maxX && y + h > vp.minY && y < vp.maxY;
  }

  /// 判断路径是否在视口内
  bool _isPathVisible(List<Offset> path, Viewport vp) {
    if (path.isEmpty) return false;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final cell in path) {
      final x = cell.dx * cellSize;
      final y = cell.dy * cellSize;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x + cellSize > maxX) maxX = x + cellSize;
      if (y + cellSize > maxY) maxY = y + cellSize;
    }

    return maxX > vp.minX && minX < vp.maxX && maxY > vp.minY && minY < vp.maxY;
  }

  List<ConveyorItemSegment> _previewItemSegmentsForPath(
      List<Offset> contextPath,
      {required bool shouldProjectForkSource,
      required int forkProjectionLimit}) {
    if (contextPath.isEmpty) return const [];

    final segments = <ConveyorItemSegment>[];
    final maxContextEnd = contextPath.length;

    for (final belt in project.conveyors) {
      if (belt.path.isEmpty) continue;

      if (shouldProjectForkSource) {
        final forkIndex = _pathIndexOfCell(belt.path, contextPath.first);
        if (forkIndex > 0) {
          final projected = _projectForkSourceSegments(
            belt,
            forkIndex,
            math.min(forkProjectionLimit, contextPath.length),
            math.min(forkProjectionLimit, contextPath.length),
          );
          if (projected.isNotEmpty) {
            segments.addAll(projected);
            continue;
          }
        }
      }

      for (int beltStart = 0; beltStart < belt.path.length; beltStart++) {
        for (int contextStart = 0;
            contextStart < maxContextEnd;
            contextStart++) {
          if (!_sameCell(belt.path[beltStart], contextPath[contextStart])) {
            continue;
          }
          if (beltStart > 0 &&
              contextStart > 0 &&
              _sameCell(
                belt.path[beltStart - 1],
                contextPath[contextStart - 1],
              )) {
            continue;
          }

          var length = 0;
          while (beltStart + length < belt.path.length &&
              contextStart + length < maxContextEnd &&
              _sameCell(
                belt.path[beltStart + length],
                contextPath[contextStart + length],
              )) {
            length++;
          }
          if (length <= 0) continue;

          segments.addAll(
            belt
                .clippedItemSegments(
                  beltStart,
                  beltStart + length,
                  clearFreezeProgress: true,
                )
                .map((segment) => segment.shifted(contextStart))
                .where((segment) => segment.hasItems),
          );
          break;
        }
      }
    }

    segments.sort((a, b) => a.drainCount.compareTo(b.drainCount));
    return segments;
  }

  List<ConveyorItemSegment> _projectForkSourceSegments(
    ConveyorBelt belt,
    int forkIndex,
    int contextLength,
    int projectedEnd,
  ) {
    final projected = <ConveyorItemSegment>[];
    final sourceEnd = math.min(contextLength, belt.path.length);
    for (final segment in belt.clippedItemSegments(
      0,
      sourceEnd,
      clearFreezeProgress: true,
    )) {
      final fill = math
          .max(segment.fillCount, projectedEnd)
          .clamp(0, contextLength)
          .toInt();
      final drain = segment.drainCount.clamp(0, contextLength).toInt();
      if (fill <= drain) continue;
      projected.add(ConveyorItemSegment(
        itemId: segment.itemId,
        fillCount: fill,
        drainCount: drain,
      ));
    }
    return projected;
  }

  int _pathIndexOfCell(List<Offset> path, Offset cell) {
    for (int i = 0; i < path.length; i++) {
      if (_sameCell(path[i], cell)) return i;
    }
    return -1;
  }

  bool _sameCell(Offset a, Offset b) {
    return a.dx.round() == b.dx.round() && a.dy.round() == b.dy.round();
  }

  /// 渲染设备的静态部分到指定 Canvas（用于预渲染缓存）
  void _renderBuildingStatic(Canvas canvas, PlacedBuilding pb, double cellSize,
      int detailLevel, Map<String, int> portConnections) {
    Recipe? recipe;
    if (pb.activeRecipeId != null && detailLevel >= 1) {
      recipe = dataLoader.getRecipe(pb.activeRecipeId!);
    }

    if (pb.building.id == RefiningUnitConfig.id) {
      RefiningUnitRenderer.render(
        canvas, pb.building, 0, 0, cellSize, 0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0, // 静态部分不含进度条
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    } else if (pb.building.id == DepotLoaderConfig.id ||
        pb.building.id == DepotUnloaderConfig.id) {
      DepotAccessRenderer.render(
        canvas,
        pb.building,
        0,
        0,
        cellSize,
        0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0,
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    } else if (LogisticsUnitRenderer.isLogisticsUnit(pb.building.id)) {
      LogisticsUnitRenderer.render(
        canvas,
        pb.building,
        0,
        0,
        cellSize,
        0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0,
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    } else {
      BuildingRenderer.renderBuilding(
        canvas,
        pb.building,
        0,
        0,
        cellSize,
        0,
        activeRecipe: recipe,
        isBlocked: pb.isBlocked,
        productionProgress: 0,
        portConnections: portConnections,
        detailLevel: detailLevel,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EditorPainter oldDelegate) {
    return repaintTrigger != oldDelegate.repaintTrigger ||
        project != oldDelegate.project ||
        dataLoader != oldDelegate.dataLoader ||
        cellSize != oldDelegate.cellSize ||
        placingBuilding != oldDelegate.placingBuilding ||
        placingRotation != oldDelegate.placingRotation ||
        mouseGridPos != oldDelegate.mouseGridPos ||
        hoveredBuilding != oldDelegate.hoveredBuilding ||
        conveyorMode != oldDelegate.conveyorMode ||
        conveyorPathInvalid != oldDelegate.conveyorPathInvalid ||
        conveyorForkCell != oldDelegate.conveyorForkCell ||
        conveyorHasCommittedPath != oldDelegate.conveyorHasCommittedPath ||
        conveyorIncomingDirection != oldDelegate.conveyorIncomingDirection ||
        previewContextExtension != oldDelegate.previewContextExtension ||
        !_listEquals(previewBridgeCells, oldDelegate.previewBridgeCells) ||
        !_listEquals(
            conveyorConfirmedPath, oldDelegate.conveyorConfirmedPath) ||
        !_listEquals(conveyorPreviewPath, oldDelegate.conveyorPreviewPath) ||
        !_setEquals(
            conveyorPreviewOccupied, oldDelegate.conveyorPreviewOccupied) ||
        displayScale != oldDelegate.displayScale ||
        displayOffsetX != oldDelegate.displayOffsetX ||
        displayOffsetY != oldDelegate.displayOffsetY ||
        displayAngle != oldDelegate.displayAngle ||
        isLongPressing != oldDelegate.isLongPressing ||
        longPressScreenPos != oldDelegate.longPressScreenPos ||
        longPressProgress != oldDelegate.longPressProgress ||
        movingBuilding != oldDelegate.movingBuilding ||
        movingRotation != oldDelegate.movingRotation;
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _setEquals<T>(Set<T>? a, Set<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

/// 视口区域（世界坐标）
class Viewport {
  final double minX, minY, maxX, maxY;
  const Viewport(this.minX, this.minY, this.maxX, this.maxY);
}
