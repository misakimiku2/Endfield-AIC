import 'package:endfield_aic_planner/canvas/canvas_editor.dart';
import 'package:endfield_aic_planner/canvas/simulation_engine.dart';
import 'package:endfield_aic_planner/constants/app_constants.dart';
import 'package:endfield_aic_planner/data/data_loader.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:endfield_aic_planner/state/project_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 复现 Bug：分流器/汇流器末端阻塞时，入口传送带末端物品的冻结态应推进到
/// settled(0.5)，让物品移动动画停止。
///
/// 实际 bug：末端物品 freezeProgress 卡在过渡态 newlyFrozen(-0.75)。
/// 渲染器的冻结状态机用 path.length 作为末端段 limit，而逻辑层在物流设备
/// inputBlocked 时用 terminalLimit(=path.length-1) 冻结物品，导致渲染器
/// atLimit 判定失败、冻结态永不推进到 settled，物品随 arrowProgress 持续移动。
///
/// 场景：源设备（精炼炉）──传送带──▶ 分流器/汇流器（无出口传送带）
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

  Future<void> driveBelts(WidgetTester tester, int seconds) async {
    for (int i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 构建并驱动一个场景：源精炼厂 → 传送带 → 目标物流设备（splitter/converger）。
  /// 返回入口传送带，供断言末端冻结态。
  Future<ConveyorBelt> buildAndDrive(
    WidgetTester tester,
    PlacedBuilding target,
    List<Offset> inputPath,
  ) async {
    final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
    final source = PlacedBuilding(
      id: 'source',
      building: refinery,
      gridX: 1,
      gridY: 1,
      activeRecipeId: 'refine_origocrust',
      outputItems: {'origocrust': 200},
    );
    final belt = ConveyorBelt(id: 'input_belt', path: inputPath, itemId: '');

    final project = projectNotifier.project;
    project.buildings.addAll([source, target]);
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

    await driveBelts(tester, 40);
    return belt;
  }

  /// 断言传送带末段的冻结态为 settled。
  void expectTerminalSettled(ConveyorBelt belt) {
    belt.ensureItemSegmentsFromLegacy();
    final segs = belt.itemSegments.where((s) => s.hasItems).toList();
    expect(segs, isNotEmpty, reason: '测试装置应连通：传送带应携带物品');
    final downstream = segs.last;
    expect(
      downstream.freezeProgress,
      equals(FreezeSentinels.settled),
      reason:
          '末端物品应稳定冻结在 settled(0.5)，实际卡在 ${downstream.freezeProgress}',
    );
  }

  testWidgets('分流器无出口时入口传送带末端物品冻结态推进到 settled',
      (tester) async {
    final splitter = dataLoader.getBuilding('splitter_1x1')!;
    // 分流器 (6,6)，输入端口 direction=down（从下方接收）。
    final split = PlacedBuilding(
      id: 'split',
      building: splitter,
      gridX: 6,
      gridY: 6,
    );

    // 入口传送带：源输出端口 (1,1) → 向右到 (6,1) → 向下到 (6,7) → 向上进入分流器 (6,6)
    // 末段 (6,7)→(6,6): arrival=up → inputPort=down ✓
    final path = <Offset>[
      const Offset(1, 1),
      const Offset(2, 1),
      const Offset(3, 1),
      const Offset(4, 1),
      const Offset(5, 1),
      const Offset(6, 1),
      const Offset(6, 2),
      const Offset(6, 3),
      const Offset(6, 4),
      const Offset(6, 5),
      const Offset(6, 6),
    ];

    final belt = await buildAndDrive(tester, split, path);
    expectTerminalSettled(belt);
  });

  testWidgets('汇流器无出口时入口传送带末端物品冻结态推进到 settled',
      (tester) async {
    final converger = dataLoader.getBuilding('converger_1x1')!;
    // 汇流器 (6,6)，输入端口 left/up/right（输出 down）。从上方进入：arrival=down→up 端口。
    final conv = PlacedBuilding(
      id: 'conv',
      building: converger,
      gridX: 6,
      gridY: 6,
    );

    // 入口传送带：(1,1) → 向右到 (6,1) → 向下到汇流器 (6,6)
    // 末段 (6,5)→(6,6): arrival=down → inputPort=up ✓
    final path = <Offset>[
      const Offset(1, 1),
      const Offset(2, 1),
      const Offset(3, 1),
      const Offset(4, 1),
      const Offset(5, 1),
      const Offset(6, 1),
      const Offset(6, 2),
      const Offset(6, 3),
      const Offset(6, 4),
      const Offset(6, 5),
      const Offset(6, 6),
    ];

    final belt = await buildAndDrive(tester, conv, path);
    expectTerminalSettled(belt);
  });
}
