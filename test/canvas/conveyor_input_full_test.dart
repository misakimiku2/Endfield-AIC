import 'package:endfield_aic_planner/canvas/canvas_editor.dart';
import 'package:endfield_aic_planner/canvas/simulation_engine.dart';
import 'package:endfield_aic_planner/constants/app_constants.dart';
import 'package:endfield_aic_planner/data/data_loader.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:endfield_aic_planner/state/project_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 复现 Bug：当生产设备输入端满载（默认 50 个）时，传送带末端物品应稳定冻结
/// （freezeProgress 推进到 settled=0.5），让物品移动动画停止。
///
/// 实际 bug：物品冻在末端但 freezeProgress 卡在过渡态 newlyFrozen(-0.75)，
/// 渲染器的冻结状态机用 path.length 作为末端段 limit，而逻辑层用
/// terminalLimit(=path.length-1) 冻结物品，导致渲染器 atLimit 判定失败、
/// 冻结态永不推进到 settled，物品随 arrowProgress 持续移动（动画不停）。
///
/// 场景：源设备（精炼炉，激活配方 refine_origocrust，输出库存有 origocrust）
///   ──传送带──▶ 接收设备（精炼炉，输入预填满 50 个 origocrust、不消耗）
///
/// 端口坐标（3x3 精炼炉，rotation=0）：
/// - 源在 (1,1)：solid 输出端口 0 位于 (1,1)
/// - 接收在 (1,7)：solid 输入端口 0 位于 (1,9)
/// - 传送带路径：(1,1) → (1,2) → ... → (1,9)
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

  /// 用细粒度 pump 驱动 CanvasEditor 内部的 _beltArrowController..repeat()。
  /// widget test 的 pump(duration) 每次只产生一帧，必须用小步长（100ms）
  /// 才能让动画 progress 真实经过 0.5 阈值，触发 onBeltAnimationFrame 的
  /// 跨零检测与渲染器的冻结状态机推进。
  Future<void> driveBelts(WidgetTester tester, int durationSeconds) async {
    for (int i = 0; i < durationSeconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      '满载输入端时传送带末端物品的冻结态应推进到 settled，动画停止',
      (tester) async {
    final refinery = dataLoader.getBuilding('refining_unit_3x3')!;

    // 源设备：gridX=1, gridY=1，solid 输出端口 0 在 (1,1)。
    final source = PlacedBuilding(
      id: 'source',
      building: refinery,
      gridX: 1,
      gridY: 1,
      activeRecipeId: 'refine_origocrust',
      outputItems: {'origocrust': 200},
    );

    // 接收设备：gridX=1, gridY=7，solid 输入端口 0 在 (1,9)。
    // 预填满 50 个 origocrust，且无激活配方 → 永不消耗，制造稳定的满载状态。
    final sink = PlacedBuilding(
      id: 'sink',
      building: refinery,
      gridX: 1,
      gridY: 7,
      inputItemId: 'origocrust',
      inputItemCount: PlacedBuilding.maxInputItemCount,
    );

    // 传送带：从源的输出端口格 (1,1) 向下延伸到接收的输入端口格 (1,9)。
    final path = <Offset>[
      for (int y = 1; y <= 9; y++) Offset(1, y.toDouble()),
    ];
    final belt = ConveyorBelt(id: 'belt', path: path, itemId: '');

    final project = projectNotifier.project;
    project.buildings.add(source);
    project.buildings.add(sink);
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

    // 推进足够多帧，让物品抵达末端并经过多轮冻结状态机推进。
    // 冻结状态机 newlyFrozen → waiting → midFrozen → settled 的推进依赖
    // arrowProgress 多次跨越 0.5，需要足够的帧数。
    await driveBelts(tester, 20);

    // 装置自检：传送带应携带物品，且接收设备未突破上限。
    belt.ensureItemSegmentsFromLegacy();
    expect(
      belt.itemSegments.where((s) => s.hasItems).isNotEmpty,
      isTrue,
      reason: '测试装置应连通：传送带应携带物品',
    );
    expect(
      sink.inputItemCount,
      lessThanOrEqualTo(PlacedBuilding.maxInputItemCount),
    );

    // 核心断言：末端段的 freezeProgress 应推进到 settled(0.5)。
    // bug 下它会卡在 newlyFrozen(-0.75)，物品随 arrowProgress 持续移动。
    belt.ensureItemSegmentsFromLegacy();
    final downstream = belt.itemSegments.last;
    expect(
      downstream.freezeProgress,
      equals(FreezeSentinels.settled),
      reason:
          '满载时末端物品应稳定冻结在 settled(0.5)，实际卡在 ${downstream.freezeProgress}',
    );
  });
}
