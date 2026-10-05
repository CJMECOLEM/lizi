import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import 'camera_gate.dart';

/// Camera preview for taking still photos of package text. Tap to focus.
/// The camera opens when mounted and closes when removed or when the app goes
/// to the background.
class PhotoCameraView extends StatefulWidget {
  const PhotoCameraView({super.key, this.hint});

  final String? hint;

  @override
  State<PhotoCameraView> createState() => PhotoCameraViewState();
}

class PhotoCameraViewState extends State<PhotoCameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _disposed = false;
  bool _starting = false;
  bool _torch = false;
  bool _hasTorch = true;
  String? _error;
  Offset? _focusMark;

  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CameraGate.released.then((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final c = _controller;
    _controller = null;
    if (c != null) CameraGate.releasing(c.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _controller;
      if (c == null) return;
      _controller = null;
      setState(() {});
      CameraGate.releasing(c.dispose());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      CameraGate.released.then((_) => _start());
    }
  }

  Future<void> _start() async {
    // The permission prompt sends the app through inactive/resumed while the
    // first start is still running.
    if (_disposed || _controller != null || _starting) return;
    _starting = true;
    try {
      await _open();
    } finally {
      _starting = false;
    }
  }

  Future<void> _open() async {
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
      // Production dates are small print; 1080p keeps them legible for OCR.
      controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();
      if (_disposed || _controller != null) {
        await controller.dispose();
        return;
      }
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException {
        // Not supported; the portrait-locked UI usually suffices.
      }
      _controller = controller;
      if (AppSettings.instance.torchWhileScanning) await _setTorch(true);
      if (mounted) setState(() => _error = null);
    } on CameraException catch (e) {
      await controller?.dispose();
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
      if (mounted) setState(() => _torch = on);
    } on CameraException {
      if (mounted) setState(() => _hasTorch = false);
    }
  }

  /// Takes a photo and returns its temporary file path.
  Future<String?> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return null;
    final file = await c.takePicture();
    // Some devices drop torch mode after a capture.
    if (_torch && !_disposed && identical(c, _controller)) {
      try {
        await c.setFlashMode(FlashMode.torch);
      } on CameraException {
        // Ignore; the user can switch it back on.
      }
    }
    return file.path;
  }

  Future<void> _focus(TapUpDetails d, Size area) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _focusMark = d.localPosition);
    final point = Offset(
      (d.localPosition.dx / area.width).clamp(0.0, 1.0),
      (d.localPosition.dy / area.height).clamp(0.0, 1.0),
    );
    try {
      await c.setFocusPoint(point);
      await c.setExposurePoint(point);
    } on CameraException {
      // Fixed-focus camera.
    }
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _focusMark = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return LayoutBuilder(builder: (context, constraints) {
      final area = constraints.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            GestureDetector(onTapUp: (d) => _focus(d, area), child: _CoverPreview(controller: c))
          else
            ColoredBox(
              color: Colors.black,
              child: Center(
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
            ),
          if (_focusMark != null)
            Positioned(
              left: _focusMark!.dx - 30,
              top: _focusMark!.dy - 30,
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(border: Border.all(color: Colors.yellowAccent, width: 2)),
                ),
              ),
            ),
          if (widget.hint != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: IgnorePointer(
                child: Text(
                  widget.hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 4)]),
                ),
              ),
            ),
          if (c != null && _hasTorch)
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: _torch ? '关闭闪光灯' : '打开闪光灯',
                icon: Icon(_torch ? Icons.flashlight_on : Icons.flashlight_off),
                onPressed: () => _setTorch(!_torch),
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
