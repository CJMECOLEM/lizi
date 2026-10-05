import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../barcode/gtin.dart';

/// The single local database. Version 1 only had the scan history table
/// (`records`); version 2 adds products, case packs and stock-take sheets.
///
/// Only SQLite features available on old Android system libraries are used
/// (no UPSERT), since sqflite relies on the platform SQLite there.
class AppDatabase {
  AppDatabase._();

  static Future<Database>? _db;

  static Future<Database> open() => _db ??= _openDefault();

  static Future<Database> _openDefault() async => openAppDatabase(
    databaseFactory,
    p.join(await getDatabasesPath(), 'history.db'),
  );
}

const schemaVersion = 4;

Future<Database> openAppDatabase(DatabaseFactory factory, String path) =>
    factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, _) async {
          await _createV1(db);
          await _upgradeToV2(db);
          await _upgradeToV3(db);
          await _upgradeToV4(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _upgradeToV2(db);
          if (oldVersion < 3) await _upgradeToV3(db);
          if (oldVersion < 4) await _upgradeToV4(db);
        },
      ),
    );

/// Shelf-life checks. Dates are stored as `yyyy-MM-dd` so they sort as text.
Future<void> _upgradeToV3(Database db) async {
  await db.execute(
    "ALTER TABLE products ADD COLUMN shelf_life TEXT NOT NULL DEFAULT ''",
  );
  await db.execute('''
    CREATE TABLE expiry_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL DEFAULT '',
      production_date TEXT NOT NULL DEFAULT '',
      shelf_life TEXT NOT NULL DEFAULT '',
      expiry_date TEXT NOT NULL,
      photo TEXT NOT NULL DEFAULT '',
      ocr_text TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_expiry_date ON expiry_items(expiry_date)');
  await db.execute('CREATE INDEX idx_expiry_barcode ON expiry_items(barcode)');
}

Future<void> _upgradeToV4(Database db) async {
  await db.execute(
    'ALTER TABLE expiry_items ADD COLUMN qty INTEGER NOT NULL DEFAULT 1 CHECK(qty >= 0)',
  );
  await db.execute(
    "ALTER TABLE expiry_items ADD COLUMN unit TEXT NOT NULL DEFAULT '件'",
  );
}

Future<void> _createV1(Database db) async {
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
}

Future<void> _upgradeToV2(Database db) async {
  await db.execute('''
    CREATE TABLE products(
      barcode TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      sku TEXT NOT NULL DEFAULT '',
      spec TEXT NOT NULL DEFAULT '',
      unit TEXT NOT NULL DEFAULT '',
      case_qty INTEGER,
      price REAL,
      source TEXT NOT NULL DEFAULT 'manual',
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE packs(
      code TEXT PRIMARY KEY,
      item_barcode TEXT NOT NULL,
      qty INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE sheets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      store TEXT NOT NULL DEFAULT '',
      area TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE sheet_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sheet_id INTEGER NOT NULL,
      barcode TEXT NOT NULL,
      format TEXT NOT NULL DEFAULT '',
      qty INTEGER NOT NULL DEFAULT 0,
      first_seen INTEGER NOT NULL,
      last_seen INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      UNIQUE(sheet_id, barcode)
    )
  ''');
  await db.execute('''
    CREATE TABLE sheet_events(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sheet_id INTEGER NOT NULL,
      barcode TEXT NOT NULL,
      format TEXT NOT NULL DEFAULT '',
      delta INTEGER NOT NULL,
      created_item INTEGER NOT NULL DEFAULT 0,
      removed_item INTEGER NOT NULL DEFAULT 0,
      first_seen INTEGER,
      at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_items_sheet ON sheet_items(sheet_id, last_seen)',
  );
  await db.execute(
    'CREATE INDEX idx_events_sheet ON sheet_events(sheet_id, id)',
  );
  await db.execute('CREATE INDEX idx_products_name ON products(name)');
  await _migrateBarcodeHistory(db);
}

/// Copies version-1 barcode history into a "旧版记录" sheet so earlier counts
/// stay visible. The original rows are left in place.
Future<void> _migrateBarcodeHistory(Database db) async {
  final rows = await db.query(
    'records',
    where: 'type = ?',
    whereArgs: ['barcode'],
  );
  if (rows.isEmpty) return;

  final merged = <String, Map<String, Object?>>{};
  for (final r in rows) {
    final code = canonicalCode(r['content'] as String);
    final first = r['first_seen'] as int;
    final last = r['last_seen'] as int;
    final m = merged[code];
    if (m == null) {
      merged[code] = {
        'barcode': code,
        'format': r['format'] ?? '',
        'qty': r['count'] as int,
        'first_seen': first,
        'last_seen': last,
      };
    } else {
      m['qty'] = (m['qty'] as int) + (r['count'] as int);
      if (first < (m['first_seen'] as int)) m['first_seen'] = first;
      if (last > (m['last_seen'] as int)) m['last_seen'] = last;
    }
  }
  final firsts = merged.values.map((m) => m['first_seen'] as int);
  final lasts = merged.values.map((m) => m['last_seen'] as int);
  final sheetId = await db.insert('sheets', {
    'name': '旧版记录',
    'note': '从第一版的扫描历史转入',
    'created_at': firsts.reduce((a, b) => a < b ? a : b),
    'updated_at': lasts.reduce((a, b) => a > b ? a : b),
  });
  final batch = db.batch();
  for (final m in merged.values) {
    batch.insert('sheet_items', {...m, 'sheet_id': sheetId});
  }
  await batch.commit(noResult: true);
}
