import 'package:endfield_aic_planner/utils/error_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录上报到 [CrashReporter] 的错误与面包屑，便于断言路由行为。
class _RecordingReporter implements CrashReporter {
  final List<AppError> errors = [];
  final List<({String message, ErrorSeverity severity})> breadcrumbs = [];

  @override
  void report(AppError error) => errors.add(error);

  @override
  void logBreadcrumb(String message, {ErrorSeverity severity = ErrorSeverity.info}) {
    breadcrumbs.add((message: message, severity: severity));
  }
}

void main() {
  late _RecordingReporter reporter;

  setUp(() {
    reporter = _RecordingReporter();
    ErrorHandler.setReporter(reporter);
  });

  tearDown(() {
    // 还原默认 Noop，避免污染其他测试。
    ErrorHandler.resetReporter();
  });

  group('AppError.report()', () {
    test('通过 ErrorHandler 路由到已注册的 reporter', () {
      final stack = StackTrace.current;
      AppError(
        message: 'SVG 加载失败',
        severity: ErrorSeverity.warning,
        code: 'PRECACHE_SVG_LOAD_FAILED',
        stackTrace: stack,
        context: {'path': 'assets/svg/x.svg'},
      ).report();

      expect(reporter.errors, hasLength(1));
      final reported = reporter.errors.single;
      expect(reported.message, 'SVG 加载失败');
      expect(reported.severity, ErrorSeverity.warning);
      expect(reported.code, 'PRECACHE_SVG_LOAD_FAILED');
      expect(reported.stackTrace, stack);
      expect(reported.context, {'path': 'assets/svg/x.svg'});
    });

    test('severity 默认为 error', () {
      AppError(message: 'x', code: 'C').report();
      expect(reporter.errors.single.severity, ErrorSeverity.error);
    });

    test('未提供 stackTrace/context 时为 null', () {
      AppError(message: 'x', code: 'C').report();
      final reported = reporter.errors.single;
      expect(reported.stackTrace, isNull);
      expect(reported.context, isNull);
    });
  });

  group('ErrorHandler', () {
    test('report 直接调用同样路由到 reporter', () {
      final error = AppError(message: 'm', code: 'CODE');
      ErrorHandler.report(error);
      expect(reporter.errors.single, same(error));
    });

    test('breadcrumb 以 info 默认级别送入 reporter', () {
      ErrorHandler.breadcrumb('启动完成');
      expect(reporter.breadcrumbs, hasLength(1));
      expect(reporter.breadcrumbs.single.message, '启动完成');
      expect(reporter.breadcrumbs.single.severity, ErrorSeverity.info);
    });

    test('breadcrumb 在 debug 级别不送入 reporter', () {
      ErrorHandler.breadcrumb('热路径', severity: ErrorSeverity.debug);
      expect(reporter.breadcrumbs, isEmpty);
    });

    test('setReporter/resetReporter 切换实现', () {
      final another = _RecordingReporter();
      ErrorHandler.setReporter(another);
      AppError(message: 'm', code: 'C').report();
      expect(another.errors, hasLength(1));
      expect(reporter.errors, isEmpty);

      ErrorHandler.resetReporter();
      // 重置后再上报不应再写入 any recording reporter。
      AppError(message: 'm2', code: 'C2').report();
      expect(another.errors, hasLength(1));
      expect(reporter.errors, isEmpty);
    });
  });

  group('Logger', () {
    test('info 作为面包屑送入 reporter', () {
      Logger.info('[precache] 总耗时: 1234ms');
      expect(reporter.breadcrumbs, hasLength(1));
      expect(reporter.breadcrumbs.single.message, '[precache] 总耗时: 1234ms');
      expect(reporter.breadcrumbs.single.severity, ErrorSeverity.info);
    });

    test('debug 不送入 reporter（避免热路径噪声）', () {
      Logger.debug('[SplitterPanel] 状态: ...');
      expect(reporter.breadcrumbs, isEmpty);
      expect(reporter.errors, isEmpty);
    });
  });

  group('NoopCrashReporter', () {
    test('所有方法均为空操作、不抛异常', () {
      const noop = NoopCrashReporter();
      noop.report(AppError(message: 'm', code: 'C'));
      noop.logBreadcrumb('msg');
      noop.logBreadcrumb('msg', severity: ErrorSeverity.error);
      // 无显式断言：未抛异常即通过。
    });

    test('是 ErrorHandler 的默认实现（reset 后）', () {
      ErrorHandler.resetReporter();
      expect(ErrorHandler.reporter, isA<NoopCrashReporter>());
    });
  });
}
