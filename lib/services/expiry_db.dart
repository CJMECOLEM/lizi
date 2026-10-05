import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../expiry/expiry_math.dart';
import '../models/expiry_item.dart';
import '../models/product.dart';
import 'app_database.dart';

/// Shelf-life checks, listed by last good day.
class ExpiryDb extends ChangeNotifier {
  ExpiryDb(this._open);

  static final ExpiryDb instance = ExpiryDb(AppDatabase.open);

  final Future<Database> Function() _open;

  Future<List<ExpiryItem>> all({String search = ''}) async {
    final db = await _open();
    final q = search.trim();
    final rows = await db.query(
      'expiry_items',
      where: q.isEmpty ? null : 'name LIKE ? OR barcode LIKE ?',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'expiry_date ASC, id DESC',
    );
    return rows.map(ExpiryItem.fromMap).toList();
  }

  // Missing production dates form expiry-only batches. Never guess that they
  // belong to a dated batch, even when the expiry dates happen to match.
  Future<List<Map<String, Object?>>> _matching(
    DatabaseExecutor db,
    ExpiryItem item,
  ) {
    final barcode = item.barcode.trim();
    final name = item.name.trim();
    if (barcode.isEmpty && name.isEmpty) return Future.value([]);
    return db.query(
      'expiry_items',
      where:
          '${barcode.isNotEmpty ? 'barcode = ?' : "barcode = '' AND name = ?"} '
          'AND production_date = ? AND expiry_date = ?'
          '${item.id == null ? '' : ' AND id != ?'}',
      whereArgs: [
        barcode.isNotEmpty ? barcode : name,
        item.productionDate == null ? '' : formatDate(item.productionDate!),
        formatDate(item.expiryDate),
        if (item.id != null) item.id,
      ],
      orderBy: 'id ASC',
      limit: 1,
    );
  }

  Future<({ExpiryItem item, bool existed})> add(ExpiryItem item) async {
    if (item.qty <= 0) throw ArgumentError('入库数量必须大于 0');
    final db = await _open();
    final result = await db.transaction((txn) async {
      final rows = await _matching(txn, item);
      if (rows.isNotEmpty) {
        final old = ExpiryItem.fromMap(rows.first);
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.update(
          'expiry_items',
          {
            'updated_at': now,
            'qty': old.qty + item.qty,
            if (old.name.isEmpty && item.name.isNotEmpty) 'name': item.name,
          },
          where: 'id = ?',
          whereArgs: [old.id],
        );
        final fresh = await txn.query(
          'expiry_items',
          where: 'id = ?',
          whereArgs: [old.id],
        );
        return (item: ExpiryItem.fromMap(fresh.first), existed: true);
      }
      final values = item.toMap()..remove('id');
      values['barcode'] = item.barcode.trim();
      values['name'] = item.name.trim();
      final id = await txn.insert('expiry_items', values);
      return (item: ExpiryItem.fromMap({...values, 'id': id}), existed: false);
    });
    notifyListeners();
    return result;
  }

  Future<void> update(ExpiryItem item) async {
    if (item.id == null || item.qty < 0) throw ArgumentError('无效的批次或数量');
    final db = await _open();
    final values = item.copyWith(updatedAt: DateTime.now()).toMap()
      ..remove('id');
    await db.transaction((txn) async {
      if ((await _matching(txn, item)).isNotEmpty) {
        throw StateError('该日期批次已存在，请在已有批次中修改数量');
      }
      await txn.update(
        'expiry_items',
        values,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    });
    notifyListeners();
  }

  Future<void> changeQuantity(int id, int delta) async {
    final db = await _open();
    await db.rawUpdate(
      'UPDATE expiry_items SET qty = MAX(0, qty + ?), updated_at = ? WHERE id = ?',
      [delta, DateTime.now().millisecondsSinceEpoch, id],
    );
    notifyListeners();
  }

  Future<Product?> rememberedByName(String name) async {
    if (name.trim().isEmpty) return null;
    final db = await _open();
    final rows = await db.query(
      'expiry_items',
      where: "barcode = '' AND name = ?",
      whereArgs: [name.trim()],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final item = ExpiryItem.fromMap(rows.first);
    return Product(
      barcode: '',
      name: item.name,
      shelfLife: item.shelfLife,
      unit: item.unit,
    );
  }

  /// Puts back an item that was just deleted, keeping its id.
  Future<void> restore(ExpiryItem item) async {
    final db = await _open();
    await db.insert(
      'expiry_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> delete(int id) async {
    final db = await _open();
    await db.delete('expiry_items', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('expiry_items');
    notifyListeners();
  }
}
