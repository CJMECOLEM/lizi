import 'expiry_math.dart';

/// One recognised text line. [height] is the line's height in the photo and
/// stands in for font size when guessing the product name.
class OcrLine {
  const OcrLine(this.text, {this.height = 0});
  final String text;
  final double height;
}

class ExpiryParse {
  const ExpiryParse({
    this.productionDate,
    this.shelfLife,
    this.printedExpiry,
    this.name,
    this.lines = const [],
  });

  final DateTime? productionDate;
  final ShelfLife? shelfLife;

  /// Expiry date printed on the package (有效期至 / EXP …).
  final DateTime? printedExpiry;

  /// Best guess at the product name.
  final String? name;

  /// Normalised text lines, offered to the user to pick a name from.
  final List<String> lines;

  /// Last good day: the printed expiry date, else production date plus shelf
  /// life.
  DateTime? get lastDay {
    if (printedExpiry != null) return printedExpiry;
    final p = productionDate;
    final s = shelfLife;
    return p == null || s == null ? null : s.lastDayFrom(p);
  }

  bool get isEmpty => productionDate == null && shelfLife == null && printedExpiry == null;
}

// ---- Normalisation ----

final _cjkSpace = RegExp(r'(?<=[\u3400-\u9fff])\s+(?=[\u3400-\u9fff])');
final _spaces = RegExp(r'[ \t]+');
final _digitLike = RegExp(r'[0-9OoIl|]+(?:[.\-/][0-9OoIl|]+)*');

/// Full-width to half-width, unified punctuation, no spaces between Chinese
/// characters, and common OCR letter/digit confusions fixed inside numbers.
String normalizeLine(String s) {
  final sb = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      sb.writeCharCode(r - 0xFEE0);
    } else if (r == 0x3000) {
      sb.write(' ');
    } else if (r == 0x3002 || r == 0xFF61) {
      sb.write('.');
    } else if (r == 0x2014 || r == 0x2013 || r == 0x2212) {
      sb.write('-');
    } else {
      sb.writeCharCode(r);
    }
  }
  var t = sb.toString().replaceAll(_cjkSpace, '').replaceAll(_spaces, ' ').trim();
  t = t.replaceAllMapped(_digitLike, (m) {
    final v = m[0]!;
    final digits = v.codeUnits.where((c) => c >= 0x30 && c <= 0x39).length;
    if (digits < 4 || digits == v.replaceAll(RegExp(r'[.\-/]'), '').length) return v;
    return v.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[Il|]'), '1');
  });
  return t;
}

// ---- Dates ----

class _DateHit {
  _DateHit(this.start, this.end, this.date, {this.monthOnly = false});
  final int start;
  final int end;
  final DateTime date;
  final bool monthOnly;
  bool used = false;

  /// Month-only dates mean the start of the month for production and the end
  /// of the month for expiry.
  DateTime asExpiry() => monthOnly ? DateTime(date.year, date.month, daysInMonth(date.year, date.month)) : date;
}

const _ymdSep = r'(?:\s?[.\-/]\s?|\s?年\s?|\s)';
const _mdSep = r'(?:\s?[.\-/]\s?|\s?月\s?|\s)';

final _fullYmd = RegExp('(?<!\\d)(20\\d{2})$_ymdSep(\\d{1,2})$_mdSep(\\d{1,2})(?:\\s?日)?(?!\\d)');
final _compactYmd = RegExp(r'(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)');
final _dmy = RegExp(r'(?<!\d)(\d{1,2})[.\-/](\d{1,2})[.\-/](20\d{2})(?!\d)');
final _shortYmd = RegExp(r'(?<![\d.\-/])(\d{2})[.\-/](\d{2})[.\-/](\d{2})(?![\d.\-/])');
final _ym = RegExp(r'(?<!\d)(20\d{2})(?:\s?[.\-/]\s?|\s?年\s?)(\d{1,2})(?:\s?月)?(?![\d.\-/月])');
final _my = RegExp(r'(?<![\d.\-/])(\d{1,2})[.\-/](20\d{2})(?![\d.\-/])');
final _compactShort = RegExp(r'^(\d{2})(\d{2})(\d{2})(?!\d)');

DateTime? _validDate(int y, int m, int d, DateTime now) {
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  if (y < now.year - 15 || y > now.year + 30) return null;
  return DateTime(y, m, d);
}

List<_DateHit> _findDates(String text, DateTime now) {
  final hits = <_DateHit>[];
  bool free(int s, int e) => hits.every((h) => e <= h.start || s >= h.end);
  void add(RegExp re, DateTime? Function(RegExpMatch) toDate, {bool monthOnly = false}) {
    for (final m in re.allMatches(text)) {
      if (!free(m.start, m.end)) continue;
      final d = toDate(m);
      if (d != null) hits.add(_DateHit(m.start, m.end, d, monthOnly: monthOnly));
    }
  }

  int g(RegExpMatch m, int i) => int.parse(m[i]!);
  add(_fullYmd, (m) => _validDate(g(m, 1), g(m, 2), g(m, 3), now));
  add(_compactYmd, (m) => _validDate(g(m, 1), g(m, 2), g(m, 3), now));
  add(_dmy, (m) {
    final a = g(m, 1), b = g(m, 2), y = g(m, 3);
    // Imported goods print day first; a first part above 12 settles it.
    return a > 12 || b <= 12 ? _validDate(y, b, a, now) : _validDate(y, a, b, now);
  });
  add(_shortYmd, (m) {
    bool near(DateTime? d) => d != null && (d.year - now.year).abs() <= 10;
    // Chinese packages print YY.MM.DD; imported ones often DD.MM.YY.
    final ymd = _validDate(2000 + g(m, 1), g(m, 2), g(m, 3), now);
    if (near(ymd)) return ymd;
    final dmy = _validDate(2000 + g(m, 3), g(m, 2), g(m, 1), now);
    return near(dmy) ? dmy : null;
  });
  add(_ym, (m) => _validDate(g(m, 1), g(m, 2), 1, now), monthOnly: true);
  add(_my, (m) => _validDate(g(m, 2), g(m, 1), 1, now), monthOnly: true);
  hits.sort((a, b) => a.start.compareTo(b.start));
  return hits;
}

// ---- Shelf life ----

final _duration = RegExp(
  r'(\d{1,4}|[零一二两三四五六七八九十百]{1,5})\s*(个月|個月|ヶ月|か月|月|天|日|年|months?|days?|years?|(?<![A-Za-z])[MDY](?![A-Za-z]))',
  caseSensitive: false,
);

const _cnDigits = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};

int? _parseNumber(String s) {
  final n = int.tryParse(s);
  if (n != null) return n;
  var total = 0;
  var cur = 0;
  for (final ch in s.split('')) {
    final d = _cnDigits[ch];
    if (d != null) {
      cur = d;
    } else if (ch == '十') {
      total += (cur == 0 ? 1 : cur) * 10;
      cur = 0;
    } else if (ch == '百') {
      total += (cur == 0 ? 1 : cur) * 100;
      cur = 0;
    } else {
      return null;
    }
  }
  return total + cur;
}

ShelfLife? _shelfLifeOf(RegExpMatch m) {
  final n = _parseNumber(m[1]!);
  if (n == null || n <= 0) return null;
  final u = m[2]!.toLowerCase();
  final unit = switch (u) {
    '天' || '日' || 'd' || 'day' || 'days' => ShelfLifeUnit.day,
    '年' || 'y' || 'year' || 'years' => ShelfLifeUnit.year,
    _ => ShelfLifeUnit.month,
  };
  final max = switch (unit) { ShelfLifeUnit.day => 3650, ShelfLifeUnit.month => 120, ShelfLifeUnit.year => 10 };
  return n > max ? null : ShelfLife(n, unit);
}

final _beforeMarker = RegExp(r'^\s?(?:之前|以前|前|止)');

final _afterOpening = RegExp(r'(?<![未不])(开封|開封|开启|開啟|打开|开瓶|开袋|开盖)[^\n]{0,8}$');

// ---- Labels ----

enum _LabelKind { production, expiry, generic }

final _labels = RegExp(
  '(?<exp>有效期截止日期|有效期截止|有效期截至|有效期至|有效期到|保质期截止|保质期截至|保质期到期日|保质期至|保質期至|保质期到|'
  '有效日期|失效日期|失效期|到期日期|到期时间|到期日|限用日期|截止使用日期|截止日期|限期使用日期|使用期限至|使用期限|保存期限至|'
  '最佳食用日期|最佳食用期|最佳赏味期|赏味期限|賞味期限|消費期限|消费期限|'
  '(?<![A-Za-z])(?:EXPIR(?:Y|ES|ATION)(?:\\s?DATE)?|EXP\\.?\\s?(?:DATE)?|BBE|BBD|BB|BEST\\s?BEFORE(?:\\s?END)?|BEST\\s?BY|USE\\s?BEFORE|USE\\s?BY)(?![A-Za-z]))'
  '|(?<prod>生产日期|生產日期|制造日期|製造日期|製造年月日|生产时间|出厂日期|灌装日期|包装日期|加工日期|生产批号|'
  '生产(?![商者许厂地址企单])|製造(?![商者])|制造(?![商者])|(?<![A-Za-z])(?:MFG\\.?\\s?(?:DATE)?|MFD|PRD|PROD(?:UCTION)?\\.?\\s?DATE|DOM|P\\.?D)(?![A-Za-z]))'
  '|(?<gen>保质期|保質期|保存期限|保存期|有效期限|有效期|賞味期間|SHELF\\s?LIFE)',
  caseSensitive: false,
);

class _Label {
  _Label(this.kind, this.start, this.end);
  final _LabelKind kind;
  final int start;
  final int end;
}

List<_Label> _findLabels(String text) => [
      for (final m in _labels.allMatches(text))
        _Label(
          m.namedGroup('exp') != null
              ? _LabelKind.expiry
              : m.namedGroup('prod') != null
                  ? _LabelKind.production
                  : _LabelKind.generic,
          m.start,
          m.end,
        ),
    ];

/// The value of a label is looked for until the next label, at most 40
/// characters and one line break away.
int _windowEnd(String text, _Label label, List<_Label> labels) {
  var end = label.end + 40;
  if (end > text.length) end = text.length;
  final firstBreak = text.indexOf('\n', label.end);
  if (firstBreak >= 0 && firstBreak < end) {
    final secondBreak = text.indexOf('\n', firstBreak + 1);
    if (secondBreak >= 0 && secondBreak < end) end = secondBreak;
  }
  for (final l in labels) {
    if (l.start >= label.end && l.start < end) {
      end = l.start;
      break;
    }
  }
  return end;
}

// ---- Product name ----

final _nameLabel = RegExp(r'^(?:产品名称|商品名称|品名|名称|产品名|商品名|品名称)\s*[:：]?\s*(.*)$');
final _cjk = RegExp(r'[\u3400-\u9fff]');
final _notName = RegExp(
  r'生产|生產|日期|保质|保質|有效|期限|地址|电话|電話|配料|成分|净含量|淨含量|规格|規格|型号|执行标准|标准|产地|原产|'
  r'厂|公司|制造商|製造商|经销|經銷|委托|使用|注意|警告|储存|贮存|保存|批号|条码|许可|网址|客服|邮编|材质|合格|检验|'
  r'适用|方法|说明|营养|能量|蛋白质|脂肪|碳水|钠|进口|有限|电池|充电|输入|输出|额定|功率|电压|容量|尺寸|重量|颜色|货号|'
  r'售价|价格|零售价|扫码|官方|服务|热线|产品|材料|填充|面料|洗涤|安全|类别|等级|执行|备注|温馨|提示',
);
const _brands = {'名创优品', 'MINISO', 'miniso', '名創優品'};

String? _guessName(List<OcrLine> lines) {
  for (var i = 0; i < lines.length; i++) {
    final m = _nameLabel.firstMatch(lines[i].text);
    if (m == null) continue;
    final v = m[1]!.trim();
    if (v.length >= 2) return v;
    if (i + 1 < lines.length && lines[i + 1].text.length >= 2) return lines[i + 1].text;
  }
  OcrLine? best;
  var bestScore = 0.0;
  for (final l in lines) {
    final t = l.text;
    final cjk = _cjk.allMatches(t).length;
    if (cjk < 2 || t.length > 30 || _brands.contains(t) || _notName.hasMatch(t)) continue;
    if (RegExp(r'\d').allMatches(t).length > t.length / 2) continue;
    // Bigger text wins; Chinese-heavy lines win ties.
    final score = (l.height <= 0 ? 1 : l.height) * (1 + cjk / t.length);
    if (score > bestScore) {
      best = l;
      bestScore = score;
    }
  }
  return best?.text;
}

// ---- Entry point ----

ExpiryParse parseExpiry(List<OcrLine> rawLines, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final lines = [
    for (final l in rawLines)
      if (normalizeLine(l.text).isNotEmpty) OcrLine(normalizeLine(l.text), height: l.height),
  ];
  final text = lines.map((l) => l.text).join('\n');
  final dates = _findDates(text, today);
  final labels = _findLabels(text);

  DateTime? production;
  DateTime? expiry;
  ShelfLife? shelf;
  var genericExpiry = false;

  _DateHit? dateIn(int from, int to) {
    for (final h in dates) {
      if (!h.used && h.start >= from && h.start < to) return h;
    }
    return null;
  }

  ({ShelfLife life, int start})? durationIn(int from, int to) {
    for (final m in _duration.allMatches(text.substring(from, to))) {
      final s = from + m.start;
      final e = from + m.end;
      if (dates.any((h) => s < h.end && e > h.start)) continue;
      if (_afterOpening.hasMatch(text.substring(from, s))) continue;
      final life = _shelfLifeOf(m);
      if (life != null) return (life: life, start: s);
    }
    return null;
  }

  for (final label in labels) {
    final end = _windowEnd(text, label, labels);
    final hit = dateIn(label.end, end);
    switch (label.kind) {
      case _LabelKind.production:
        if (production != null) break;
        if (hit != null) {
          hit.used = true;
          production = hit.date;
        } else {
          final m = _compactShort.firstMatch(text.substring(label.end, end).trimLeft().replaceFirst(RegExp(r'^[:：]\s*'), ''));
          if (m != null) {
            production = _validDate(2000 + int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), today);
          }
        }
      case _LabelKind.expiry:
      case _LabelKind.generic:
        final dur = durationIn(label.end, end);
        final useDuration = dur != null && (hit == null || dur.start < hit.start);
        if (useDuration) {
          shelf ??= dur.life;
        } else if (hit != null && expiry == null) {
          hit.used = true;
          expiry = hit.asExpiry();
          genericExpiry = label.kind == _LabelKind.generic;
        }
    }
  }

  // "请于2027年3月15日前食用" / "2027.03.15之前使用": a date followed by 前/止
  // is an expiry date even without a label.
  if (expiry == null) {
    for (final h in dates) {
      if (h.used) continue;
      final after = text.substring(h.end, h.end + 4 > text.length ? text.length : h.end + 4);
      if (_beforeMarker.hasMatch(after)) {
        h.used = true;
        expiry = h.asExpiry();
        break;
      }
    }
  }

  shelf ??= () {
    for (final m in _duration.allMatches(text)) {
      final unit = m[2]!;
      if (!(unit.contains('月') || unit == '年' || unit.startsWith('month'))) continue;
      if (dates.any((h) => m.start < h.end && m.end > h.start)) continue;
      if (_afterOpening.hasMatch(text.substring(0, m.start))) continue;
      final life = _shelfLifeOf(m);
      if (life != null && (life.unit != ShelfLifeUnit.month || life.value >= 3)) return life;
    }
    return null;
  }();

  // "保质期 2025.03.01 … 12个月": with a shelf life present, a date next to a
  // generic label is the production date.
  if (genericExpiry && production == null && shelf != null) {
    production = expiry;
    expiry = null;
  }

  final free = dates.where((h) => !h.used).toList()..sort((a, b) => a.date.compareTo(b.date));
  if (production == null && expiry == null && free.isNotEmpty) {
    if (free.length >= 2 && free.last.date.isAfter(free.first.date)) {
      production = free.first.date;
      expiry = free.last.asExpiry();
    } else if (shelf != null || !free.first.date.isAfter(today)) {
      production = free.first.date;
    } else {
      expiry = free.first.asExpiry();
    }
  } else if (production == null && expiry != null) {
    final before = free.where((h) => h.date.isBefore(expiry!));
    if (before.isNotEmpty) production = before.first.date;
  } else if (production != null && expiry == null && shelf == null) {
    final after = free.where((h) => h.date.isAfter(production!));
    if (after.isNotEmpty) expiry = after.last.asExpiry();
  }

  return ExpiryParse(
    productionDate: production,
    shelfLife: shelf,
    printedExpiry: expiry,
    name: _guessName(lines),
    lines: [for (final l in lines) l.text],
  );
}
