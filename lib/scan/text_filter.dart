final _whitespace = RegExp(r'\s+');
final _spaceAroundCjk = RegExp(r'(?<=[\u4e00-\u9fff])\s+|\s+(?=[\u4e00-\u9fff])');
final _digitOrCjk = RegExp(r'[0-9\u4e00-\u9fff]');

/// Normalizes an OCR line so tiny spacing differences between frames do not
/// look like different results. OCR often inserts spaces between Chinese
/// characters; those are dropped.
String normalizeOcrLine(String raw) =>
    raw.replaceAll(_whitespace, ' ').replaceAll(_spaceAroundCjk, '').trim();

/// Keeps lines that contain digits or Chinese and are long enough to be
/// meaningful; single stray characters are usually noise.
bool isUsefulOcrLine(String line) =>
    line.runes.length >= 2 && _digitOrCjk.hasMatch(line);
