import 'package:intl/intl.dart';

enum ShelfLifeUnit {
  day('天', 'D'),
  month('个月', 'M'),
  year('年', 'Y');

  const ShelfLifeUnit(this.label, this.code);
  final String label;
  final String code;
}

class ShelfLife {
  const ShelfLife(this.value, this.unit);

  final int value;
  final ShelfLifeUnit unit;

  String get label => '$value${unit.label}';

  /// Compact form stored in the database, e.g. `12M`.
  String get code => '$value${unit.code}';

  static ShelfLife? fromCode(String? code) {
    if (code == null || code.length < 2) return null;
    final n = int.tryParse(code.substring(0, code.length - 1));
    final u = code.substring(code.length - 1);
    if (n == null || n <= 0) return null;
    for (final unit in ShelfLifeUnit.values) {
      if (unit.code == u) return ShelfLife(n, unit);
    }
    return null;
  }

  /// Last day the product is still good when made on [production]: a product
  /// made on 2025-03-01 with a 12-month shelf life is good until 2026-02-28.
  DateTime lastDayFrom(DateTime production) {
    final p = dateOnly(production);
    final end = switch (unit) {
      ShelfLifeUnit.day => DateTime(p.year, p.month, p.day + value),
      ShelfLifeUnit.month => addMonths(p, value),
      ShelfLifeUnit.year => addMonths(p, value * 12),
    };
    return DateTime(end.year, end.month, end.day - 1);
  }

  @override
  bool operator ==(Object other) => other is ShelfLife && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => label;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Calendar month arithmetic; the day is clamped to the end of the target
/// month (Jan 31 + 1 month = Feb 28/29).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final day = d.day > daysInMonth(year, month) ? daysInMonth(year, month) : d.day;
  return DateTime(year, month, day);
}

enum ExpiryLevel {
  /// Past its last good day.
  expired,

  /// Good for one calendar month or less.
  withinOneMonth,

  /// Good for two calendar months or less.
  withinTwoMonths,
  ok,
}

ExpiryLevel expiryLevel(DateTime lastDay, DateTime now) {
  final today = dateOnly(now);
  final end = dateOnly(lastDay);
  if (end.isBefore(today)) return ExpiryLevel.expired;
  if (!end.isAfter(addMonths(today, 1))) return ExpiryLevel.withinOneMonth;
  if (!end.isAfter(addMonths(today, 2))) return ExpiryLevel.withinTwoMonths;
  return ExpiryLevel.ok;
}

/// Whole calendar months and remaining days from [now] until [lastDay].
({int months, int days}) remainingTime(DateTime lastDay, DateTime now) {
  final today = dateOnly(now);
  final end = dateOnly(lastDay);
  var months = (end.year - today.year) * 12 + end.month - today.month;
  if (months < 0) months = 0;
  while (months > 0 && addMonths(today, months).isAfter(end)) {
    months--;
  }
  final days = end.difference(addMonths(today, months)).inDays;
  return (months: months, days: days < 0 ? 0 : days);
}

String remainingLabel(DateTime lastDay, DateTime now) {
  final today = dateOnly(now);
  final end = dateOnly(lastDay);
  if (end.isBefore(today)) return '已过期 ${today.difference(end).inDays} 天';
  if (end == today) return '今天到期';
  final r = remainingTime(end, today);
  if (r.months == 0) return '剩 ${r.days} 天';
  if (r.days == 0) return '剩 ${r.months} 个月';
  return '剩 ${r.months} 个月 ${r.days} 天';
}

final _ymd = DateFormat('yyyy-MM-dd');

String formatDate(DateTime d) => _ymd.format(d);

DateTime? parseStoredDate(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}
