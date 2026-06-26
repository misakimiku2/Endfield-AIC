import 'dart:ui';

/// 类型安全的 JSON 解析扩展方法。
///
/// 替代遍布各处的手写 `(json['x'] as num).toDouble()` 强制转换：
/// - 统一处理 int/double/num 三种数值来源
/// - 缺字段或类型不符时给出明确报错（必填）或可配置默认值（可选）
/// - 减少运行时类型错误风险
extension JsonParse on Map<String, dynamic> {
  /// 读取必填的 double 字段。
  ///
  /// 字段缺失或非数值时抛出 [FormatException]，避免静默错误。
  double getDouble(String key) {
    final value = this[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    throw FormatException(
        'Expected double for key "$key", got ${value.runtimeType} ($value)');
  }

  /// 读取可选的 double 字段，缺失或非数值时返回 [defaultValue]。
  double getDoubleOrDefault(String key, {double defaultValue = 0.0}) {
    final value = this[key];
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return defaultValue;
  }

  /// 读取可能为 null 的 double 字段，返回 null 表示未提供。
  double? getDoubleOrNull(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }
}

/// 作用于任意 Map 的坐标解析辅助方法（用于 List 元素未必是
/// Map<String, dynamic> 的场景，如 sim_worker 中的 message 解析）。
extension OffsetParse on Map {
  /// 读取必填的 double 字段（同 [JsonParse.getDouble]，但作用于任意 Map）。
  double getDouble(String key) {
    final value = this[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    throw FormatException(
        'Expected double for key "$key", got ${value.runtimeType} ($value)');
  }

  /// 从 `{'x': ..., 'y': ...}` 形式的节点读取 [Offset]。
  Offset offset() => Offset(getDouble('x'), getDouble('y'));
}
