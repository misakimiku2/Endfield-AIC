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
