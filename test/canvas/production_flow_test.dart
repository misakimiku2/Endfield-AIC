import 'package:endfield_aic_planner/canvas/simulation_engine.dart';
import 'package:endfield_aic_planner/data/data_loader.dart';
import 'package:endfield_aic_planner/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refining consumes input before producing output', () async {
    final dataLoader = DataLoader();
    await dataLoader.loadAll();

    final refinery = dataLoader.getBuilding('refining_unit_3x3');
    expect(refinery, isNotNull);

    final placedRefinery = PlacedBuilding(
      id: 'refinery',
      building: refinery!,
      gridX: 0,
      gridY: 0,
      inputItemId: 'originium_ore',
      inputItemCount: 1,
    );
    final project = ProjectState(buildings: [placedRefinery]);
    final engine = SimulationEngine(dataLoader)..attach(project);
    addTearDown(engine.dispose);

    engine.debugTickForTesting(0.05);

    expect(placedRefinery.activeRecipeId, 'refine_origocrust');
    expect(placedRefinery.inputItemCount, 0);
    expect(placedRefinery.inputItemId, isNull);
    expect(placedRefinery.outputItems, isEmpty);
    expect(placedRefinery.productionProgress, greaterThan(0));

    engine.debugTickForTesting(1.95);

    expect(placedRefinery.productionProgress, 0);
    expect(placedRefinery.outputItems['origocrust'], 1);
  });

  test('output item is consumed when pushed onto a belt', () async {
    final dataLoader = DataLoader();
    await dataLoader.loadAll();

    final refinery = dataLoader.getBuilding('refining_unit_3x3');
    expect(refinery, isNotNull);

    final placedRefinery = PlacedBuilding(
      id: 'refinery',
      building: refinery!,
      gridX: 0,
      gridY: 0,
      activeRecipeId: 'refine_origocrust',
      outputItems: {'origocrust': 1},
    );
    final belt = ConveyorBelt(
      id: 'output_belt',
      path: const [
        Offset(0, 0),
        Offset(0, 1),
      ],
      itemId: '',
    );

    expect(placedRefinery.hasOutputItem('origocrust'), true);
    expect(belt.pushSourceItem('origocrust'), true);
    expect(placedRefinery.consumeOutputItem('origocrust', 1), true);
    expect(placedRefinery.outputItems, isEmpty);
    expect(belt.itemId, 'origocrust');
    expect(belt.itemFillCount, 1);
  });
}
