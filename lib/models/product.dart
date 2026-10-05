import '../expiry/expiry_math.dart';

const defaultUnit = '件';

String stockUnit(String value) =>
    value.trim().isEmpty ? defaultUnit : value.trim();

/// What the app remembers about a barcode: the name and shelf life entered or
/// recognised the last time, so the next check of the same product only needs
/// the production date.
class Product {
  const Product({
    required this.barcode,
    this.name = '',
    this.shelfLife,
    this.unit = defaultUnit,
  });

  /// Canonical barcode (see `canonicalCode`).
  final String barcode;
  final String name;
  final ShelfLife? shelfLife;
  final String unit;

  factory Product.fromMap(Map<String, Object?> m) => Product(
    barcode: m['barcode'] as String,
    name: (m['name'] as String?) ?? '',
    shelfLife: ShelfLife.fromCode(m['shelf_life'] as String?),
    unit: stockUnit((m['unit'] as String?) ?? ''),
  );
}
