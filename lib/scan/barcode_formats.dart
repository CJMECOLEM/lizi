import 'package:mobile_scanner/mobile_scanner.dart';

import '../barcode/scan_resolver.dart';

/// Retail and logistics symbologies. Fewer formats keep detection fast and
/// avoid misreading random patterns as rare codes.
const scanFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.codabar,
  BarcodeFormat.itf14,
  BarcodeFormat.qrCode,
  BarcodeFormat.dataMatrix,
];

Symbology symbologyOf(BarcodeFormat f) => switch (f) {
      BarcodeFormat.ean13 => Symbology.ean13,
      BarcodeFormat.ean8 => Symbology.ean8,
      BarcodeFormat.upcA => Symbology.upcA,
      BarcodeFormat.upcE => Symbology.upcE,
      BarcodeFormat.code128 => Symbology.code128,
      BarcodeFormat.code39 => Symbology.code39,
      BarcodeFormat.code93 => Symbology.code93,
      BarcodeFormat.codabar => Symbology.codabar,
      BarcodeFormat.itf14 ||
      BarcodeFormat.itf2of5 ||
      BarcodeFormat.itf2of5WithChecksum =>
        Symbology.itf,
      BarcodeFormat.qrCode || BarcodeFormat.microQrCode => Symbology.qr,
      BarcodeFormat.dataMatrix => Symbology.dataMatrix,
      BarcodeFormat.pdf417 => Symbology.pdf417,
      BarcodeFormat.aztec => Symbology.aztec,
      BarcodeFormat.dataBar || BarcodeFormat.dataBarExpanded || BarcodeFormat.dataBarLimited =>
        Symbology.dataBar,
      _ => Symbology.other,
    };
