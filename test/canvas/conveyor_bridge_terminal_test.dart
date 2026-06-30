import 'package:endfield_aic_planner/canvas/canvas_editor.dart';
import 'package:endfield_aic_planner/canvas/simulation_engine.dart';
import 'package:endfield_aic_planner/constants/app_constants.dart';
import 'package:endfield_aic_planner/data/data_loader.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:endfield_aic_planner/state/project_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 复现 Bug：物流桥（belt bridge）只有一端连接传送带、另一侧断开时，
/// 物品走到物流桥后应停下（末端物品冻结态推进到 settled，动画停止）。
///
/// 实际 bug：末端物品 freezeProgress 卡在过渡态 newlyFrozen(-0.75)，
/// 渲染器的冻结状态机用 path.length 作为末端段 limit，而逻辑层在物流桥
/// 通道满时用 terminalLimit(=path.length-1) 冻结物品，导致渲染器 atLimit
/// 判定失败、冻结态永不推进到 settled，物品随 arrowProgress 持续移动
/// （视觉上"源源不断进入物流桥"，动画不停）。
///
/// 场景：源设备（精炼炉）──传送带──▶ 物流桥（仅一端连接，无出口传送带）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataLoader dataLoader;
  late SimulationEngine engine;
  late ProjectNotifier projectNotifier;

  setUp(() async {
    dataLoader = DataLoader();
    await dataLoader.loadAll();
    engine = SimulationEngine(dataLoader);
    projectNotifier = ProjectNotifier(engine);
  });

  tearDown(() {
    engine.dispose();
  });

  /// 细粒度 pump 驱动动画控制器（详见 conveyor_input_full_test.dart 注释）。
  Future<void> driveBelts(WidgetTester tester, int seconds) async {
    for (int i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('物流桥单端连接时末端物品冻结态应推进到 settled，动画停止',
      (tester) async {
    final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
    final bridge = dataLoader.getBuilding('belt_bridge_1x1')!;

    // 源精炼厂在 (1,1)：solid 输出端口 0 在 (1,1)。
    final source = PlacedBuilding(
      id: 'source',
      building: refinery,
      gridX: 1,
      gridY: 1,
      activeRecipeId: 'refine_origocrust',
      outputItems: {'origocrust': 200},
    );

    // 物流桥在 (5,5)（1x1），仅作为传送带终点，无出口传送带。
    final bridgeBuilding = PlacedBuilding(
      id: 'bridge',
      building: bridge,
      gridX: 5,
      gridY: 5,
    );

    // 入口传送带：从源输出端口 (1,1) → 向右到 (5,1) → 向下到物流桥 (5,5)。
    final path = <Offset>[
      const Offset(1, 1),
      const Offset(2, 1),
      const Offset(3, 1),
      const Offset(4, 1),
      const Offset(5, 1),
      const Offset(5, 2),
      const Offset(5, 3),
      const Offset(5, 4),
      const Offset(5, 5),
    ];
    final belt = ConveyorBelt(id: 'belt', path: path, itemId: '');

    final project = projectNotifier.project;
    project.buildings.addAll([source, bridgeBuilding]);
    project.conveyors.add(belt);
    projectNotifier.notifyChanged();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataLoader>.value(value: dataLoader),
          ChangeNotifierProvider<SimulationEngine>.value(value: engine),
          ChangeNotifierProvider<ProjectNotifier>.value(value: projectNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CanvasEditor()),
        ),
      ),
    );

    // 推进足够帧，让物品抵达物流桥末端并经过多轮冻结状态机推进。
    await driveBelts(tester, 20);

    // 装置自检：传送带应携带物品，物流桥通道应已接收一个物品（容量1）。
    belt.ensureItemSegmentsFromLegacy();
    expect(
      belt.itemSegments.where((s) => s.hasItems).isNotEmpty,
      isTrue,
      reason: '测试装置应连通：传送带应携带物品',
    );
    expect(
      bridgeBuilding.bridgeLaneItems.values,
      contains('origocrust'),
      reason: '物品应已进入物流桥通道',
    );

    // 核心断言：末端段的 freezeProgress 应推进到 settled(0.5)。
    // bug 下它卡在 newlyFrozen(-0.75)，物品随 arrowProgress 持续移动。
    belt.ensureItemSegmentsFromLegacy();
    final downstream = belt.itemSegments.lastWhere((s) => s.hasItems);
    expect(
      downstream.freezeProgress,
      equals(FreezeSentinels.settled),
      reason:
          '物流桥单端时末端物品应稳定冻结在 settled(0.5)，实际卡在 ${downstream.freezeProgress}',
    );
  });
}
