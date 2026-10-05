import 'package:flutter_test/flutter_test.dart';
import 'package:lizi/expiry/expiry_math.dart';
import 'package:lizi/expiry/expiry_parser.dart';
import 'package:lizi/models/expiry_item.dart';
import 'package:lizi/pages/expiry_edit_page.dart';
import 'package:lizi/services/exporter.dart';

void main() {
  final now = DateTime(2026, 1, 15);

  ExpiryParse parse(List<String> lines, {List<double>? heights}) => parseExpiry(
        [for (var i = 0; i < lines.length; i++) OcrLine(lines[i], height: heights?[i] ?? 20)],
        now: now,
      );

  group('date math', () {
    test('addMonths clamps to the end of the month', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(addMonths(DateTime(2025, 11, 30), 3), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 3, 15), -3), DateTime(2025, 12, 15));
    });

    test('shelf life gives the last good day', () {
      expect(const ShelfLife(12, ShelfLifeUnit.month).lastDayFrom(DateTime(2025, 3, 1)), DateTime(2026, 2, 28));
      expect(const ShelfLife(2, ShelfLifeUnit.year).lastDayFrom(DateTime(2025, 3, 10)), DateTime(2027, 3, 9));
      expect(const ShelfLife(180, ShelfLifeUnit.day).lastDayFrom(DateTime(2025, 1, 1)), DateTime(2025, 6, 29));
    });

    test('shelf life code round trip', () {
      expect(ShelfLife.fromCode('18M'), const ShelfLife(18, ShelfLifeUnit.month));
      expect(ShelfLife.fromCode(const ShelfLife(3, ShelfLifeUnit.year).code), const ShelfLife(3, ShelfLifeUnit.year));
      expect(ShelfLife.fromCode('x'), isNull);
      expect(ShelfLife.fromCode('0M'), isNull);
    });

    test('levels use calendar months', () {
      expect(expiryLevel(DateTime(2026, 1, 14), now), ExpiryLevel.expired);
      expect(expiryLevel(DateTime(2026, 1, 15), now), ExpiryLevel.withinOneMonth);
      expect(expiryLevel(DateTime(2026, 2, 15), now), ExpiryLevel.withinOneMonth);
      expect(expiryLevel(DateTime(2026, 2, 16), now), ExpiryLevel.withinTwoMonths);
      expect(expiryLevel(DateTime(2026, 3, 15), now), ExpiryLevel.withinTwoMonths);
      expect(expiryLevel(DateTime(2026, 3, 16), now), ExpiryLevel.ok);
    });

    test('remaining label', () {
      expect(remainingLabel(DateTime(2026, 1, 10), now), '已过期 5 天');
      expect(remainingLabel(DateTime(2026, 1, 15), now), '今天到期');
      expect(remainingLabel(DateTime(2026, 1, 25), now), '剩 10 天');
      expect(remainingLabel(DateTime(2026, 3, 15), now), '剩 2 个月');
      expect(remainingLabel(DateTime(2026, 4, 20), now), '剩 3 个月 5 天');
      expect(remainingTime(DateTime(2026, 2, 14), DateTime(2026, 1, 31)), (months: 0, days: 14));
      expect(remainingTime(DateTime(2026, 2, 28), DateTime(2026, 1, 31)), (months: 1, days: 0));
    });
  });

  group('parseExpiry', () {
    test('production date with shelf life in months', () {
      final r = parse(['生产日期：2025.03.01', '保质期：12个月']);
      expect(r.productionDate, DateTime(2025, 3, 1));
      expect(r.shelfLife, const ShelfLife(12, ShelfLifeUnit.month));
      expect(r.printedExpiry, isNull);
      expect(r.lastDay, DateTime(2026, 2, 28));
    });

    test('full-width characters, Chinese date and Chinese numerals', () {
      final r = parse(['生产日期：２０２５年３月１日', '保质期：十八个月']);
      expect(r.productionDate, DateTime(2025, 3, 1));
      expect(r.shelfLife, const ShelfLife(18, ShelfLifeUnit.month));
    });

    test('printed expiry date wins', () {
      final r = parse(['生产日期 2025-05-01', '有效期至 2027-04-30', '保质期 24个月']);
      expect(r.productionDate, DateTime(2025, 5, 1));
      expect(r.printedExpiry, DateTime(2027, 4, 30));
      expect(r.lastDay, DateTime(2027, 4, 30));
    });

    test('value on the next line and compact sprayed date', () {
      final r = parse(['生产日期', '20250610 A12', '保质期', '3年']);
      expect(r.productionDate, DateTime(2025, 6, 10));
      expect(r.shelfLife, const ShelfLife(3, ShelfLifeUnit.year));
    });

    test('a label without value does not steal the next label\'s date', () {
      final r = parse(['生产日期：见瓶底', '限用日期：2027/01/31']);
      expect(r.productionDate, isNull);
      expect(r.printedExpiry, DateTime(2027, 1, 31));
    });

    test('english labels and day-first dates', () {
      final r = parse(['MFG: 01/06/2025', 'EXP: 31/05/2028']);
      expect(r.productionDate, DateTime(2025, 6, 1));
      expect(r.printedExpiry, DateTime(2028, 5, 31));
    });

    test('month-only expiry means the end of that month', () {
      final r = parse(['EXP 2027.08']);
      expect(r.printedExpiry, DateTime(2027, 8, 31));
    });

    test('generic 保质期 label with a date and a separate shelf life', () {
      final r = parse(['保质期 2025.09.09', '常温保存 18个月']);
      expect(r.productionDate, DateTime(2025, 9, 9));
      expect(r.shelfLife, const ShelfLife(18, ShelfLifeUnit.month));
      expect(r.printedExpiry, isNull);
    });

    test('unlabelled pair of sprayed dates: earlier is production', () {
      final r = parse(['20250301', '20270228']);
      expect(r.productionDate, DateTime(2025, 3, 1));
      expect(r.printedExpiry, DateTime(2027, 2, 28));
    });

    test('ignores after-opening durations', () {
      final r = parse(['生产日期 2025.10.01', '保质期:未开封36个月,开封后12个月']);
      expect(r.shelfLife, const ShelfLife(36, ShelfLifeUnit.month));
      final r2 = parse(['生产日期 2025.10.01', '开封后请于6个月内用完']);
      expect(r2.shelfLife, isNull);
    });

    test('OCR letter confusions inside numbers are fixed', () {
      final r = parse(['生产日期:2O25.O8.l2', '保质期:24个月']);
      expect(r.productionDate, DateTime(2025, 8, 12));
    });

    test('nothing to find', () {
      final r = parse(['名创优品', '香氛蜡烛', '净含量：200g']);
      expect(r.isEmpty, isTrue);
      expect(r.lastDay, isNull);
    });
  });

  group('product name guess', () {
    test('uses a 品名 label when present', () {
      expect(parse(['品名：柔软抽纸', '生产日期 2025.01.01']).name, '柔软抽纸');
      expect(parse(['产品名称', '玫瑰香氛护手霜']).name, '玫瑰香氛护手霜');
    });

    test('otherwise picks the largest Chinese line that is not boilerplate', () {
      final r = parse(
        ['名创优品', '海洋香氛洗发水', '生产日期：2025.01.01', '地址：广州市荔湾区', '净含量：500mL'],
        heights: [60, 48, 20, 18, 18],
      );
      expect(r.name, '海洋香氛洗发水');
    });
  });

  group('saved items', () {
    ExpiryItem item(DateTime expiry, {DateTime? production, ShelfLife? shelf}) => ExpiryItem(
          id: 1,
          name: '护手霜',
          productionDate: production,
          shelfLife: shelf,
          expiryDate: expiry,
          createdAt: now,
          updatedAt: now,
        );

    test('editing keeps computed expiry dates computed', () {
      const shelf = ShelfLife(12, ShelfLifeUnit.month);
      final computed = ExpiryDraft.of(item(DateTime(2026, 2, 28), production: DateTime(2025, 3, 1), shelf: shelf));
      expect(computed.printedExpiry, isNull);
      expect(computed.lastDay, DateTime(2026, 2, 28));
      final printed = ExpiryDraft.of(item(DateTime(2026, 1, 31), production: DateTime(2025, 3, 1), shelf: shelf));
      expect(printed.printedExpiry, DateTime(2026, 1, 31));
    });

    test('CSV export lists status and remaining time', () {
      final csv = buildExpiryCsv([item(DateTime(2026, 2, 1))], now: now);
      expect(csv, contains('1,1个月内到期,护手霜,,,,2026-02-01,剩 17 天,'));
    });
  });

  test('normalizeLine', () {
    expect(normalizeLine('生 产 日 期：２０２５'), '生产日期:2025');
    expect(normalizeLine('MINISO Oil'), 'MINISO Oil');
  });
}
