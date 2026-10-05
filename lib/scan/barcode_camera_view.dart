import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../barcode/scan_resolver.dart';
import '../services/app_settings.dart';
import 'barcode_formats.dart';
import 'camera_gate.dart';
import 'viewfinder.dart';

/// Live barcode scanning inside a viewfinder window. The camera opens when
/// this widget is mounted and closes when it is removed or the app goes to
/// the background; the torch follows the "torch while scanning" setting.
class BarcodeCameraView extends StatefulWidget {
  const BarcodeCameraView({super.key, required this.onDetect, this.hint = '将条码放入框内'});

  /// Valid codes seen in one camera frame (misreads that fail their check
  /// digit are already dropped).
  final void Function(List<ResolvedScan> scans) onDetect;
  final String hint;

  @override
  State<BarcodeCameraView> createState() => BarcodeCameraViewState();
}

class BarcodeCameraViewState extends State<BarcodeCameraView> with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    formats: scanFormats,
    torchEnabled: AppSettings.instance.torchWhileScanning,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 200,
  );
  bool _disposed = false;
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CameraGate.released.then((_) => _start());
  }

  Future<void> _start() async {
    if (_disposed) return;
    try {
      await _controller.start();
    } on MobileScannerException {
      // Shown by the error builder.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission prompt itself makes the app inactive; leave the first
    // start alone until access has been granted.
    if (_disposed || !_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _controller.stop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    CameraGate.releasing(() async {
      await _controller.stop();
      await _controller.dispose();
    }());
    super.dispose();
  }

  /// Briefly turns the viewfinder green to confirm a counted scan.
  void flash() {
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final scans = <ResolvedScan>[];
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final r = resolveScan(raw, symbologyOf(b.format));
      if (r != null) scans.add(r);
    }
    if (scans.isNotEmpty) widget.onDetect(scans);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final window = barcodeViewfinderRect(constraints.biggest);
      return Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: window,
            onDetect: _onDetect,
            tapToFocus: true,
            errorBuilder: (context, error) => _ErrorView(error: error),
            placeholderBuilder: (_) => const ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator(color: Colors.white54)),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: ViewfinderPainter(window, highlight: _flash))),
          Positioned(
            left: 16,
            right: 16,
            top: window.bottom + 12,
            child: IgnorePointer(
              child: Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 4)]),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
                final on = state.torchState == TorchState.on;
                return IconButton.filledTonal(
                  tooltip: on ? '关闭闪光灯' : '打开闪光灯',
                  icon: Icon(on ? Icons.flashlight_on : Icons.flashlight_off),
                  onPressed: () => _controller.toggleTorch(),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final msg = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? '没有相机权限\n请在系统设置里允许本应用使用相机'
        : '相机启动失败：${error.errorDetails?.message ?? error.errorCode.message}';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ),
      ),
    );
  }
}

/// Dims everything outside [rect] and outlines it; green while [highlight].
class ViewfinderPainter extends CustomPainter {
  ViewfinderPainter(this.rect, {this.highlight = false});

  final Rect rect;
  final bool highlight;

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
        ..color = highlight ? Colors.greenAccent : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlight ? 4 : 2,
    );
  }

  @override
  bool shouldRepaint(ViewfinderPainter old) => old.rect != rect || old.highlight != highlight;
}
