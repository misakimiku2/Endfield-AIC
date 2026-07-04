import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 错误/日志严重程度。
///
/// 依次递增：[debug] 仅开发环境输出；[info] 作为面包屑送入 reporter；
/// [warning]/[error]/[critical] 表示真实异常，会进入 [CrashReporter]。
enum ErrorSeverity { debug, info, warning, error, critical }

/// 崩溃上报抽象。
///
/// 默认 [NoopCrashReporter] 不做任何事；接入 Sentry / Crashlytics 等
/// 服务时提供新实现，并通过 [ErrorHandler.setReporter] 注册。
///
/// 该抽象只面向主线程（Isolate 内的 worker 不依赖此模块）。
abstract class CrashReporter {
  void report(AppError error);

  void logBreadcrumb(
    String message, {
    ErrorSeverity severity = ErrorSeverity.info,
  });
}

/// 不做任何事情的 [CrashReporter] 实现，作为默认值。
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  void report(AppError error) {}

  @override
  void logBreadcrumb(String message, {ErrorSeverity severity = ErrorSeverity.info}) {}
}

/// 全局错误处理中心。
///
/// 设计要点：
/// - 静态配置，主线程任意位置可直接调用，无需 DI。
/// - `kDebugMode` 为编译期常量，release 下日志分支被死代码消除，零开销。
/// - 测试可通过 [setReporter] 注入 mock，并用 [resetReporter] 还原。
class ErrorHandler {
  static CrashReporter _reporter = const NoopCrashReporter();

  static CrashReporter get reporter => _reporter;

  /// 注册崩溃上报实现。仅在应用启动早期或测试中调用。
  static void setReporter(CrashReporter reporter) {
    _reporter = reporter;
  }

  /// 还原为默认的 [NoopCrashReporter]。仅用于测试清理。
  static void resetReporter() {
    _reporter = const NoopCrashReporter();
  }

  /// 统一错误上报入口。
  static void report(AppError error) {
    if (kDebugMode) {
      debugPrint(
          '[${error.severity.name.toUpperCase()}] ${error.code}: ${error.message}');
    }
    _reporter.report(error);
  }

  /// 记录一条面包屑（breadcrumb）。
  ///
  /// 面包屑本身不是错误，而是在崩溃发生时帮助还原上下文的痕迹
  /// （如启动耗时、关键状态切换）。debug 级别不会送入 reporter，
  /// 避免热路径产生噪声。
  static void breadcrumb(
    String message, {
    ErrorSeverity severity = ErrorSeverity.info,
  }) {
    if (severity == ErrorSeverity.debug) {
      if (kDebugMode) {
        debugPrint('[DEBUG] $message');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint('[${severity.name.toUpperCase()}] $message');
    }
    _reporter.logBreadcrumb(message, severity: severity);
  }
}

/// 统一错误模型。
///
/// 通过 [report] 送入 [ErrorHandler]；构造时不做任何 I/O，
/// 因此可安全在 catch 块中创建。
class AppError {
  /// 面向人的描述信息。
  final String message;

  /// 严重程度，决定是否以及如何上报。
  final ErrorSeverity severity;

  /// 稳定错误码，便于在日志/崩溃看板中聚合（如 `PRECACHE_SVG_LOAD_FAILED`）。
  final String code;

  /// 可选调用栈。送入崩溃服务时非常有用。
  final StackTrace? stackTrace;

  /// 可选结构化上下文，附加在错误上的键值对。
  final Map<String, dynamic>? context;

  AppError({
    required this.message,
    this.severity = ErrorSeverity.error,
    required this.code,
    this.stackTrace,
    this.context,
  });

  /// 上报本错误到 [ErrorHandler]。
  void report() => ErrorHandler.report(this);
}

/// 诊断日志（非错误的性能/状态追踪）。
///
/// - [debug]：仅开发环境输出到 debugPrint，release 下死代码消除，**不**送入 reporter。
///   用于高频触发的开发调试痕迹（每次 build 的状态、图片加载观测等）。
/// - [info]：作为面包屑送入 reporter，在崩溃时提供上下文。
///   用于低频、有诊断价值的事件（启动耗时、关键阶段完成等）。
class Logger {
  Logger._();

  static void debug(String message) =>
      ErrorHandler.breadcrumb(message, severity: ErrorSeverity.debug);

  static void info(String message) =>
      ErrorHandler.breadcrumb(message, severity: ErrorSeverity.info);
}

/// 在应用启动早期调用一次，安装框架级错误捕获。
///
/// 将 Flutter 框架未处理异常（widget build 失败等）与平台层未捕获的
/// async 异常统一送入 [ErrorHandler]。debug 模式下保留原有红屏体验。
///
/// 应在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用。
void installFrameworkErrorHandlers() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppError(
      message: details.exception.toString(),
      severity: ErrorSeverity.error,
      code: 'FLUTTER_FRAMEWORK',
      stackTrace: details.stack,
      context: {
        if (details.library != null) 'library': details.library!,
        if (details.context != null) 'context': details.context.toString(),
      },
    ).report();
    // 保留 debug 模式下原有的错误展示（红屏）。
    previousFlutterError?.call(details);
  };

  // 捕获未 await 的 Future 错误与 isolate 外抛的异常。
  // 返回 true 表示已处理，抑制控制台默认的崩溃打印。
  PlatformDispatcher.instance.onError = (error, stack) {
    AppError(
      message: error.toString(),
      severity: ErrorSeverity.critical,
      code: 'UNCAUGHT_ASYNC',
      stackTrace: stack,
    ).report();
    return true;
  };
}
