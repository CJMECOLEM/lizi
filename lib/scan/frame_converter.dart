import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
