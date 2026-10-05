/// One stock-take (盘点单). Quantities only accumulate within a sheet.
class StockSheet {
  const StockSheet({
    required this.id,
    required this.name,
    this.store = '',
    this.area = '',
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.lineCount = 0,
    this.totalQty = 0,
  });

  final int id;
  final String name;
  final String store;
  final String area;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Number of distinct codes in the sheet.
  final int lineCount;

  /// Sum of all quantities.
  final int totalQty;

  String get place => [store, area].where((s) => s.isNotEmpty).join(' · ');

  factory StockSheet.fromMap(Map<String, Object?> m) => StockSheet(
        id: m['id'] as int,
        name: m['name'] as String,
        store: (m['store'] as String?) ?? '',
        area: (m['area'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
        lineCount: (m['line_count'] as int?) ?? 0,
        totalQty: (m['total_qty'] as int?) ?? 0,
      );
}

/// A counted code within a sheet, joined with its product details if known.
class SheetItem {
  const SheetItem({
    required this.id,
    required this.sheetId,
    required this.barcode,
    this.format = '',
    required this.qty,
    required this.firstSeen,
    required this.lastSeen,
    this.note = '',
    this.name = '',
  });

  final int id;
  final int sheetId;
  final String barcode;
  final String format;
  final int qty;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final String note;
  final String name;

  bool get hasName => name.isNotEmpty;

  factory SheetItem.fromMap(Map<String, Object?> m) => SheetItem(
        id: m['id'] as int,
        sheetId: m['sheet_id'] as int,
        barcode: m['barcode'] as String,
        format: (m['format'] as String?) ?? '',
        qty: m['qty'] as int,
        firstSeen: DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
        note: (m['note'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
      );
}
