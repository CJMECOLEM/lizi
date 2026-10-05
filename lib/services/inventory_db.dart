import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../models/stock_sheet.dart';
import 'app_database.dart';

/// Stock-take sheets and their counted items. Every quantity change is logged
/// in `sheet_events` so the latest change can be undone.
class InventoryDb extends ChangeNotifier {
  InventoryDb(this._open);

  static final InventoryDb instance = InventoryDb(AppDatabase.open);

  final Future<Database> Function() _open;

  static String defaultSheetName(DateTime t) =>
      '盘点 ${DateFormat('MM-dd HH:mm').format(t)}';

  Future<StockSheet> createSheet({
    String? name,
    String store = '',
    String area = '',
    String note = '',
  }) async {
    final db = await _open();
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    final n = (name == null || name.trim().isEmpty) ? defaultSheetName(now) : name.trim();
    final id = await db.insert('sheets', {
      'name': n,
      'store': store.trim(),
      'area': area.trim(),
      'note': note.trim(),
      'created_at': ms,
      'updated_at': ms,
    });
    notifyListeners();
    return StockSheet(id: id, name: n, store: store, area: area, note: note, createdAt: now, updatedAt: now);
  }

  static const _sheetSelect = '''
    SELECT s.*,
      (SELECT COUNT(*) FROM sheet_items i WHERE i.sheet_id = s.id) AS line_count,
      (SELECT COALESCE(SUM(qty), 0) FROM sheet_items i WHERE i.sheet_id = s.id) AS total_qty
    FROM sheets s
  ''';

  Future<List<StockSheet>> sheets() async {
    final db = await _open();
    final rows = await db.rawQuery('$_sheetSelect ORDER BY s.updated_at DESC');
    return rows.map(StockSheet.fromMap).toList();
  }

  Future<StockSheet?> sheet(int id) async {
    final db = await _open();
    final rows = await db.rawQuery('$_sheetSelect WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : StockSheet.fromMap(rows.first);
  }

  Future<void> updateSheet(int id, {required String name, String store = '', String area = '', String note = ''}) async {
    final db = await _open();
    await db.update(
      'sheets',
      {
        'name': name.trim().isEmpty ? '未命名盘点' : name.trim(),
        'store': store.trim(),
        'area': area.trim(),
        'note': note.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Future<void> deleteSheet(int id) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('sheet_events', where: 'sheet_id = ?', whereArgs: [id]);
      await txn.delete('sheet_items', where: 'sheet_id = ?', whereArgs: [id]);
      await txn.delete('sheets', where: 'id = ?', whereArgs: [id]);
    });
    notifyListeners();
  }

  Future<List<SheetItem>> items(int sheetId, {String search = ''}) async {
    final db = await _open();
    final q = search.trim();
    final rows = await db.rawQuery(
      '''
      SELECT i.*, p.name
      FROM sheet_items i LEFT JOIN products p ON p.barcode = i.barcode
      WHERE i.sheet_id = ?
      ${q.isEmpty ? '' : 'AND (i.barcode LIKE ? OR p.name LIKE ?)'}
      ORDER BY i.last_seen DESC, i.id DESC
      ''',
      [sheetId, if (q.isNotEmpty) ...['%$q%', '%$q%']],
    );
    return rows.map(SheetItem.fromMap).toList();
  }

  /// The sheet scans are counted into, created on first use. [stored] is the
  /// id remembered in the settings.
  Future<StockSheet> currentSheet(int? stored) async {
    if (stored != null) {
      final s = await sheet(stored);
      if (s != null) return s;
    }
    return createSheet(name: '计数');
  }

  void refresh() => notifyListeners();

  /// Empties a sheet, including its undo history.
  Future<void> clearSheet(int sheetId) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('sheet_events', where: 'sheet_id = ?', whereArgs: [sheetId]);
      await txn.delete('sheet_items', where: 'sheet_id = ?', whereArgs: [sheetId]);
      await _touch(txn, sheetId, DateTime.now().millisecondsSinceEpoch);
    });
    notifyListeners();
  }

  Future<int> quantityOf(int sheetId, String barcode) async {
    final db = await _open();
    return Sqflite.firstIntValue(await db.query(
          'sheet_items',
          columns: ['qty'],
          where: 'sheet_id = ? AND barcode = ?',
          whereArgs: [sheetId, barcode],
        )) ??
        0;
  }

  /// Adds [delta] (may be negative) to the quantity of [barcode], creating the
  /// line if needed. Quantities never go below zero. Returns the new quantity.
  Future<int> add(int sheetId, String barcode, int delta, {String format = '', DateTime? at}) async {
    final db = await _open();
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final result = await db.transaction((txn) async {
      final rows = await txn.query(
        'sheet_items',
        columns: ['qty'],
        where: 'sheet_id = ? AND barcode = ?',
        whereArgs: [sheetId, barcode],
      );
      if (rows.isEmpty) {
        if (delta <= 0) return 0;
        await txn.insert('sheet_items', {
          'sheet_id': sheetId,
          'barcode': barcode,
          'format': format,
          'qty': delta,
          'first_seen': ms,
          'last_seen': ms,
        });
        await _log(txn, sheetId, barcode, format, delta, ms, created: true);
        await _touch(txn, sheetId, ms);
        return delta;
      }
      final old = rows.first['qty'] as int;
      final next = old + delta < 0 ? 0 : old + delta;
      if (next == old) return old;
      await txn.update(
        'sheet_items',
        {'qty': next, 'last_seen': ms, if (format.isNotEmpty) 'format': format},
        where: 'sheet_id = ? AND barcode = ?',
        whereArgs: [sheetId, barcode],
      );
      await _log(txn, sheetId, barcode, format, next - old, ms);
      await _touch(txn, sheetId, ms);
      return next;
    });
    notifyListeners();
    return result;
  }

  Future<void> setQuantity(int sheetId, String barcode, int qty) async {
    final current = await quantityOf(sheetId, barcode);
    if (qty < 0 || qty == current) return;
    await add(sheetId, barcode, qty - current);
  }

  Future<void> removeItem(int sheetId, String barcode) async {
    final db = await _open();
    final ms = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sheet_items',
        where: 'sheet_id = ? AND barcode = ?',
        whereArgs: [sheetId, barcode],
      );
      if (rows.isEmpty) return;
      final r = rows.first;
      await txn.delete('sheet_items', where: 'sheet_id = ? AND barcode = ?', whereArgs: [sheetId, barcode]);
      await _log(
        txn,
        sheetId,
        barcode,
        (r['format'] as String?) ?? '',
        -(r['qty'] as int),
        ms,
        removed: true,
        firstSeen: r['first_seen'] as int,
      );
      await _touch(txn, sheetId, ms);
    });
    notifyListeners();
  }

  Future<bool> canUndo(int sheetId) async {
    final db = await _open();
    final n = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM sheet_events WHERE sheet_id = ?',
      [sheetId],
    ));
    return (n ?? 0) > 0;
  }

  /// Reverts the most recent change in the sheet. Returns the affected barcode
  /// and the change that was reverted, or null if there is nothing to undo.
  Future<({String barcode, int delta})?> undoLast(int sheetId) async {
    final db = await _open();
    final result = await db.transaction<({String barcode, int delta})?>((txn) async {
      final events = await txn.query(
        'sheet_events',
        where: 'sheet_id = ?',
        whereArgs: [sheetId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (events.isEmpty) return null;
      final e = events.first;
      final barcode = e['barcode'] as String;
      final delta = e['delta'] as int;
      final ms = DateTime.now().millisecondsSinceEpoch;
      if (e['removed_item'] == 1) {
        await txn.insert('sheet_items', {
          'sheet_id': sheetId,
          'barcode': barcode,
          'format': e['format'] ?? '',
          'qty': -delta,
          'first_seen': (e['first_seen'] as int?) ?? (e['at'] as int),
          'last_seen': e['at'] as int,
        });
      } else if (e['created_item'] == 1) {
        await txn.delete('sheet_items', where: 'sheet_id = ? AND barcode = ?', whereArgs: [sheetId, barcode]);
      } else {
        await txn.rawUpdate(
          'UPDATE sheet_items SET qty = MAX(0, qty - ?) WHERE sheet_id = ? AND barcode = ?',
          [delta, sheetId, barcode],
        );
      }
      await txn.delete('sheet_events', where: 'id = ?', whereArgs: [e['id']]);
      await _touch(txn, sheetId, ms);
      return (barcode: barcode, delta: delta);
    });
    notifyListeners();
    return result;
  }

  Future<void> _log(
    Transaction txn,
    int sheetId,
    String barcode,
    String format,
    int delta,
    int ms, {
    bool created = false,
    bool removed = false,
    int? firstSeen,
  }) =>
      txn.insert('sheet_events', {
        'sheet_id': sheetId,
        'barcode': barcode,
        'format': format,
        'delta': delta,
        'created_item': created ? 1 : 0,
        'removed_item': removed ? 1 : 0,
        'first_seen': firstSeen,
        'at': ms,
      });

  Future<void> _touch(Transaction txn, int sheetId, int ms) =>
      txn.update('sheets', {'updated_at': ms}, where: 'id = ?', whereArgs: [sheetId]);
}
