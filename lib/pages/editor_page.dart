import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/project.dart';
import '../data/data_loader.dart';
import '../canvas/canvas_editor.dart';
import '../canvas/simulation_engine.dart';
import '../widgets/building_palette.dart';
import '../widgets/property_panel.dart';

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

  @override
  void initState() {
    super.initState();
    _project = ProjectState();
    widget.simulationEngine.attach(_project);
  }

  void _onBuildingSelected(Building building) {
    setState(() {
      _placingBuilding = building;
      _conveyorMode = false;
      _selectedBuilding = null;
    });
  }

  void _onBuildingPlaced() {
    setState(() {
      _placingBuilding = null;
    });
  }

  void _onCancelPlacement() {
    setState(() {
      _placingBuilding = null;
      _conveyorMode = false;
    });
  }

  void _onBuildingTapped(PlacedBuilding? pb) {
    setState(() {
      _selectedBuilding = pb;
      _placingBuilding = null;
      _conveyorMode = false;
    });
  }

  void _onRecipeChanged(String? recipeId) {
    if (_selectedBuilding == null) return;
    setState(() {
      _selectedBuilding!.activeRecipeId = recipeId;
      _updatePortLinks();
    });
  }

  void _updatePortLinks() {
    if (_selectedBuilding == null) return;
    final recipe = _selectedBuilding!.activeRecipeId != null
        ? widget.dataLoader.getRecipe(_selectedBuilding!.activeRecipeId!)
        : null;

    _selectedBuilding!.inputPorts
      ..clear()
      ..addAll(List.generate(
        _selectedBuilding!.building.ports.inputs.length,
        (i) => PortState(
          index: i,
          type: 'input',
          definition: _selectedBuilding!.building.ports.inputs[i],
        ),
      ));

    _selectedBuilding!.outputPorts
      ..clear()
      ..addAll(List.generate(
        _selectedBuilding!.building.ports.outputs.length,
        (i) => PortState(
          index: i,
          type: 'output',
          definition: _selectedBuilding!.building.ports.outputs[i],
        ),
      ));

    if (recipe != null) {
      for (int i = 0; i < recipe.inputs.length && i < _selectedBuilding!.inputPorts.length; i++) {
        _selectedBuilding!.inputPorts[i].linkedItemId = recipe.inputs[i].itemId;
      }
      for (int i = 0; i < recipe.outputs.length && i < _selectedBuilding!.outputPorts.length; i++) {
        _selectedBuilding!.outputPorts[i].linkedItemId = recipe.outputs[i].itemId;
      }
    }
  }

  void _onRotate() {
    if (_selectedBuilding == null) return;
    setState(() {
      _selectedBuilding!.rotation = (_selectedBuilding!.rotation + 1) % 4;
    });
  }

  void _onDelete() {
    if (_selectedBuilding == null) return;
    final pb = _selectedBuilding!;
    setState(() {
      _project.buildings.remove(pb);
      _project.conveyors.removeWhere((belt) {
        const cellSize = 48.0;
        const threshold = 30.0;
        for (final port in [...pb.inputPorts, ...pb.outputPorts]) {
          final pw = port.worldPosition(
              pb.gridX, pb.gridY, cellSize, pb.building.gridWidth, pb.building.gridHeight);
          if ((belt.start - pw).distance < threshold ||
              (belt.end - pw).distance < threshold) {
            return true;
          }
        }
        return false;
      });
      _selectedBuilding = null;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                if (_placingBuilding != null || _conveyorMode)
                  const SizedBox(width: 0)
                else
                  BuildingPalette(
                    dataLoader: widget.dataLoader,
                    selectedBuildingId: _placingBuilding?.id,
                    onBuildingSelected: _onBuildingSelected,
                    onCancelPlacement: _onCancelPlacement,
                  ),
                Expanded(
                  child: CanvasEditor(
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
                PropertyPanel(
                  selectedBuilding: _selectedBuilding,
                  dataLoader: widget.dataLoader,
                  onRecipeChanged: _onRecipeChanged,
                  onRotate: _onRotate,
                  onDelete: _onDelete,
                ),
              ],
            ),
          ),
          _buildStatusBar(),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          const SizedBox(width: 16),
          _toolbarButton(
            '传送带',
            Icons.cable,
            _conveyorMode,
            () {
              setState(() {
                _conveyorMode = !_conveyorMode;
                _placingBuilding = null;
                _selectedBuilding = null;
              });
            },
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
          if (widget.simulationEngine.isRunning)
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
