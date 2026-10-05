import 'gs1.dart';
import 'gtin.dart';

enum Symbology {
  ean13('EAN-13'),
  ean8('EAN-8'),
  upcA('UPC-A'),
  upcE('UPC-E'),
  code128('Code 128'),
  code39('Code 39'),
  code93('Code 93'),
  codabar('Codabar'),
  itf('ITF'),
  qr('二维码'),
  dataMatrix('Data Matrix'),
  pdf417('PDF417'),
  aztec('Aztec'),
  dataBar('DataBar'),
  other('其他');

  const Symbology(this.label);
  final String label;

  /// 2D and GS1-capable symbologies can carry GS1 application identifiers.
  bool get mayCarryGs1 =>
      this == code128 || this == qr || this == dataMatrix || this == dataBar || this == other;
}

enum ScanKind {
  /// A sellable unit, counted under its own barcode.
  item,

  /// An outer case; the count is multiplied by the units per case.
  outerCase,

  /// Anything else (internal codes, URLs, plain text), counted as scanned.
  other,
}

class ResolvedScan {
  const ResolvedScan({
    required this.raw,
    required this.symbology,
    required this.kind,
    required this.key,
    this.caseCode,
    this.gs1,
    this.multiplier = 1,
  });

  final String raw;
  final Symbology symbology;
  final ScanKind kind;

  /// Code the quantity is counted under: the unit barcode for items and
  /// cases, the scanned content otherwise.
  final String key;

  /// The outer case code, when [kind] is [ScanKind.outerCase].
  final String? caseCode;

  final Gs1Data? gs1;

  /// How many items (or cases, for [ScanKind.outerCase]) one scan stands for.
  /// Taken from a GS1 count (AI 37 / 30) when the label carries one.
  final int multiplier;
}

/// Decides what a scanned value means for counting. Returns null for values
/// that fail their check digit, which are almost always misreads.
ResolvedScan? resolveScan(String raw, Symbology symbology) {
  final v = raw.trim();
  if (v.isEmpty) return null;

  ResolvedScan item(String key, {Gs1Data? gs1, int multiplier = 1}) => ResolvedScan(
        raw: v,
        symbology: symbology,
        kind: ScanKind.item,
        key: key,
        gs1: gs1,
        multiplier: multiplier,
      );

  ResolvedScan fromGtin(String gtin, {Gs1Data? gs1, int multiplier = 1}) {
    final unit = gtin.length == 14 ? unitCodeOfCase(gtin) : null;
    if (unit == null) return item(canonicalCode(gtin), gs1: gs1, multiplier: multiplier);
    return ResolvedScan(
      raw: v,
      symbology: symbology,
      kind: ScanKind.outerCase,
      key: unit,
      caseCode: gtin,
      gs1: gs1,
      multiplier: multiplier,
    );
  }

  ResolvedScan other() => ResolvedScan(
        raw: v,
        symbology: symbology,
        kind: ScanKind.other,
        key: v.replaceAll(groupSeparator, ' ').trim(),
      );

  switch (symbology) {
    case Symbology.ean13:
    case Symbology.ean8:
    case Symbology.upcA:
      return isValidGtin(v) ? item(canonicalCode(v)) : null;
    case Symbology.upcE:
      return isDigits(v) ? item(v) : null;
    case Symbology.itf:
      if (v.length == 14) return isValidGtin(v) ? fromGtin(v) : null;
      return other();
    default:
      break;
  }

  if (symbology.mayCarryGs1) {
    final gs1 = parseGs1(v);
    if (gs1 != null) {
      final gtin = gs1.containedGtin ?? gs1.gtin;
      if (gtin == null) return other();
      return fromGtin(gtin, gs1: gs1, multiplier: gs1.count ?? 1);
    }
  }
  // Some labels print a plain GTIN in Code 128.
  if (symbology == Symbology.code128 && isValidGtin(v)) return fromGtin(v);
  return other();
}
