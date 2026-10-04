enum RecordType {
  barcode('条码'),
  text('文字');

  const RecordType(this.label);
  final String label;

  static RecordType fromName(String name) =>
      RecordType.values.firstWhere((t) => t.name == name, orElse: () => text);
}

class ScanRecord {
  ScanRecord({
    this.id,
    required this.type,
    required this.content,
    this.format = '',
    this.count = 1,
    required this.firstSeen,
    required this.lastSeen,
  });

  final int? id;
  final RecordType type;
  final String content;

  /// Barcode symbology (e.g. EAN-13); empty for text.
  final String format;
  int count;
  final DateTime firstSeen;
  DateTime lastSeen;

  String get key => '${type.name}|$content';

  factory ScanRecord.fromMap(Map<String, Object?> m) => ScanRecord(
        id: m['id'] as int?,
        type: RecordType.fromName(m['type'] as String),
        content: m['content'] as String,
        format: (m['format'] as String?) ?? '',
        count: m['count'] as int,
        firstSeen: DateTime.fromMillisecondsSinceEpoch(m['first_seen'] as int),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
      );
}
