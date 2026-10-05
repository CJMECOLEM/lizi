import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../expiry/expiry_math.dart';
import '../models/product.dart';
import 'app_database.dart';

/// Names and shelf lives remembered per barcode.
class ProductDb extends ChangeNotifier {
  ProductDb(this._open);

  static final ProductDb instance = ProductDb(AppDatabase.open);

  final Future<Database> Function() _open;

  Future<Product?> get(String barcode) async {
    if (barcode.isEmpty) return null;
    final db = await _open();
    final rows = await db.query('products', where: 'barcode = ?', whereArgs: [barcode]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Stores the non-empty values given; empty ones keep what was there.
  Future<void> remember(String barcode, {String name = '', ShelfLife? shelfLife}) async {
    if (barcode.isEmpty || (name.isEmpty && shelfLife == null)) return;
    final db = await _open();
    final values = {
      if (name.isNotEmpty) 'name': name,
      if (shelfLife != null) 'shelf_life': shelfLife.code,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    final n = await db.update('products', values, where: 'barcode = ?', whereArgs: [barcode]);
    if (n == 0) await db.insert('products', {'barcode': barcode, ...values});
    notifyListeners();
  }
}
