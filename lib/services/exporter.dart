import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../expiry/expiry_math.dart';
import '../models/expiry_item.dart';
import '../models/scan_record.dart';
import '../models/stock_sheet.dart';

enum ExportFormat { csv, xlsx }

final _time = DateFormat('yyyy-MM-dd HH:mm:ss');

String _csvField(String v) {
  if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
  return v;
}

/// CSV with a UTF-8 BOM so Excel opens Chinese text correctly.
String _csv(List<String> headers, Iterable<List<String>> rows) {
  final sb = StringBuffer('\uFEFF')
    ..write(headers.join(','))
    ..write('\r\n');
  for (final r in rows) {
    sb
      ..write(r.map(_csvField).join(','))
      ..write('\r\n');
  }
  return sb.toString();
}

// Barcodes are written as text so Excel does not turn them into 6.9E+12.
List<int> _xlsx(
  String sheetName,
  List<String> headers,
  Iterable<List<CellValue>> rows, {
  Map<String, String>? info,
}) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, sheetName);
  final sheet = excel[sheetName];
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  for (final r in rows) {
    sheet.appendRow(r);
  }
  if (info != null) {
    final infoSheet = excel['信息'];
    info.forEach(
      (k, v) => infoSheet.appendRow([TextCellValue(k), TextCellValue(v)]),
    );
  }
  return excel.encode()!;
}

// ---- Text recognition history ----

const _recordHeaders = ['类型', '内容', '条码格式', '次数', '首次识别', '最近识别'];

List<String> _recordRow(ScanRecord r) => [
  r.type.label,
  r.content,
  r.format,
  '${r.count}',
  _time.format(r.firstSeen),
  _time.format(r.lastSeen),
];

String buildCsv(List<ScanRecord> records) =>
    _csv(_recordHeaders, records.map(_recordRow));

List<int> buildXlsx(List<ScanRecord> records) => _xlsx(
  '扫描记录',
  _recordHeaders,
  records.map(
    (r) => [
      TextCellValue(r.type.label),
      TextCellValue(r.content),
      TextCellValue(r.format),
      IntCellValue(r.count),
      TextCellValue(_time.format(r.firstSeen)),
      TextCellValue(_time.format(r.lastSeen)),
    ],
  ),
);

Future<void> exportAndShare(List<ScanRecord> records, ExportFormat format) {
  final bytes = format == ExportFormat.csv
      ? utf8.encode(buildCsv(records))
      : buildXlsx(records);
  return _shareFile('识字记录', format == ExportFormat.csv ? 'csv' : 'xlsx', bytes);
}

// ---- Counting ----

const sheetHeaders = ['序号', '条码', '品名', '数量', '码制', '首次扫描', '最后扫描'];

List<String> _itemRow(int i, SheetItem it) => [
  '${i + 1}',
  it.barcode,
  it.name,
  '${it.qty}',
  it.format,
  _time.format(it.firstSeen),
  _time.format(it.lastSeen),
];

String buildSheetCsv(List<SheetItem> items) => _csv(sheetHeaders, [
  for (var i = 0; i < items.length; i++) _itemRow(i, items[i]),
]);

List<int> buildSheetXlsx(List<SheetItem> items) => _xlsx(
  '计数明细',
  sheetHeaders,
  [
    for (var i = 0; i < items.length; i++)
      [
        IntCellValue(i + 1),
        TextCellValue(items[i].barcode),
        TextCellValue(items[i].name),
        IntCellValue(items[i].qty),
        TextCellValue(items[i].format),
        TextCellValue(_time.format(items[i].firstSeen)),
        TextCellValue(_time.format(items[i].lastSeen)),
      ],
  ],
  info: {
    '品种数': '${items.length}',
    '总数量': '${items.fold<int>(0, (s, it) => s + it.qty)}',
    '导出时间': _time.format(DateTime.now()),
  },
);

Future<void> exportSheet(List<SheetItem> items, ExportFormat format) {
  final bytes = format == ExportFormat.csv
      ? utf8.encode(buildSheetCsv(items))
      : buildSheetXlsx(items);
  return _shareFile('计数', format == ExportFormat.csv ? 'csv' : 'xlsx', bytes);
}

// ---- Shelf life ----

const expiryHeaders = [
  '序号',
  '状态',
  '品名',
  '条码',
  '生产日期',
  '保质期',
  '到期日',
  '剩余',
  '记录时间',
  '数量',
  '单位',
];

String expiryStatusLabel(ExpiryLevel level) => switch (level) {
  ExpiryLevel.expired => '已过期',
  ExpiryLevel.withinOneMonth => '1个月内到期',
  ExpiryLevel.withinTwoMonths => '2个月内到期',
  ExpiryLevel.ok => '正常',
};

List<String> _expiryRow(int i, ExpiryItem it, DateTime now) => [
  '${i + 1}',
  expiryStatusLabel(it.levelAt(now)),
  it.name,
  it.barcode,
  it.productionDate == null ? '' : formatDate(it.productionDate!),
  it.shelfLife?.label ?? '',
  formatDate(it.expiryDate),
  remainingLabel(it.expiryDate, now),
  _time.format(it.updatedAt),
  '${it.qty}',
  it.unit,
];

String buildExpiryCsv(List<ExpiryItem> items, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return _csv(expiryHeaders, [
    for (var i = 0; i < items.length; i++) _expiryRow(i, items[i], t),
  ]);
}

List<int> buildExpiryXlsx(List<ExpiryItem> items, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return _xlsx(
    '保质期',
    expiryHeaders,
    [
      for (var i = 0; i < items.length; i++)
        [
          IntCellValue(i + 1),
          for (final v in _expiryRow(i, items[i], t).skip(1).take(8))
            TextCellValue(v),
          IntCellValue(items[i].qty),
          TextCellValue(items[i].unit),
        ],
    ],
    info: {
      for (final level in ExpiryLevel.values)
        expiryStatusLabel(level):
            '${items.where((it) => it.levelAt(t) == level).length}',
      '导出时间': _time.format(t),
    },
  );
}

Future<void> exportExpiry(List<ExpiryItem> items, ExportFormat format) {
  final bytes = format == ExportFormat.csv
      ? utf8.encode(buildExpiryCsv(items))
      : buildExpiryXlsx(items);
  return _shareFile('保质期', format == ExportFormat.csv ? 'csv' : 'xlsx', bytes);
}

// ---- Helpers ----

final _unsafeName = RegExp(r'[\\/:*?"<>|\s]+');

Future<void> _shareFile(String baseName, String ext, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final safe = baseName.replaceAll(_unsafeName, '_');
  final file = File('${dir.path}/${safe}_$stamp.$ext');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

Future<void> shareText(String text) =>
    SharePlus.instance.share(ShareParams(text: text));
