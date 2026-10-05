import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../expiry/expiry_parser.dart';

/// Chinese/Latin text recognition on a still photo.
class PhotoOcr {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  Future<List<OcrLine>> read(String path) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(path));
    return [
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            // The short side of the box approximates the font size, also for
            // vertical text.
            height: math.min(line.boundingBox.width, line.boundingBox.height),
          ),
    ];
  }

  Future<void> close() => _recognizer.close();
}
