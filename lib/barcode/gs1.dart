import 'gtin.dart';

/// ASCII group separator; scanners report the GS1 FNC1 separator as this.
const groupSeparator = '\x1d';

/// Parsed GS1 application identifiers (AI → value), e.g. from a GS1-128
/// logistics label or a GS1 QR / Data Matrix code.
class Gs1Data {
  const Gs1Data(this.fields);

  final Map<String, String> fields;

  String? get sscc => fields['00'];
  String? get gtin => fields['01'];

  /// GTIN of the trade items contained in a logistic unit (used with AI 37).
  String? get containedGtin => fields['02'];
  String? get batch => fields['10'];
  String? get serial => fields['21'];
  DateTime? get productionDate => parseGs1Date(fields['11']);
  DateTime? get bestBefore => parseGs1Date(fields['15']);
  DateTime? get expiry => parseGs1Date(fields['17']);

  /// Item count printed on the label: AI 37 (items in a logistic unit) or
  /// AI 30 (variable count).
  int? get count {
    final v = fields['37'] ?? fields['30'];
    final n = v == null ? null : int.tryParse(v);
    return n == null || n <= 0 ? null : n;
  }

  /// Short Chinese summary of the fields useful in a store, for display.
  String describe() {
    String d(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return [
      if (batch != null) '批号 $batch',
      if (productionDate != null) '生产 ${d(productionDate!)}',
      if (bestBefore != null) '保质期至 ${d(bestBefore!)}',
      if (expiry != null) '有效期至 ${d(expiry!)}',
      if (count != null) '数量 $count',
    ].join(' · ');
  }
}

class _AiSpec {
  const _AiSpec(this.length, {this.variable = false, this.numeric = false});

  /// Exact data length when fixed, maximum length when [variable].
  final int length;
  final bool variable;
  final bool numeric;
}

const _fixedDate = _AiSpec(6, numeric: true);

const _twoDigit = <String, _AiSpec>{
  '00': _AiSpec(18, numeric: true),
  '01': _AiSpec(14, numeric: true),
  '02': _AiSpec(14, numeric: true),
  '10': _AiSpec(20, variable: true),
  '11': _fixedDate,
  '12': _fixedDate,
  '13': _fixedDate,
  '15': _fixedDate,
  '16': _fixedDate,
  '17': _fixedDate,
  '20': _AiSpec(2, numeric: true),
  '21': _AiSpec(20, variable: true),
  '22': _AiSpec(20, variable: true),
  '30': _AiSpec(8, variable: true, numeric: true),
  '37': _AiSpec(8, variable: true, numeric: true),
  '90': _AiSpec(30, variable: true),
  '91': _AiSpec(90, variable: true),
  '92': _AiSpec(90, variable: true),
  '93': _AiSpec(90, variable: true),
  '94': _AiSpec(90, variable: true),
  '95': _AiSpec(90, variable: true),
  '96': _AiSpec(90, variable: true),
  '97': _AiSpec(90, variable: true),
  '98': _AiSpec(90, variable: true),
  '99': _AiSpec(90, variable: true),
};

const _threeDigit = <String, _AiSpec>{
  '235': _AiSpec(28, variable: true),
  '240': _AiSpec(30, variable: true),
  '241': _AiSpec(30, variable: true),
  '242': _AiSpec(6, variable: true, numeric: true),
  '243': _AiSpec(20, variable: true),
  '250': _AiSpec(30, variable: true),
  '251': _AiSpec(30, variable: true),
  '253': _AiSpec(30, variable: true),
  '254': _AiSpec(20, variable: true),
  '255': _AiSpec(25, variable: true, numeric: true),
  '400': _AiSpec(30, variable: true),
  '401': _AiSpec(30, variable: true),
  '402': _AiSpec(17, numeric: true),
  '403': _AiSpec(30, variable: true),
  '410': _AiSpec(13, numeric: true),
  '411': _AiSpec(13, numeric: true),
  '412': _AiSpec(13, numeric: true),
  '413': _AiSpec(13, numeric: true),
  '414': _AiSpec(13, numeric: true),
  '415': _AiSpec(13, numeric: true),
  '416': _AiSpec(13, numeric: true),
  '417': _AiSpec(13, numeric: true),
  '420': _AiSpec(20, variable: true),
  '421': _AiSpec(12, variable: true),
  '422': _AiSpec(3, numeric: true),
  '423': _AiSpec(15, variable: true, numeric: true),
  '424': _AiSpec(3, numeric: true),
  '425': _AiSpec(15, variable: true, numeric: true),
  '426': _AiSpec(3, numeric: true),
  '427': _AiSpec(3, variable: true),
};

const _fourDigit = <String, _AiSpec>{
  '7001': _AiSpec(13, numeric: true),
  '7002': _AiSpec(30, variable: true),
  '7003': _AiSpec(10, numeric: true),
  '7004': _AiSpec(4, variable: true, numeric: true),
  '7005': _AiSpec(12, variable: true),
  '7006': _fixedDate,
  '7007': _AiSpec(12, variable: true, numeric: true),
  '7008': _AiSpec(3, variable: true),
  '7009': _AiSpec(10, variable: true),
  '7010': _AiSpec(2, variable: true),
  '8001': _AiSpec(14, numeric: true),
  '8002': _AiSpec(20, variable: true),
  '8003': _AiSpec(30, variable: true),
  '8004': _AiSpec(30, variable: true),
  '8005': _AiSpec(6, numeric: true),
  '8006': _AiSpec(18, numeric: true),
  '8007': _AiSpec(34, variable: true),
  '8008': _AiSpec(12, variable: true, numeric: true),
  '8009': _AiSpec(50, variable: true),
  '8010': _AiSpec(30, variable: true),
  '8011': _AiSpec(12, variable: true, numeric: true),
  '8012': _AiSpec(20, variable: true),
  '8013': _AiSpec(25, variable: true),
  '8017': _AiSpec(18, numeric: true),
  '8018': _AiSpec(18, numeric: true),
  '8019': _AiSpec(10, variable: true, numeric: true),
  '8020': _AiSpec(25, variable: true),
  '8026': _AiSpec(18, numeric: true),
  '8110': _AiSpec(70, variable: true),
  '8111': _AiSpec(4, numeric: true),
  '8112': _AiSpec(70, variable: true),
  '8200': _AiSpec(70, variable: true),
};

_AiSpec? _specFor(String ai) {
  switch (ai.length) {
    case 2:
      return _twoDigit[ai];
    case 3:
      return _threeDigit[ai];
    case 4:
      if (!isDigits(ai)) return null;
      // 310n–369n: trade and logistic measures, n = decimal places.
      final head = int.parse(ai.substring(0, 2));
      if (head >= 31 && head <= 36) return const _AiSpec(6, numeric: true);
      // 390n–393n: amounts payable; 394n: coupon percentage; 395n: price per unit.
      final head3 = ai.substring(0, 3);
      if (head3 == '390' || head3 == '391' || head3 == '392' || head3 == '393') {
        return const _AiSpec(18, variable: true, numeric: true);
      }
      if (head3 == '394') return const _AiSpec(4, numeric: true);
      if (head3 == '395') return const _AiSpec(6, numeric: true);
      return _fourDigit[ai];
  }
  return null;
}

String? _matchAi(String s, int pos) {
  // GS1 AIs are prefix-free, so the first length that matches is the AI.
  for (final len in const [2, 3, 4]) {
    if (pos + len > s.length) return null;
    final ai = s.substring(pos, pos + len);
    if (_specFor(ai) != null) return ai;
  }
  return null;
}

bool _valueFits(_AiSpec spec, String value) {
  if (value.isEmpty) return false;
  if (spec.variable ? value.length > spec.length : value.length != spec.length) {
    return false;
  }
  return !spec.numeric || isDigits(value);
}

Map<String, String>? _parseElementString(String s) {
  final out = <String, String>{};
  var pos = 0;
  while (pos < s.length) {
    if (s[pos] == groupSeparator) {
      pos++;
      continue;
    }
    final ai = _matchAi(s, pos);
    if (ai == null) return null;
    final spec = _specFor(ai)!;
    pos += ai.length;
    String value;
    if (spec.variable) {
      var end = s.indexOf(groupSeparator, pos);
      if (end < 0) end = s.length;
      value = s.substring(pos, end);
      pos = end;
    } else {
      if (pos + spec.length > s.length) return null;
      value = s.substring(pos, pos + spec.length);
      pos += spec.length;
    }
    if (!_valueFits(spec, value)) return null;
    out[ai] = value;
  }
  return out.isEmpty ? null : out;
}

final _bracketed = RegExp(r'\((\d{2,4})\)([^(]*)');

/// Human-readable form, e.g. "(01)06901234567892(17)270131(10)A12".
Map<String, String>? _parseBracketed(String s) {
  final out = <String, String>{};
  var consumed = 0;
  for (final m in _bracketed.allMatches(s)) {
    if (m.start != consumed) return null;
    consumed = m.end;
    final ai = m.group(1)!;
    final value = m.group(2)!.trim();
    final spec = _specFor(ai);
    if (spec == null || !_valueFits(spec, value)) return null;
    out[ai] = value;
  }
  if (consumed != s.length || out.isEmpty) return null;
  return out;
}

/// GS1 Digital Link, e.g. "https://id.gs1.org/01/06901234567892/10/A12?17=270131".
Map<String, String>? _parseDigitalLink(String s) {
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final segs = uri.pathSegments;
  final i = segs.indexOf('01');
  if (i < 0 || i + 1 >= segs.length) return null;
  final g = segs[i + 1];
  if (!isDigits(g) || g.length > 14) return null;
  final gtin = g.padLeft(14, '0');
  if (!isValidGtin(gtin)) return null;
  final out = <String, String>{'01': gtin};
  for (var j = i + 2; j + 1 < segs.length; j += 2) {
    final spec = _specFor(segs[j]);
    if (spec != null && _valueFits(spec, segs[j + 1])) out[segs[j]] = segs[j + 1];
  }
  uri.queryParameters.forEach((k, v) {
    final spec = _specFor(k);
    if (spec != null && _valueFits(spec, v)) out[k] = v;
  });
  return out;
}

bool _validMod10(String code) =>
    isDigits(code) &&
    code.length >= 2 &&
    gtinCheckDigit(code.substring(0, code.length - 1)) ==
        code.codeUnitAt(code.length - 1) - 0x30;

const _symbologyIds = [']C1', ']e0', ']d2', ']Q3', ']J1'];

/// Parses GS1 data from a scanned value, or returns null if it is not GS1.
///
/// Plain Code 128 values are only accepted as GS1 when they contain an
/// identification key (SSCC or GTIN) with a valid check digit, so ordinary
/// internal codes that happen to start with "10" or "21" are not misread.
Gs1Data? parseGs1(String raw) {
  var s = raw.trim();
  var explicit = false;
  for (final id in _symbologyIds) {
    if (s.startsWith(id)) {
      s = s.substring(id.length);
      explicit = true;
      break;
    }
  }
  if (s.startsWith(groupSeparator)) {
    s = s.substring(1);
    explicit = true;
  }
  if (s.isEmpty) return null;

  Map<String, String>? fields;
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    fields = _parseDigitalLink(s);
  } else if (s.startsWith('(')) {
    fields = _parseBracketed(s);
    explicit = true;
  } else {
    fields = _parseElementString(s);
  }
  if (fields == null) return null;

  for (final key in const ['00', '01', '02']) {
    final v = fields[key];
    if (v != null && !_validMod10(v)) return null;
  }
  final hasKey = fields.containsKey('00') || fields.containsKey('01') || fields.containsKey('02');
  if (!explicit && !hasKey) return null;
  return Gs1Data(fields);
}

/// GS1 dates are YYMMDD; DD = 00 means the last day of the month. The century
/// follows the GS1 sliding window around the current year.
DateTime? parseGs1Date(String? v, {DateTime? now}) {
  if (v == null || v.length != 6 || !isDigits(v)) return null;
  final yy = int.parse(v.substring(0, 2));
  final mm = int.parse(v.substring(2, 4));
  final dd = int.parse(v.substring(4, 6));
  if (mm < 1 || mm > 12) return null;
  final current = (now ?? DateTime.now()).year;
  var year = current ~/ 100 * 100 + yy;
  final diff = yy - current % 100;
  if (diff >= 51) {
    year -= 100;
  } else if (diff <= -50) {
    year += 100;
  }
  final lastDay = DateTime(year, mm + 1, 0).day;
  final day = dd == 0 ? lastDay : dd;
  if (day > lastDay) return null;
  return DateTime(year, mm, day);
}
