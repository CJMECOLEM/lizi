final _digitsOnly = RegExp(r'^\d+$');

bool isDigits(String s) => s.isNotEmpty && _digitsOnly.hasMatch(s);

/// GS1 mod-10 check digit for [body] (all digits except the check digit).
int gtinCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final d = body.codeUnitAt(body.length - 1 - i) - 0x30;
    sum += i.isEven ? d * 3 : d;
  }
  return (10 - sum % 10) % 10;
}

/// True for an 8/12/13/14-digit GTIN whose last digit is a correct check digit.
bool isValidGtin(String code) {
  if (!isDigits(code)) return false;
  if (code.length != 8 && code.length != 12 && code.length != 13 && code.length != 14) {
    return false;
  }
  final body = code.substring(0, code.length - 1);
  return gtinCheckDigit(body) == code.codeUnitAt(code.length - 1) - 0x30;
}

/// One spelling per trade item, so the same product matches no matter how a
/// scanner or a spreadsheet wrote it: UPC-A (12 digits) and GTIN-14 with a
/// leading 0 both become the 13-digit form. Anything else is returned as is.
String canonicalCode(String code) {
  final c = code.trim();
  if (!isDigits(c)) return c;
  if (c.length == 12 && isValidGtin(c)) return '0$c';
  if (c.length == 14 && c.startsWith('0') && isValidGtin(c)) return c.substring(1);
  return c;
}

/// For a GTIN-14 whose packaging indicator (first digit) is 1–8, i.e. an outer
/// case, returns the GTIN-13 of the unit inside. GS1 builds case codes by
/// prefixing the unit code and recomputing the check digit, so this is only a
/// best guess: some suppliers assign unrelated case codes.
String? unitCodeOfCase(String gtin14) {
  if (gtin14.length != 14 || !isValidGtin(gtin14)) return null;
  final indicator = gtin14.codeUnitAt(0) - 0x30;
  if (indicator < 1 || indicator > 8) return null;
  final body = gtin14.substring(1, 13);
  return '$body${gtinCheckDigit(body)}';
}

bool isCaseGtin(String gtin14) => unitCodeOfCase(gtin14) != null;
