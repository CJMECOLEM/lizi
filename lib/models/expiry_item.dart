import '../expiry/expiry_math.dart';

/// One checked product batch and its last good day.
class ExpiryItem {
  const ExpiryItem({
    this.id,
    this.barcode = '',
    this.name = '',
    this.productionDate,
    this.shelfLife,
    required this.expiryDate,
    this.photo = '',
    this.ocrText = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String barcode;
  final String name;
  final DateTime? productionDate;
  final ShelfLife? shelfLife;

  /// Last good day.
  final DateTime expiryDate;

  /// Path of the saved photo, empty if none.
  final String photo;

  /// Recognised text, one line per line.
  final String ocrText;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get title => name.isNotEmpty ? name : (barcode.isNotEmpty ? barcode : '未命名商品');

  ExpiryLevel levelAt(DateTime now) => expiryLevel(expiryDate, now);

  ExpiryItem copyWith({int? id, String? photo, DateTime? updatedAt}) => ExpiryItem(
        id: id ?? this.id,
        barcode: barcode,
        name: name,
        productionDate: productionDate,
        shelfLife: shelfLife,
        expiryDate: expiryDate,
        photo: photo ?? this.photo,
        ocrText: ocrText,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'barcode': barcode,
        'name': name,
        'production_date': productionDate == null ? '' : formatDate(productionDate!),
        'shelf_life': shelfLife?.code ?? '',
        'expiry_date': formatDate(expiryDate),
        'photo': photo,
        'ocr_text': ocrText,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ExpiryItem.fromMap(Map<String, Object?> m) => ExpiryItem(
        id: m['id'] as int,
        barcode: (m['barcode'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        productionDate: parseStoredDate(m['production_date'] as String?),
        shelfLife: ShelfLife.fromCode(m['shelf_life'] as String?),
        expiryDate: parseStoredDate(m['expiry_date'] as String?) ?? DateTime(2000),
        photo: (m['photo'] as String?) ?? '',
        ocrText: (m['ocr_text'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}
