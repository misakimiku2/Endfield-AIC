import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'data/data_loader.dart';
import 'canvas/simulation_engine.dart';
import 'state/project_notifier.dart';
import 'pages/editor_page.dart';
import 'utils/error_handler.dart';

/// 物品图片在各处使用的 cacheWidth/cacheHeight 尺寸集合。
/// Image.asset 使用 cacheWidth/cacheHeight 时会内部包装为 ResizeImage，
/// 其缓存键与原始 AssetImage 不同，因此需要按这些尺寸单独预加载。
const _itemCacheSizes = [120, 162, 168, 192, 210, 279, 384];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 安装框架级错误捕获，让 widget 构建异常、未捕获 async 错误也进入统一 handler。
  installFrameworkErrorHandlers();

  // 提升 imageCache 容量以容纳原始图 + 多尺寸缩放版本
  PaintingBinding.instance.imageCache.maximumSize = 1000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1A1A1A),
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final dataLoader = DataLoader();
  await dataLoader.loadAll();

  // 预加载所有 PNG 图片和 SVG 图标到缓存
  await _precacheAllAssets();

  final simulationEngine = SimulationEngine(dataLoader);
  final projectNotifier = ProjectNotifier(simulationEngine);

  runApp(EndfieldAICApp(
    dataLoader: dataLoader,
    simulationEngine: simulationEngine,
    projectNotifier: projectNotifier,
  ));
}

class EndfieldAICApp extends StatelessWidget {
  final DataLoader dataLoader;
  final SimulationEngine simulationEngine;
  final ProjectNotifier projectNotifier;

  const EndfieldAICApp({
    super.key,
    required this.dataLoader,
    required this.simulationEngine,
    required this.projectNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DataLoader>.value(value: dataLoader),
        ChangeNotifierProvider<SimulationEngine>.value(value: simulationEngine),
        ChangeNotifierProvider<ProjectNotifier>.value(value: projectNotifier),
      ],
      child: MaterialApp(
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
        home: const EditorPage(),
      ),
    );
  }
}

/// 从 AssetManifest.json 读取所有资源路径，预加载 PNG 和 SVG 到缓存。
///
/// 关键点：Image.asset 使用 cacheWidth/cacheHeight 时会内部包装为 ResizeImage，
/// 其缓存键与原始 AssetImage 不同，因此必须按各 UI 实际使用的尺寸分别预加载，
/// 否则首次打开弹窗时仍会触发解码+缩放导致空白→图片的延迟。
Future<void> _precacheAllAssets() async {
  final manifestJson = await rootBundle.loadString('AssetManifest.json');
  final manifest = json.decode(manifestJson) as Map<String, dynamic>;

  final pngPaths = manifest.keys.where((k) => k.endsWith('.png')).toList();
  final svgPaths = manifest.keys.where((k) => k.endsWith('.svg')).toList();

  Logger.info('[precache] 开始预加载: ${pngPaths.length} PNG, ${svgPaths.length} SVG, '
      '${_itemCacheSizes.length} 种缩放尺寸');
  final stopwatch = Stopwatch()..start();

  // 第一阶段：原始分辨率 PNG + SVG 并行预加载
  await Future.wait([
    ...pngPaths.map(_precachePngImage),
    ...svgPaths.map(_precacheSvg),
  ]);

  Logger.info('[precache] 原始分辨率完成: ${stopwatch.elapsedMilliseconds}ms, '
      'imageCache: ${PaintingBinding.instance.imageCache.currentSize} entries / '
      '${(PaintingBinding.instance.imageCache.currentSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB');

  // 第二阶段：按各 UI 使用的 cacheWidth/cacheHeight 尺寸预加载缩放版本
  // ResizeImage 的缓存键包含目标尺寸，必须逐尺寸预加载才能命中
  final resizeStopwatch = Stopwatch()..start();
  await Future.wait([
    for (final path in pngPaths)
      for (final size in _itemCacheSizes)
        _precacheResizedPng(path, size),
  ]);

  Logger.info('[precache] 缩放尺寸完成: ${resizeStopwatch.elapsedMilliseconds}ms, '
      'imageCache: ${PaintingBinding.instance.imageCache.currentSize} entries / '
      '${(PaintingBinding.instance.imageCache.currentSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB');

  stopwatch.stop();
  Logger.info('[precache] 全部完成，总耗时: ${stopwatch.elapsedMilliseconds}ms');
}

/// 预加载 PNG 图片到 imageCache（原始分辨率）
Future<void> _precachePngImage(String path) async {
  try {
    final completer = Completer<void>();
    final stream = AssetImage(path).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete();
        stream.removeListener(listener);
      },
      onError: (e, s) {
        completer.completeError(e, s);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    await completer.future;
  } catch (e, stackTrace) {
    AppError(
      message: 'PNG 原始加载失败: $path -> $e',
      severity: ErrorSeverity.warning,
      code: 'PRECACHE_PNG_LOAD_FAILED',
      stackTrace: stackTrace,
      context: {'path': path},
    ).report();
  }
}

/// 预加载 PNG 图片到 imageCache（指定缩放尺寸，匹配 Image.asset 的 cacheWidth/cacheHeight）
Future<void> _precacheResizedPng(String path, int size) async {
  try {
    final completer = Completer<void>();
    final provider = ResizeImage(AssetImage(path), width: size, height: size);
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete();
        stream.removeListener(listener);
      },
      onError: (e, s) {
        completer.completeError(e, s);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    await completer.future;
  } catch (_) {
    // 忽略无法缩放的图片
  }
}

/// 预加载 SVG 图标到 pictureCache
Future<void> _precacheSvg(String path) async {
  try {
    await vg.loadPicture(SvgAssetLoader(path), null);
  } catch (e, stackTrace) {
    AppError(
      message: 'SVG 加载失败: $path -> $e',
      severity: ErrorSeverity.warning,
      code: 'PRECACHE_SVG_LOAD_FAILED',
      stackTrace: stackTrace,
      context: {'path': path},
    ).report();
  }
}