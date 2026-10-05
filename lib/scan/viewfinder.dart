import 'dart:math' as math;
import 'dart:ui';

/// Upright (portrait) size of a camera frame. The app is portrait-locked and
/// ML Kit reports coordinates in the upright image, so the short side is the
/// width regardless of how the sensor delivers the buffer.
Size uprightImageSize(Size raw) => Size(
      math.min(raw.width, raw.height),
      math.max(raw.width, raw.height),
    );

/// Converts a rectangle on screen into image coordinates, assuming the
/// preview fills [screen] with BoxFit.cover.
Rect screenRectToImage(Rect onScreen, Size screen, Size uprightImage) {
  final scale = math.max(
    screen.width / uprightImage.width,
    screen.height / uprightImage.height,
  );
  final dx = (screen.width - uprightImage.width * scale) / 2;
  final dy = (screen.height - uprightImage.height * scale) / 2;
  return Rect.fromLTRB(
    (onScreen.left - dx) / scale,
    (onScreen.top - dy) / scale,
    (onScreen.right - dx) / scale,
    (onScreen.bottom - dy) / scale,
  );
}

/// Barcode scan window: wide enough for long 1D codes, tall enough for QR
/// codes, centered slightly above the middle where the thumb does not cover.
Rect barcodeViewfinderRect(Size screen) {
  final width = screen.width * 0.8;
  final height = math.min(width * 0.62, screen.height * 0.5);
  final center = Offset(screen.width / 2, screen.height * 0.45);
  return Rect.fromCenter(center: center, width: width, height: height);
}

/// Viewfinder used in text mode: a wide band slightly above center.
Rect textViewfinderRect(Size screen) {
  final width = screen.width * 0.86;
  final height = math.min(screen.height * 0.18, 160.0);
  final center = Offset(screen.width / 2, screen.height * 0.38);
  return Rect.fromCenter(center: center, width: width, height: height);
}
