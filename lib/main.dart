import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/data_loader.dart';
import 'canvas/simulation_engine.dart';
import 'pages/editor_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1A1A1A),
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final dataLoader = DataLoader();
  await dataLoader.loadAll();

  final simulationEngine = SimulationEngine(dataLoader);

  runApp(EndfieldAICApp(
    dataLoader: dataLoader,
    simulationEngine: simulationEngine,
  ));
}

class EndfieldAICApp extends StatelessWidget {
  final DataLoader dataLoader;
  final SimulationEngine simulationEngine;

  const EndfieldAICApp({
    super.key,
    required this.dataLoader,
    required this.simulationEngine,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '终末地 AIC 规划工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFCC00),
          surface: Color(0xFF2A2A2A),
        ),
        fontFamily: 'Roboto',
      ),
      home: EditorPage(
        dataLoader: dataLoader,
        simulationEngine: simulationEngine,
      ),
    );
  }
}