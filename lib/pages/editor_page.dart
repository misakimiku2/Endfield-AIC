import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../canvas/canvas_editor.dart';
import '../canvas/simulation_engine.dart';
import '../widgets/equipment_dock.dart';
import '../widgets/floating_action_buttons.dart';
import '../widgets/building_detail_dialog.dart';

class EditorPage extends StatefulWidget {
  final DataLoader dataLoader;
  final SimulationEngine simulationEngine;

  const EditorPage({
    super.key,
    required this.dataLoader,
    required this.simulationEngine,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late ProjectState _project;
  Building? _placingBuilding;
  PlacedBuilding? _selectedBuilding;
  bool _conveyorMode = false;
  final GlobalKey<CanvasEditorState> _canvasKey = GlobalKey();

  static const List<String> _dockOrder = [
    'refining_unit_3x3',
    'shredder_3x3',
    'furnace_3x3',
    'assembler_4x4',
    'depot_loader_3x1',
    'depot_unloader_3x1',
  ];

  @override
  void initState() {
    super.initState();
    _project = ProjectState();
    widget.simulationEngine.attach(_project);
    // 监听仿真引擎的 tick 结果，触发 UI 重绘
    widget.simulationEngine.addListener(_onSimTick);
    // 异步初始化计算 Isolate
    widget.simulationEngine.init().then((_) {
      // Isolate 就绪后同步当前状态
      widget.simulationEngine.attach(_project);
    });
  }

  @override
  void dispose() {
    widget.simulationEngine.removeListener(_onSimTick);
    super.dispose();
  }

  void _onSimTick() {
    setState(() {});
  }

  void _onDockBuildingSelected(Building? building) {
    setState(() {
      _placingBuilding = building;
      _conveyorMode = false;
      if (building == null) _selectedBuilding = null;
    });
  }

  void _onBuildingPlaced() {
    setState(() {
      _placingBuilding = null;
    });
  }

  void _cancelPlacement() {
    setState(() {
      _placingBuilding = null;
      _conveyorMode = false;
    });
  }

  void _onBuildingTapped(PlacedBuilding? pb) {
    if (pb != null) {
      BuildingDetailDialog.show(
        context,
        placedBuilding: pb,
        dataLoader: widget.dataLoader,
      );
    }
    setState(() {
      _selectedBuilding = pb;
      _placingBuilding = null;
      _conveyorMode = false;
    });
  }

  void _toggleConveyorMode() {
    setState(() {
      _conveyorMode = !_conveyorMode;
      _placingBuilding = null;
      _selectedBuilding = null;
    });
  }

  void _rotateCanvas() {
    _canvasKey.currentState?.rotateCanvas90();
  }

  void _exportProject() {
    final data = {
      'buildings': _project.buildings.map((pb) => {
            'building_id': pb.building.id,
            'grid_x': pb.gridX,
            'grid_y': pb.gridY,
            'rotation': pb.rotation,
            'recipe_id': pb.activeRecipeId,
          }).toList(),
      'conveyors': _project.conveyors.map((c) => {
            'path': c.path
                .map((p) => {'x': p.dx.toInt(), 'y': p.dy.toInt()})
                .toList(),
            'item_id': c.itemId,
          }).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('蓝图已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _importProject() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('导入蓝图',
              style: TextStyle(color: Color(0xFFCCCCCC))),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              maxLines: 10,
              style: const TextStyle(
                  color: Color(0xFFCCCCCC), fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '在此粘贴蓝图 JSON...',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                border: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xFF555555))),
                enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xFF555555))),
                focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xFFFFCC00))),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF888888))),
            ),
            TextButton(
              onPressed: () {
                try {
                  final data = json.decode(controller.text);
                  _applyImportData(data);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('蓝图导入成功'),
                        duration: Duration(seconds: 2)),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导入失败: $e')),
                  );
                }
              },
              child: const Text('导入',
                  style: TextStyle(color: Color(0xFFFFCC00))),
            ),
          ],
        );
      },
    );
  }

  void _applyImportData(Map<String, dynamic> data) {
    final newBuildings = <PlacedBuilding>[];
    final newConveyors = <ConveyorBelt>[];

    if (data['buildings'] != null) {
      for (final bd in data['buildings']) {
        final buildingId = bd['building_id'] as String;
        final building = widget.dataLoader.getBuilding(buildingId);
        if (building != null) {
          newBuildings.add(PlacedBuilding(
            id: 'building_${DateTime.now().millisecondsSinceEpoch}_${newBuildings.length}',
            building: building,
            gridX: (bd['grid_x'] as num).toDouble(),
            gridY: (bd['grid_y'] as num).toDouble(),
            rotation: bd['rotation'] as int? ?? 0,
            activeRecipeId: bd['recipe_id'] as String?,
          ));
        }
      }
    }

    if (data['conveyors'] != null) {
      for (final cd in data['conveyors']) {
        final path = <Offset>[];
        if (cd['path'] != null) {
          for (final p in cd['path']) {
            path.add(Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ));
          }
        } else if (cd['start_x'] != null && cd['end_x'] != null) {
          final sx = ((cd['start_x'] as num).toDouble() / 48.0).floor();
          final sy = ((cd['start_y'] as num).toDouble() / 48.0).floor();
          final ex = ((cd['end_x'] as num).toDouble() / 48.0).floor();
          final ey = ((cd['end_y'] as num).toDouble() / 48.0).floor();

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
        }

        if (path.length >= 2) {
          newConveyors.add(ConveyorBelt(
            id: 'belt_${DateTime.now().millisecondsSinceEpoch}_${newConveyors.length}',
            path: path,
            itemId: cd['item_id'] as String? ?? '',
          ));
        }
      }
    }

    setState(() {
      _project.buildings
        ..clear()
        ..addAll(newBuildings);
      _project.conveyors
        ..clear()
        ..addAll(newConveyors);
      widget.simulationEngine.attach(_project);
    });
  }

  Building? _getBuildingByKey(int keyIndex) {
    if (keyIndex < 0 || keyIndex >= _dockOrder.length) return null;
    return widget.dataLoader.getBuilding(_dockOrder[keyIndex]);
  }

  bool _handleKeyDown(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelPlacement();
      return true;
    }

    // Ctrl+R: 旋转画布（必须在页面层处理，否则浏览器会拦截刷新）
    if (event.logicalKey == LogicalKeyboardKey.keyR &&
        (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
            HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlRight))) {
      _rotateCanvas();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyE &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.controlRight)) {
      _toggleConveyorMode();
      return true;
    }

    int? keyIndex;
    final label = event.logicalKey.keyLabel;
    if (label == '1') {
      keyIndex = 0;
    } else if (label == '2') {
      keyIndex = 1;
    } else if (label == '3') {
      keyIndex = 2;
    } else if (label == '4') {
      keyIndex = 3;
    } else if (label == '5') {
      keyIndex = 4;
    } else if (label == '6') {
      keyIndex = 5;
    } else if (label == '7') {
      keyIndex = 6;
    } else if (label == '8') {
      keyIndex = 7;
    } else if (label == '9') {
      keyIndex = 8;
    } else if (label == '0' ||
        event.logicalKey == LogicalKeyboardKey.digit0) {
      keyIndex = 9;
    }

    if (keyIndex != null) {
      final building = _getBuildingByKey(keyIndex);
      if (building != null) {
        final isSelected = _placingBuilding?.id == building.id;
        setState(() {
          _placingBuilding = isSelected ? null : building;
          _conveyorMode = false;
          _selectedBuilding = null;
        });
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final handled = _handleKeyDown(event);
          return handled ? KeyEventResult.handled : KeyEventResult.ignored;
        },
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CanvasEditor(
                      key: _canvasKey,
                      dataLoader: widget.dataLoader,
                      project: _project,
                      onProjectChanged: (p) {
                        setState(() {
                          _project = p;
                          widget.simulationEngine.attach(p);
                        });
                      },
                      placingBuilding: _placingBuilding,
                      onBuildingPlaced: _onBuildingPlaced,
                      onBuildingSelected: _onBuildingTapped,
                      conveyorMode: _conveyorMode,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 60,
                    child: FloatingActionButtons(
                      conveyorMode: _conveyorMode,
                      onConveyorToggle: _toggleConveyorMode,
                      onRotateCanvas: _rotateCanvas,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: EquipmentDock(
                        dataLoader: widget.dataLoader,
                        selectedBuilding: _placingBuilding,
                        onBuildingSelected: _onDockBuildingSelected,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(bottom: BorderSide(color: Color(0xFF444444), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            'AIC 规划工具',
            style: TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _toolbarButton(
            widget.simulationEngine.isRunning ? '暂停' : '启动',
            widget.simulationEngine.isRunning ? Icons.pause : Icons.play_arrow,
            false,
            () => widget.simulationEngine.toggle(),
          ),
          const SizedBox(width: 8),
          _speedControl(),
          const SizedBox(width: 8),
          _toolbarButton('导出', Icons.file_upload_outlined, false,
              _exportProject),
          const SizedBox(width: 4),
          _toolbarButton('导入', Icons.file_download_outlined, false,
              _importProject),
        ],
      ),
    );
  }

  Widget _toolbarButton(
      String label, IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0x40FFCC00)
              : const Color(0xFF333333),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFFCC00)
                : const Color(0xFF555555),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFCCCCCC)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _speedControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        border: Border.all(color: const Color(0xFF555555)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [0.25, 0.5, 1.0, 2.0, 4.0].map((speed) {
          final isActive =
              (widget.simulationEngine.speedMultiplier - speed).abs() < 0.01;
          return GestureDetector(
            onTap: () => widget.simulationEngine.speedMultiplier = speed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0x40FFCC00)
                    : Colors.transparent,
              ),
              child: Text(
                '${speed}x',
                style: TextStyle(
                  color:
                      isActive ? const Color(0xFFFFCC00) : const Color(0xFF888888),
                  fontSize: 10,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(top: BorderSide(color: Color(0xFF444444), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            '设备: ${_project.buildings.length}',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
          ),
          const SizedBox(width: 16),
          Text(
            '传送带: ${_project.conveyors.length}',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
          ),
          const SizedBox(width: 16),
          Text(
            '缩放: ${(_project.scale * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
          ),
          const Spacer(),
          if (_placingBuilding != null)
            Text(
              '放置模式: ${_placingBuilding!.name}',
              style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 10),
            )
          else if (_conveyorMode)
            const Text(
              '传送带模式 (ESC退出)',
              style: TextStyle(color: Color(0xFF4488FF), fontSize: 10),
            )
          else if (widget.simulationEngine.isRunning)
            const Text(
              '● 仿真运行中',
              style: TextStyle(color: Color(0xFF00FF66), fontSize: 10),
            )
          else
            const Text(
              '● 仿真已暂停',
              style: TextStyle(color: Color(0xFF666666), fontSize: 10),
            ),
        ],
      ),
    );
  }
}
