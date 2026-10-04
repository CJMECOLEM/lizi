import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Wraps a camera stream frame for ML Kit. The app is portrait-locked, so the
/// rotation is simply the sensor orientation.
InputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraDescription camera,
) {
  final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
  final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
  if (rotation == null || format == null) return null;
  if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
  if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
  if (image.planes.length != 1) return null;

  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

/// 1D symbologies only; 2D codes are intentionally ignored.
const oneDimensionalFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upca,
  BarcodeFormat.upce,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.codabar,
  BarcodeFormat.itf,
];

String barcodeFormatName(BarcodeFormat f) => switch (f) {
      BarcodeFormat.ean13 => 'EAN-13',
      BarcodeFormat.ean8 => 'EAN-8',
      BarcodeFormat.upca => 'UPC-A',
      BarcodeFormat.upce => 'UPC-E',
      BarcodeFormat.code128 => 'Code 128',
      BarcodeFormat.code39 => 'Code 39',
      BarcodeFormat.code93 => 'Code 93',
      BarcodeFormat.codabar => 'Codabar',
      BarcodeFormat.itf => 'ITF',
      _ => f.name,
    };
