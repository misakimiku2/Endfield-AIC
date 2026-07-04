import 'package:endfield_aic_planner/canvas/main_thread_simulation_backend.dart';
import 'package:endfield_aic_planner/constants/app_constants.dart';
import 'package:endfield_aic_planner/data/data_loader.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

/// `MainThreadSimulationBackend` 冒烟测试。
///
/// 该后端是 Web 平台与 Isolate 不可用时的回退路径，
/// 直接在主线程上推进 `ProjectState`。
/// 通过 `debugTickForTesting` 手动驱动 tick，无需真实 Timer。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataLoader dataLoader;

  setUp(() async {
    dataLoader = DataLoader();
    await dataLoader.loadAll();
  });

  MainThreadSimulationBackend createBackend({
    required void Function() onChanged,
  }) {
    final backend = MainThreadSimulationBackend(dataLoader, onChanged);
    addTearDown(backend.dispose);
    return backend;
  }

  test('isReady 始终为 true（无需异步初始化）', () {
    final backend = createBackend(onChanged: () {});
    expect(backend.isReady, isTrue);
  });

  group('建筑生产循环', () {
    test('消耗输入 → 推进进度 → 满一轮后产出', () {
      final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
      final placed = PlacedBuilding(
        id: 'refinery',
        building: refinery,
        gridX: 0,
        gridY: 0,
        inputItemId: 'originium_ore',
        inputItemCount: 1,
      );
      final project = ProjectState(buildings: [placed]);
      final backend = createBackend(onChanged: () {});
      backend.attach(project);

      // 第一帧：自动匹配配方并消耗输入
      backend.debugTickForTesting(0.05);

      expect(placed.activeRecipeId, 'refine_origocrust');
      expect(placed.inputItemCount, 0);
      expect(placed.inputItemId, isNull);
      expect(placed.outputItems, isEmpty);
      expect(placed.productionProgress, greaterThan(0));

      // 推进到一轮结束
      backend.debugTickForTesting(1.95);

      expect(placed.productionProgress, 0);
      expect(placed.outputItems['origocrust'], 1);
    });

    test('输入不足时不消耗、不产出', () {
      final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
      final placed = PlacedBuilding(
        id: 'refinery',
        building: refinery,
        gridX: 0,
        gridY: 0,
        activeRecipeId: 'refine_origocrust',
        inputItemCount: 0,
      );
      final project = ProjectState(buildings: [placed]);
      final backend = createBackend(onChanged: () {});
      backend.attach(project);

      backend.debugTickForTesting(0.5);

      expect(placed.productionProgress, 0);
      expect(placed.outputItems, isEmpty);
      expect(placed.isBlocked, isFalse);
    });

    test('输出库存达上限时拒绝新产出', () {
      final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
      // 预填输出至 maxOutputItemCount，使新一轮产出（amount=1）会超出上限
      final placed = PlacedBuilding(
        id: 'refinery',
        building: refinery,
        gridX: 0,
        gridY: 0,
        activeRecipeId: 'refine_origocrust',
        inputItemId: 'originium_ore',
        inputItemCount: 1,
        outputItems: {'origocrust': AppConstants.maxOutputItemCount},
      );
      final project = ProjectState(buildings: [placed]);
      final backend = createBackend(onChanged: () {});
      backend.attach(project);

      backend.debugTickForTesting(0.05);

      // 配方产出量(1) + 已有(maxOutputItemCount) > 上限 → 拒绝
      expect(placed.inputItemCount, 1, reason: '输入不应被消耗');
      expect(placed.productionProgress, 0);
      expect(
        placed.outputItems['origocrust'],
        AppConstants.maxOutputItemCount,
        reason: '输出不应增加',
      );
    });
  });

  group('传送带推进', () {
    test('flowProgress 随 tick 递增', () {
      final belt = ConveyorBelt(
        id: 'belt1',
        path: const [Offset(0, 0), Offset(0, 1)],
        itemId: '',
      );
      final project = ProjectState(buildings: [], conveyors: [belt]);
      final backend = createBackend(onChanged: () {});
      backend.attach(project);

      backend.debugTickForTesting(0.5);

      expect(belt.flowProgress, greaterThan(0));
    });

    test('flowProgress 超过回绕阈值后归零', () {
      final belt = ConveyorBelt(
        id: 'belt1',
        path: const [Offset(0, 0), Offset(0, 1)],
        itemId: '',
        flowProgress: AppConstants.flowProgressWrapThreshold - 1,
      );
      final project = ProjectState(buildings: [], conveyors: [belt]);
      final backend = createBackend(onChanged: () {});
      backend.attach(project);

      // dt*60 必然让 flowProgress 跨越阈值
      backend.debugTickForTesting(0.5);

      expect(belt.flowProgress, lessThan(AppConstants.flowProgressWrapThreshold),
          reason: '超过回绕阈值应归零');
    });
  });

  test('每帧 tick 后触发 onChanged 回调', () {
    final refinery = dataLoader.getBuilding('refining_unit_3x3')!;
    final placed = PlacedBuilding(
      id: 'refinery',
      building: refinery,
      gridX: 0,
      gridY: 0,
      inputItemId: 'originium_ore',
      inputItemCount: 1,
    );
    final project = ProjectState(buildings: [placed]);

    var changeCount = 0;
    final backend = createBackend(onChanged: () => changeCount++);
    backend.attach(project);

    backend.debugTickForTesting(0.05);
    backend.debugTickForTesting(0.05);

    expect(changeCount, 2);
  });
}
