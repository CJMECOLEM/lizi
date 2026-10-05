import 'package:flutter/foundation.dart';

import '../models/scan_record.dart';
import 'app_database.dart';

/// Text-recognition history. One row per distinct text; [ScanRecord.count]
/// accumulates every counted occurrence. Barcode counts live in stock-take
/// sheets (see `InventoryDb`); old barcode rows from version 1 are kept in the
/// table but no longer listed here.
class HistoryDb extends ChangeNotifier {
  HistoryDb._();
  static final HistoryDb instance = HistoryDb._();

  Future<void> addOccurrence({
    required RecordType type,
    required String content,
    String format = '',
    required DateTime at,
  }) async {
    final db = await AppDatabase.open();
    final ms = at.millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final updated = await txn.rawUpdate(
        'UPDATE records SET count = count + 1, last_seen = ?, format = ? '
        'WHERE type = ? AND content = ?',
        [ms, format, type.name, content],
      );
      if (updated == 0) {
        await txn.insert('records', {
          'type': type.name,
          'content': content,
          'format': format,
          'count': 1,
          'first_seen': ms,
          'last_seen': ms,
        });
      }
    });
    notifyListeners();
  }

  Future<List<ScanRecord>> query({String search = ''}) async {
    final db = await AppDatabase.open();
    final s = search.trim();
    final rows = await db.query(
      'records',
      where: s.isEmpty ? 'type = ?' : 'type = ? AND content LIKE ?',
      whereArgs: s.isEmpty ? [RecordType.text.name] : [RecordType.text.name, '%$s%'],
      orderBy: 'last_seen DESC',
    );
    return rows.map(ScanRecord.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.open();
    await db.delete('records', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> clear() async {
    final db = await AppDatabase.open();
    await db.delete('records', where: 'type = ?', whereArgs: [RecordType.text.name]);
    notifyListeners();
  }
}
