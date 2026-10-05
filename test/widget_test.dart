import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lizi/models/scan_record.dart';
import 'package:lizi/scan/occurrence_tracker.dart';
import 'package:lizi/scan/text_filter.dart';
import 'package:lizi/scan/viewfinder.dart';
import 'package:lizi/services/exporter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('OccurrenceTracker', () {
    test('counts after confirmation and not again while visible', () {
      final t = OccurrenceTracker(confirmFrames: 2);
      expect(t.update(['A'], at(0)), isEmpty);
      expect(t.update(['A'], at(100)), ['A']);
      for (var ms = 200; ms < 3000; ms += 100) {
        expect(t.update(['A'], at(ms)), isEmpty);
      }
    });

    test('counts again only after leaving the frame', () {
      final t = OccurrenceTracker(
        confirmFrames: 2,
        goneAfter: const Duration(milliseconds: 800),
      );
      t.update(['A'], at(0));
      expect(t.update(['A'], at(100)), ['A']);
      // Brief dropout shorter than goneAfter does not count as leaving.
      expect(t.update([], at(500)), isEmpty);
      expect(t.update(['A'], at(700)), isEmpty);
      // Absent long enough, then reappears.
      expect(t.update([], at(1600)), isEmpty);
      expect(t.update(['A'], at(1700)), isEmpty);
      expect(t.update(['A'], at(1800)), ['A']);
    });

    test('single-frame misreads are not counted', () {
      final t = OccurrenceTracker(confirmFrames: 2);
      expect(t.update(['noise'], at(0)), isEmpty);
      expect(t.update(['A'], at(100)), isEmpty);
      expect(t.update(['A'], at(200)), ['A']);
      expect(t.update(['A'], at(2000)), isEmpty);
    });
  });

  group('viewfinder mapping', () {
    test('upright size is portrait regardless of buffer orientation', () {
      expect(uprightImageSize(const Size(1920, 1080)), const Size(1080, 1920));
      expect(uprightImageSize(const Size(1080, 1920)), const Size(1080, 1920));
    });

    test('maps screen rect into image space under BoxFit.cover', () {
      // Image 1080x1920 shown on a 540x600 area: scale 0.5, cropped vertically.
      const screen = Size(540, 600);
      const image = Size(1080, 1920);
      final full = screenRectToImage(Offset.zero & screen, screen, image);
      expect(full.left, closeTo(0, 0.01));
      expect(full.right, closeTo(1080, 0.01));
      expect(full.top, closeTo(360, 0.01));
      expect(full.bottom, closeTo(1560, 0.01));
    });
  });

  group('OCR text filter', () {
    test('removes spaces between Chinese characters', () {
      expect(normalizeOcrLine(' 生 产 日期  2026 01 '), '生产日期2026 01');
    });

    test('keeps digits or Chinese with at least two characters', () {
      expect(isUsefulOcrLine('12'), isTrue);
      expect(isUsefulOcrLine('中文'), isTrue);
      expect(isUsefulOcrLine('7'), isFalse);
      expect(isUsefulOcrLine('ab'), isFalse);
    });
  });

  test('CSV export escapes fields and includes BOM', () {
    final csv = buildCsv([
      ScanRecord(
        type: RecordType.text,
        content: '含,逗号"引号',
        count: 3,
        firstSeen: t0,
        lastSeen: t0,
      ),
    ]);
    expect(csv.startsWith('\uFEFF类型,内容'), isTrue);
    expect(csv, contains('文字,"含,逗号""引号",,3,2026-01-01 12:00:00'));
  });

  test('Excel export produces a non-empty xlsx', () {
    final bytes = buildXlsx([
      ScanRecord(
        type: RecordType.barcode,
        content: '6901234567892',
        format: 'EAN-13',
        firstSeen: t0,
        lastSeen: t0,
      ),
    ]);
    // xlsx is a zip archive: starts with "PK".
    expect(bytes.take(2), [0x50, 0x4B]);
  });
}
