import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../expiry/expiry_math.dart';
import '../models/expiry_item.dart';
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

  /// Saves a new check. The same product with the same last good day is one
  /// batch, so an existing entry is refreshed instead of duplicated; returns
  /// the stored item and whether it was already there.
  Future<({ExpiryItem item, bool existed})> add(ExpiryItem item) async {
    final db = await _open();
    if (item.barcode.isNotEmpty) {
      final rows = await db.query(
        'expiry_items',
        where: 'barcode = ? AND expiry_date = ?',
        whereArgs: [item.barcode, formatDate(item.expiryDate)],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final old = ExpiryItem.fromMap(rows.first);
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'expiry_items',
          {
            'updated_at': now,
            if (old.name.isEmpty && item.name.isNotEmpty) 'name': item.name,
          },
          where: 'id = ?',
          whereArgs: [old.id],
        );
        notifyListeners();
        final fresh = await db.query('expiry_items', where: 'id = ?', whereArgs: [old.id]);
        return (item: ExpiryItem.fromMap(fresh.first), existed: true);
      }
    }
    final id = await db.insert('expiry_items', item.toMap()..remove('id'));
    notifyListeners();
    return (item: item.copyWith(id: id), existed: false);
  }

  Future<void> update(ExpiryItem item) async {
    final db = await _open();
    final values = item.copyWith(updatedAt: DateTime.now()).toMap()..remove('id');
    await db.update('expiry_items', values, where: 'id = ?', whereArgs: [item.id]);
    notifyListeners();
  }

  /// Puts back an item that was just deleted, keeping its id.
  Future<void> restore(ExpiryItem item) async {
    final db = await _open();
    await db.insert('expiry_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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
