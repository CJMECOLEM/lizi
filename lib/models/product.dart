import '../expiry/expiry_math.dart';

/// What the app remembers about a barcode: the name and shelf life entered or
/// recognised the last time, so the next check of the same product only needs
/// the production date.
class Product {
  const Product({required this.barcode, this.name = '', this.shelfLife});

  /// Canonical barcode (see `canonicalCode`).
  final String barcode;
  final String name;
  final ShelfLife? shelfLife;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        barcode: m['barcode'] as String,
        name: (m['name'] as String?) ?? '',
        shelfLife: ShelfLife.fromCode(m['shelf_life'] as String?),
      );
}
