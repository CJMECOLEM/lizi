import 'package:flutter_test/flutter_test.dart';
import 'package:lizi/barcode/gs1.dart';
import 'package:lizi/barcode/gtin.dart';
import 'package:lizi/barcode/scan_resolver.dart';

void main() {
  group('GTIN', () {
    test('check digits', () {
      expect(isValidGtin('6901234567892'), isTrue);
      expect(isValidGtin('6901234567891'), isFalse);
      expect(isValidGtin('16901234567899'), isTrue);
    });

    test('canonical code and unit code of an outer case', () {
      expect(canonicalCode('06901234567892'), '6901234567892');
      expect(unitCodeOfCase('16901234567899'), '6901234567892');
      expect(unitCodeOfCase('06901234567892'), isNull);
    });
  });

  group('GS1', () {
    test('element string with expiry date', () {
      final d = parseGs1(']C1011690123456789917270531${groupSeparator}10AB12')!;
      expect(d.gtin, '16901234567899');
      expect(d.expiry, DateTime(2027, 5, 31));
      expect(d.batch, 'AB12');
    });

    test('bracketed form and last-day-of-month dates', () {
      final d = parseGs1('(01)06901234567892(17)261200')!;
      expect(d.expiry, DateTime(2026, 12, 31));
    });

    test('ordinary internal codes are not GS1', () {
      expect(parseGs1('1012345'), isNull);
    });
  });

  group('resolveScan', () {
    test('drops misreads failing the check digit', () {
      expect(resolveScan('6901234567891', Symbology.ean13), isNull);
    });

    test('retail barcode is an item', () {
      final r = resolveScan('6901234567892', Symbology.ean13)!;
      expect(r.kind, ScanKind.item);
      expect(r.key, '6901234567892');
    });

    test('ITF-14 case maps to the unit code', () {
      final r = resolveScan('16901234567899', Symbology.itf)!;
      expect(r.kind, ScanKind.outerCase);
      expect(r.key, '6901234567892');
      expect(r.caseCode, '16901234567899');
    });

    test('GS1 QR carries the expiry date', () {
      final r = resolveScan('(01)06901234567892(17)270131', Symbology.qr)!;
      expect(r.key, '6901234567892');
      expect(r.gs1?.expiry, DateTime(2027, 1, 31));
    });
  });
}
