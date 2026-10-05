import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lizi/expiry/expiry_math.dart';
import 'package:lizi/expiry/stock_group.dart';
import 'package:lizi/models/expiry_item.dart';
import 'package:lizi/pages/expiry_edit_page.dart';
import 'package:lizi/pages/expiry_product_page.dart';
import 'package:lizi/services/app_database.dart';
import 'package:lizi/services/expiry_db.dart';
import 'package:lizi/services/exporter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final now = DateTime(2026, 1, 15);
  ExpiryItem item(
    int id, {
    String barcode = 'A',
    String name = '护手霜',
    DateTime? expiry,
    DateTime? production,
    int qty = 1,
    String unit = '件',
  }) => ExpiryItem(
    id: id,
    barcode: barcode,
    name: name,
    expiryDate: expiry ?? DateTime(2026, 3, 15),
    productionDate: production,
    qty: qty,
    unit: unit,
    createdAt: now,
    updatedAt: now,
  );

  test('barcode has priority; names only group products without barcodes', () {
    final groups = groupExpiryItems([
      item(1),
      item(2, name: '改名'),
      item(3, barcode: 'B'),
      item(4, barcode: ''),
      item(5, barcode: ''),
      item(6, barcode: '', name: ''),
      item(7, barcode: '', name: ''),
    ]);
    expect(groups, hasLength(5));
    expect(
      groups.firstWhere((g) => g.key == 'barcode:A').batches,
      hasLength(2),
    );
    expect(groups.firstWhere((g) => g.key == 'name:护手霜').batches, hasLength(2));
  });

  test('each filter includes products with any matching batch', () {
    final group = groupExpiryItems([
      item(1, expiry: DateTime(2026, 1, 1)),
      item(2, expiry: DateTime(2026, 2, 1)),
      item(3),
      item(4, expiry: DateTime(2027, 1, 1)),
    ]).single;
    for (final level in ExpiryLevel.values) {
      expect(group.matchesLevel(level, now), isTrue);
    }
    expect(group.earliest.levelAt(now), ExpiryLevel.expired);
    expect(group.quantityLabel, '4 件');
    expect(group.matchesSearch('护手'), isTrue);
  });

  test('totals do not mix units and labels handle expiry-only batches', () {
    final group = groupExpiryItems([
      item(1, qty: 2),
      item(2, qty: 3, unit: '盒'),
    ]).single;
    expect(group.quantityLabel, '2 件 + 3 盒');
    expect(batchLabel(item(1)), '到期 2026-03-15');
    expect(
      batchLabel(item(1, production: DateTime(2025, 3, 16))),
      '生产 2025-03-16',
    );
  });

  test('copy includes only selected batch, not local photo or other stock', () {
    final text = batchCopyText(item(1, qty: 5, unit: '支'), now);
    expect(text, contains('生产日期：未填写'));
    expect(text, contains('到期日期：2026-03-15'));
    expect(text, contains('数量：5\n单位：支'));
    expect(text, contains('剩余 59 天'));
    expect(text, isNot(contains('photo')));
    expect(
      expiryDaysLabel(item(2, expiry: DateTime(2026, 1, 14)), now),
      '已过期 1 天',
    );
  });

  test(
    'draft editing preserves quantity and unit; new draft starts at one',
    () {
      final draft = ExpiryDraft.of(item(1, qty: 12, unit: '支'));
      expect(draft.qty, 12);
      expect(draft.unit, '支');
      expect(draft.toItem()!.qty, 12);
      expect(draft.toItem()!.unit, '支');
      final fresh = ExpiryDraft(printedExpiry: DateTime(2027));
      expect(fresh.toItem()!.quantityLabel, '1 件');
    },
  );

  test('exports include quantity and unit with numeric Excel stock cells', () {
    final items = [item(1, qty: 12, unit: '盒')];
    final csv = buildExpiryCsv(items, now: now);
    expect(csv, contains('记录时间,数量,单位'));
    expect(csv, contains(',12,盒\r\n'));
    final sheet = Excel.decodeBytes(buildExpiryXlsx(items, now: now))
        .tables['保质期']!;
    expect(sheet.rows[1][9]!.value, IntCellValue(12));
    expect(sheet.rows[1][10]!.value, TextCellValue('盒'));
  });

  testWidgets(
    'switching tabs updates parameters, copy and stock independently',
    (tester) async {
      sqfliteFfiInit();
      final db = (await tester.runAsync(
        () => openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath),
      ))!;
      final store = ExpiryDb(() async => db);
      final a = (await tester.runAsync(
        () => store.add(item(1, production: DateTime(2025, 1, 1), qty: 2)),
      ))!.item;
      final b = (await tester.runAsync(
        () => store.add(item(2, production: DateTime(2025, 2, 1), qty: 7)),
      ))!.item;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ExpiryProductPage(
              productKey: expiryProductKey(a),
              database: store,
            ),
          ),
        );
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('batch-${b.id}')));
        await tester.pumpAndSettle();
        expect(find.text('生产 2025-02-01 · 7 件'), findsOneWidget);
        final panel = tester.widget<BatchParameterPanel>(
          find.byType(BatchParameterPanel),
        );
        expect(panel.item.id, b.id);
        await tester.scrollUntilVisible(
          find.text('复制当前批次参数'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('复制当前批次参数'));
        await tester.pumpAndSettle();
        expect(copied, contains('生产日期：2025-02-01'));
        expect(copied, contains('数量：7'));
        expect(copied, isNot(contains('2025-01-01')));
        await tester.ensureVisible(find.byTooltip('当前批次加一'));
        await tester.tap(find.byTooltip('当前批次加一'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        final rows = await tester.runAsync(store.all);
        expect(rows!.firstWhere((r) => r.id == b.id).qty, 8);
        expect(rows.firstWhere((r) => r.id == a.id).qty, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        store.dispose();
        await tester.runAsync(db.close);
      }
    },
  );
}
