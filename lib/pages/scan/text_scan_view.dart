import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../scan/camera_gate.dart';
import '../../scan/frame_converter.dart';
import '../../scan/occurrence_tracker.dart';
import '../../scan/text_filter.dart';
import '../../scan/viewfinder.dart';
import '../../services/app_settings.dart';

/// Camera preview with continuous Chinese/number OCR inside a viewfinder band.
/// The camera opens when this widget is mounted and closes when it is removed.
class TextScanView extends StatefulWidget {
  const TextScanView({super.key, required this.onCounted, required this.torchOn});

  /// Lines that just entered the viewfinder.
  final void Function(List<String> lines, DateTime at) onCounted;

  /// Reflects the torch state for the parent's button. The parent resets it
  /// when it removes this view (notifying during dispose is not allowed).
  final ValueNotifier<bool> torchOn;

  @override
  State<TextScanView> createState() => TextScanViewState();
}

class TextScanViewState extends State<TextScanView> {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _disposed = false;
  bool _busy = false;
  String? _error;
  String? _frameError;
  Size _previewArea = Size.zero;

  final _recognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  // OCR rarely reads a line identically twice, so one frame is enough; a line
  // is counted again only after it has been out of view for a while.
  final _tracker = OccurrenceTracker(confirmFrames: 1, goneAfter: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    CameraGate.released.then((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _controller;
    _controller = null;
    CameraGate.releasing(_release(c));
    super.dispose();
  }

  Future<void> _release(CameraController? c) async {
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } on CameraException {
        // The system may already have torn the camera down.
      }
      await c.dispose();
    }
    await _recognizer.close();
  }

  Future<void> _start() async {
    if (_disposed) return;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('没有找到可用的相机');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // 720p keeps OCR fast and the phone cool; text in the band stays legible.
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      // Frames stay upright even if the phone is physically turned, which the
      // viewfinder mapping relies on.
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException {
        // Not supported on this device; the portrait-locked UI usually suffices.
      }
      _camera = camera;
      _controller = controller;
      if (AppSettings.instance.torchWhileScanning) await _setTorch(true);
      if (mounted) setState(() => _error = null);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      await controller?.dispose();
      _controller = null;
      const denied = {'CameraAccessDenied', 'CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted'};
      _setError(denied.contains(e.code)
          ? '没有相机权限\n请在系统设置里允许本应用使用相机'
          : '相机启动失败：${e.description ?? e.code}');
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _setTorch(bool on) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      widget.torchOn.value = on;
    } on CameraException {
      // Device without a torch.
    }
  }

  Future<void> toggleTorch() => _setTorch(!widget.torchOn.value);

  void _onFrame(CameraImage image) {
    if (_busy || _disposed) return;
    final camera = _camera;
    if (camera == null) return;
    _busy = true;
    _processFrame(image, camera).then((_) {
      if (_frameError != null && mounted) setState(() => _frameError = null);
    }, onError: (Object e) {
      if (mounted) setState(() => _frameError = '识别出错：$e');
    }).whenComplete(() => _busy = false);
  }

  Future<void> _processFrame(CameraImage image, CameraDescription camera) async {
    final now = DateTime.now();
    final input = inputImageFromCameraImage(image, camera);
    if (input == null) {
      throw StateError('不支持的画面格式 ${image.format.raw}（${image.planes.length} 个平面）');
    }
    if (_previewArea.isEmpty) return;
    final roi = screenRectToImage(
      textViewfinderRect(_previewArea),
      _previewArea,
      uprightImageSize(Size(image.width.toDouble(), image.height.toDouble())),
    );
    final result = await _recognizer.processImage(input);
    final found = <String>{};
    for (final block in result.blocks) {
      for (final line in block.lines) {
        if (!roi.contains(line.boundingBox.center)) continue;
        final t = normalizeOcrLine(line.text);
        if (isUsefulOcrLine(t)) found.add(t);
      }
    }
    if (_disposed) return;
    final counted = _tracker.update(found, now);
    if (counted.isNotEmpty) widget.onCounted(counted, now);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return LayoutBuilder(builder: (context, constraints) {
      _previewArea = constraints.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            _CoverPreview(controller: c)
          else
            Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: Colors.white54)
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
            ),
          CustomPaint(painter: _BandPainter(textViewfinderRect(_previewArea))),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Text(
              _frameError ?? '将文字放入框内',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _frameError == null ? Colors.white : Colors.orangeAccent,
                fontSize: 14,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.expand();
    // previewSize is reported in landscape; swap for the portrait UI.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.height, height: size.width, child: CameraPreview(controller)),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.rect != rect;
}
