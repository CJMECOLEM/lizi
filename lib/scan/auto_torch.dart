import 'dart:typed_data';

/// Average brightness (0–255) of a camera frame, estimated from a sparse
/// grid of sampled pixels.
///
/// [bgra] selects iOS BGRA8888 frames; otherwise the first plane is treated
/// as a luma (Y) plane, as with Android NV21/YUV420.
double averageLuma({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required bool bgra,
  int samplesPerAxis = 40,
}) {
  if (width <= 0 || height <= 0) return 0;
  final stepX = (width / samplesPerAxis).ceil().clamp(1, width);
  final stepY = (height / samplesPerAxis).ceil().clamp(1, height);
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < height; y += stepY) {
    final row = y * bytesPerRow;
    for (var x = 0; x < width; x += stepX) {
      if (bgra) {
        final i = row + x * 4;
        if (i + 2 >= bytes.length) continue;
        sum += 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
      } else {
        final i = row + x;
        if (i >= bytes.length) continue;
        sum += bytes[i];
      }
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Turns the torch on after the scene has stayed dark for [darkFor].
///
/// The torch itself brightens the scene, so the ambient light can no longer
/// be measured once it is on. For that reason the controller never turns the
/// torch off by itself; it stays on until the user switches it off or the
/// scanner is reset. After a manual "off" the controller stays quiet until
/// [reset], so it does not fight the user.
class AutoTorchController {
  AutoTorchController({
    this.darkThreshold = 45,
    this.darkFor = const Duration(milliseconds: 1200),
  });

  final double darkThreshold;
  final Duration darkFor;

  DateTime? _darkSince;
  bool _suppressed = false;

  /// Returns true when the torch should be switched on now.
  bool shouldTurnOn({
    required double luma,
    required DateTime now,
    required bool torchOn,
    required bool enabled,
  }) {
    if (!enabled || torchOn || _suppressed) {
      _darkSince = null;
      return false;
    }
    if (luma >= darkThreshold) {
      _darkSince = null;
      return false;
    }
    _darkSince ??= now;
    if (now.difference(_darkSince!) >= darkFor) {
      _darkSince = null;
      return true;
    }
    return false;
  }

  void userTurnedOff() {
    _suppressed = true;
    _darkSince = null;
  }

  void reset() {
    _suppressed = false;
    _darkSince = null;
  }
}
