import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/scan_record.dart';

/// Local history. One row per distinct (type, content); [ScanRecord.count]
/// accumulates every counted occurrence.
class HistoryDb extends ChangeNotifier {
  HistoryDb._();
  static final HistoryDb instance = HistoryDb._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'history.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE records(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            format TEXT NOT NULL DEFAULT '',
            count INTEGER NOT NULL DEFAULT 1,
            first_seen INTEGER NOT NULL,
            last_seen INTEGER NOT NULL,
            UNIQUE(type, content)
          )
        ''');
        await db.execute('CREATE INDEX idx_last_seen ON records(last_seen)');
      },
    );
  }

  Future<void> addOccurrence({
    required RecordType type,
    required String content,
    String format = '',
    required DateTime at,
  }) async {
    final db = await _database;
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
    final db = await _database;
    final s = search.trim();
    final rows = await db.query(
      'records',
      where: s.isEmpty ? null : 'content LIKE ?',
      whereArgs: s.isEmpty ? null : ['%$s%'],
      orderBy: 'last_seen DESC',
    );
    return rows.map(ScanRecord.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('records', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('records');
    notifyListeners();
  }
}
