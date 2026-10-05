import '../models/expiry_item.dart';
import '../models/product.dart';
import 'expiry_math.dart';

String expiryProductKey(ExpiryItem item) {
  if (item.barcode.trim().isNotEmpty) return 'barcode:${item.barcode.trim()}';
  if (item.name.trim().isNotEmpty) return 'name:${item.name.trim()}';
  // Unknown products must not silently collapse into one stock entry.
  return 'unknown:${item.id ?? identityHashCode(item)}';
}

class ExpiryProductGroup {
  ExpiryProductGroup(this.key, Iterable<ExpiryItem> items)
    : batches = List.of(items)
        ..sort((a, b) {
          final byExpiry = a.expiryDate.compareTo(b.expiryDate);
          return byExpiry != 0 ? byExpiry : (a.id ?? 0).compareTo(b.id ?? 0);
        });

  final String key;
  final List<ExpiryItem> batches;

  ExpiryItem get earliest => batches.first;
  String get title {
    final named = batches.where((b) => b.name.trim().isNotEmpty).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return named.isEmpty ? earliest.title : named.first.name;
  }

  bool matchesLevel(ExpiryLevel? level, DateTime now) =>
      level == null || batches.any((b) => b.levelAt(now) == level);

  bool matchesSearch(String search) {
    final q = search.trim().toLowerCase();
    return q.isEmpty ||
        batches.any(
          (b) =>
              b.name.toLowerCase().contains(q) ||
              b.barcode.toLowerCase().contains(q),
        );
  }

  String get quantityLabel {
    final totals = <String, int>{};
    for (final b in batches) {
      final unit = stockUnit(b.unit);
      totals[unit] = (totals[unit] ?? 0) + b.qty;
    }
    // A box and a piece cannot be summed without a conversion factor.
    return totals.entries.map((e) => '${e.value} ${e.key}').join(' + ');
  }
}

List<ExpiryProductGroup> groupExpiryItems(Iterable<ExpiryItem> items) {
  final groups = <String, List<ExpiryItem>>{};
  for (final item in items) {
    groups.putIfAbsent(expiryProductKey(item), () => []).add(item);
  }
  return [
    for (final entry in groups.entries)
      ExpiryProductGroup(entry.key, entry.value),
  ]..sort((a, b) {
    final byExpiry = a.earliest.expiryDate.compareTo(b.earliest.expiryDate);
    return byExpiry != 0 ? byExpiry : a.key.compareTo(b.key);
  });
}

String batchLabel(ExpiryItem item) => item.productionDate == null
    ? '到期 ${formatDate(item.expiryDate)}'
    : '生产 ${formatDate(item.productionDate!)}';

int daysUntilExpiry(DateTime expiry, DateTime now) => DateTime.utc(
  expiry.year,
  expiry.month,
  expiry.day,
).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

String expiryDaysLabel(ExpiryItem item, DateTime now) {
  final days = daysUntilExpiry(item.expiryDate, now);
  return days < 0
      ? '已过期 ${-days} 天'
      : days == 0
      ? '今天到期'
      : '剩余 $days 天';
}

String batchCopyText(ExpiryItem item, DateTime now) => [
  '商品名称：${item.title}',
  '条形码：${item.barcode.isEmpty ? '未填写' : item.barcode}',
  '生产日期：${item.productionDate == null ? '未填写' : formatDate(item.productionDate!)}',
  '保质期：${item.shelfLife?.label ?? '未填写'}',
  '到期日期：${formatDate(item.expiryDate)}',
  '剩余时间：${remainingLabel(item.expiryDate, now)}（${expiryDaysLabel(item, now)}）',
  '数量：${item.qty}',
  '单位：${stockUnit(item.unit)}',
].join('\n');
