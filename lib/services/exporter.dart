import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_record.dart';

enum ExportFormat { csv, xlsx }

const _headers = ['类型', '内容', '条码格式', '次数', '首次识别', '最近识别'];
final _time = DateFormat('yyyy-MM-dd HH:mm:ss');

String _csvField(String v) {
  if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
  return v;
}

/// CSV with a UTF-8 BOM so Excel opens Chinese text correctly.
String buildCsv(List<ScanRecord> records) {
  final sb = StringBuffer('\uFEFF')..write(_headers.join(','))..write('\r\n');
  for (final r in records) {
    sb
      ..write([
        r.type.label,
        r.content,
        r.format,
        '${r.count}',
        _time.format(r.firstSeen),
        _time.format(r.lastSeen),
      ].map(_csvField).join(','))
      ..write('\r\n');
  }
  return sb.toString();
}

List<int> buildXlsx(List<ScanRecord> records) {
  final excel = Excel.createExcel();
  const sheetName = '扫描记录';
  excel.rename(excel.getDefaultSheet()!, sheetName);
  final sheet = excel[sheetName];
  sheet.appendRow(_headers.map((h) => TextCellValue(h)).toList());
  for (final r in records) {
    sheet.appendRow([
      TextCellValue(r.type.label),
      // Stored as text so long barcodes are not turned into 1.23E+12.
      TextCellValue(r.content),
      TextCellValue(r.format),
      IntCellValue(r.count),
      TextCellValue(_time.format(r.firstSeen)),
      TextCellValue(_time.format(r.lastSeen)),
    ]);
  }
  return excel.encode()!;
}

Future<void> exportAndShare(List<ScanRecord> records, ExportFormat format) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final ext = format == ExportFormat.csv ? 'csv' : 'xlsx';
  final file = File('${dir.path}/扫描记录_$stamp.$ext');
  if (format == ExportFormat.csv) {
    await file.writeAsBytes(utf8.encode(buildCsv(records)));
  } else {
    await file.writeAsBytes(buildXlsx(records));
  }
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

Future<void> shareText(String text) =>
    SharePlus.instance.share(ShareParams(text: text));
