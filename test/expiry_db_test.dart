import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lizi/expiry/expiry_math.dart';
import 'package:lizi/models/expiry_item.dart';
import 'package:lizi/services/app_database.dart';
import 'package:lizi/services/expiry_db.dart';
import 'package:lizi/services/inventory_db.dart';
import 'package:lizi/services/product_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ExpiryDb store;
  final now = DateTime(2026, 1, 1);

  ExpiryItem item({
    String barcode = 'A',
    String name = '护手霜',
    DateTime? production,
    int qty = 1,
    String unit = '件',
  }) => ExpiryItem(
    barcode: barcode,
    name: name,
    productionDate: production,
    expiryDate: DateTime(2027, 1, 1),
    qty: qty,
    unit: unit,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() async {
    db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    store = ExpiryDb(() async => db);
  });
  tearDown(() async {
    store.dispose();
    await db.close();
  });

  test(
    'new batch is one unit; repeated admissions increment atomically',
    () async {
      final first = await store.add(item(unit: '盒'));
      expect(first.existed, isFalse);
      await Future.wait(List.generate(8, (_) => store.add(item())));
      final rows = await store.all();
      expect(rows, hasLength(1));
      expect(rows.single.qty, 9);
      expect(rows.single.unit, '盒');
    },
  );

  test(
    'different production dates never merge even with the same expiry',
    () async {
      await store.add(item(production: DateTime(2025, 1, 1)));
      await store.add(item(production: DateTime(2025, 2, 1)));
      await store.add(item());
      expect(await store.all(), hasLength(3));
    },
  );

  test(
    'no-barcode names merge; unnamed items and different barcodes do not',
    () async {
      await store.add(item(barcode: ''));
      await store.add(item(barcode: '', qty: 2));
      await store.add(item(barcode: 'B'));
      await store.add(item(barcode: '', name: ''));
      await store.add(item(barcode: '', name: ''));
      final rows = await store.all();
      expect(rows, hasLength(4));
      expect(
        rows.where((r) => r.barcode.isEmpty && r.name.isNotEmpty).single.qty,
        3,
      );
    },
  );

  test(
    'editing sets quantity rather than adding; decrement stops at zero',
    () async {
      final saved = (await store.add(item())).item;
      await store.update(saved.copyWith(qty: 7, unit: '瓶'));
      expect((await store.all()).single.qty, 7);
      await store.changeQuantity(saved.id!, -10);
      expect((await store.all()).single.qty, 0);
      await expectLater(
        store.update(saved.copyWith(qty: -1)),
        throwsArgumentError,
      );
    },
  );

  test('editing into another batch is rejected without losing stock', () async {
    final a = (await store.add(item(production: DateTime(2025, 1, 1)))).item;
    final b = (await store.add(item(production: DateTime(2025, 2, 1)))).item;
    await expectLater(store.update(a.copyWith(id: b.id)), throwsStateError);
    expect(await store.all(), hasLength(2));
  });

  test(
    'remembers product parameters and unit, including no-barcode names',
    () async {
      final products = ProductDb(() async => db);
      await products.remember(
        'A',
        name: '护手霜',
        unit: '支',
        shelfLife: const ShelfLife(12, ShelfLifeUnit.month),
      );
      await products.remember('A', name: '新版护手霜');
      expect((await products.get('A'))!.unit, '支');
      expect((await products.get('A'))!.shelfLife!.value, 12);
      await store.add(item(barcode: '', unit: '盒'));
      expect((await store.rememberedByName('护手霜'))!.unit, '盒');
      products.dispose();
    },
  );

  test(
    'shelf-life admission leaves the standalone counter unchanged',
    () async {
      final inventory = InventoryDb(() async => db);
      final sheet = await inventory.createSheet(name: '计数');
      await inventory.add(sheet.id, 'A', 5);
      await store.add(item());
      await store.add(item());
      expect(await inventory.quantityOf(sheet.id, 'A'), 5);
      expect((await store.all()).single.qty, 2);
      inventory.dispose();
    },
  );

  test('version 3 upgrade preserves old records with quantity one', () async {
    final dir = await Directory.systemTemp.createTemp('lizi-migration-');
    final path = '${dir.path}/history.db';
    Database? upgraded;
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE expiry_items(
            id INTEGER PRIMARY KEY, barcode TEXT, name TEXT, production_date TEXT,
            shelf_life TEXT, expiry_date TEXT, photo TEXT, ocr_text TEXT,
            created_at INTEGER, updated_at INTEGER)''');
            final values = item().toMap()
              ..remove('qty')
              ..remove('unit');
            await db.insert('expiry_items', values);
          },
        ),
      );
      await old.close();
      upgraded = await openAppDatabase(databaseFactoryFfi, path);
      final rows = await upgraded.query('expiry_items');
      expect(rows.single['name'], '护手霜');
      expect(rows.single['qty'], 1);
      expect(rows.single['unit'], '件');
      expect(await upgraded.getVersion(), 4);
    } finally {
      await upgraded?.close();
      await dir.delete(recursive: true);
    }
  });
}
