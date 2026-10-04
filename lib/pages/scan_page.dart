import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/scan_record.dart';
import '../scan/auto_torch.dart';
import '../scan/frame_converter.dart';
import '../scan/occurrence_tracker.dart';
import '../scan/text_filter.dart';
import '../scan/viewfinder.dart';
import '../services/app_settings.dart';
import '../services/exporter.dart';
import '../services/history_db.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.active});

  /// The camera only runs while the scan tab is visible.
  final bool active;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _starting = false;
  bool _appResumed = true;
  String? _error;

  RecordType _mode = RecordType.barcode;
  bool _torchOn = false;
  bool _busy = false;
  Size _previewArea = Size.zero;

  final _barcodeScanner = BarcodeScanner(formats: oneDimensionalFormats);
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  final _barcodeTracker = OccurrenceTracker();
  // OCR runs slower than barcode scanning, so allow longer gaps between hits.
  final _textTracker = OccurrenceTracker(
    goneAfter: const Duration(milliseconds: 1500),
  );
  final _autoTorch = AutoTorchController();

  /// Results of the current scanning session, newest first.
  final List<ScanRecord> _session = [];

  bool get _shouldRun => widget.active && _appResumed && mounted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(ScanPage old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _start() : _stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      if (widget.active) _start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _appResumed = false;
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(rebuild: false);
    _barcodeScanner.close();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _start() async {
    if (_controller != null || _starting) return;
    _starting = true;
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
      controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!_shouldRun) {
        await controller.dispose();
        return;
      }
      _camera = camera;
      _controller = controller;
      _torchOn = false;
      _autoTorch.reset();
      _barcodeTracker.reset();
      _textTracker.reset();
      setState(() => _error = null);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      await controller?.dispose();
      _controller = null;
      const denied = {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      };
      _setError(denied.contains(e.code)
          ? '没有相机权限\n请在「设置 › 扫码识字」中允许访问相机'
          : '相机启动失败：${e.description ?? e.code}');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop({bool rebuild = true}) async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    _torchOn = false;
    if (rebuild && mounted) setState(() {});
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } on CameraException {
      // The camera may already be torn down by the system.
    }
    await c.dispose();
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onFrame(CameraImage image) {
    if (_busy) return;
    final camera = _camera;
    if (camera == null || _controller == null) return;
    _busy = true;
    _processFrame(image, camera).catchError((Object _) {}).whenComplete(() {
      _busy = false;
    });
  }

  Future<void> _processFrame(CameraImage image, CameraDescription camera) async {
    final now = DateTime.now();
    final plane = image.planes.first;
    final luma = averageLuma(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      bgra: Platform.isIOS,
    );
    if (_autoTorch.shouldTurnOn(
      luma: luma,
      now: now,
      torchOn: _torchOn,
      enabled: AppSettings.instance.autoTorch,
    )) {
      unawaited(_setTorch(true));
    }

    final input = inputImageFromCameraImage(image, camera);
    if (input == null) return;

    final mode = _mode;
    final found = <String, String>{}; // content -> barcode format name
    if (mode == RecordType.barcode) {
      final codes = await _barcodeScanner.processImage(input);
      for (final b in codes) {
        final v = b.rawValue?.trim() ?? '';
        if (v.isNotEmpty) found[v] = barcodeFormatName(b.format);
      }
    } else {
      if (_previewArea.isEmpty) return;
      final roi = screenRectToImage(
        textViewfinderRect(_previewArea),
        _previewArea,
        uprightImageSize(Size(image.width.toDouble(), image.height.toDouble())),
      );
      final result = await _textRecognizer.processImage(input);
      for (final block in result.blocks) {
        for (final line in block.lines) {
          if (!roi.contains(line.boundingBox.center)) continue;
          final t = normalizeOcrLine(line.text);
          if (isUsefulOcrLine(t)) found[t] = '';
        }
      }
    }
    // Ignore results that finished after the user switched modes.
    if (!mounted || mode != _mode) return;

    final tracker = mode == RecordType.barcode ? _barcodeTracker : _textTracker;
    final counted = tracker.update(found.keys, now);
    if (counted.isEmpty) return;
    for (final content in counted) {
      _record(mode, content, found[content]!, now);
    }
    if (AppSettings.instance.vibrate) HapticFeedback.mediumImpact();
  }

  void _record(RecordType type, String content, String format, DateTime now) {
    setState(() {
      final key = '${type.name}|$content';
      final i = _session.indexWhere((r) => r.key == key);
      if (i >= 0) {
        final r = _session.removeAt(i)
          ..count += 1
          ..lastSeen = now;
        _session.insert(0, r);
      } else {
        _session.insert(
          0,
          ScanRecord(
            type: type,
            content: content,
            format: format,
            firstSeen: now,
            lastSeen: now,
          ),
        );
      }
    });
    HistoryDb.instance.addOccurrence(
      type: type,
      content: content,
      format: format,
      at: now,
    );
  }

  Future<void> _setTorch(bool on) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = on);
    } on CameraException {
      // Device without a torch; leave the state unchanged.
    }
  }

  void _toggleTorch() {
    if (_torchOn) {
      _autoTorch.userTurnedOff();
      _setTorch(false);
    } else {
      _setTorch(true);
    }
  }

  void _switchMode(RecordType mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _barcodeTracker.reset();
    _textTracker.reset();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _copy(String text, {String msg = '已复制'}) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(child: _buildCameraArea()),
          _buildResultsPanel(context),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
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
          if (_mode == RecordType.text)
            CustomPaint(
              painter: _ViewfinderPainter(textViewfinderRect(_previewArea)),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Text(
              _mode == RecordType.barcode ? '对准条码即可连续识别' : '将文字放入框内',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _ModeSwitch(mode: _mode, onChanged: _switchMode),
                  const Spacer(),
                  _RoundButton(
                    icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                    highlighted: _torchOn,
                    onPressed: _controller == null ? null : _toggleTorch,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildResultsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.32;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Text('本次识别 ${_session.length} 项', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: _session.isEmpty
                      ? null
                      : () => _copy(
                            _session.map((r) => r.content).join('\n'),
                            msg: '已复制全部 ${_session.length} 项',
                          ),
                  child: const Text('复制全部'),
                ),
                TextButton(
                  onPressed: _session.isEmpty
                      ? null
                      : () {
                          setState(_session.clear);
                          _barcodeTracker.reset();
                          _textTracker.reset();
                        },
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _session.isEmpty
                ? Center(
                    child: Text(
                      '识别结果会显示在这里',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _session.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                    itemBuilder: (context, i) {
                      final r = _session[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          r.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                        subtitle: Text(
                          r.format.isEmpty ? r.type.label : '${r.type.label} · ${r.format}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CountBadge(count: r.count),
                            IconButton(
                              icon: const Icon(Icons.ios_share, size: 20),
                              tooltip: '分享',
                              onPressed: () => shareText(r.content),
                            ),
                          ],
                        ),
                        onTap: () => _copy(r.content),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
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
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter(this.rect);

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
  bool shouldRepaint(_ViewfinderPainter old) => old.rect != rect;
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final RecordType mode;
  final ValueChanged<RecordType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in RecordType.values)
            GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: m == mode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  m.label,
                  style: TextStyle(
                    color: m == mode ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.highlighted,
    required this.onPressed,
  });

  final IconData icon;
  final bool highlighted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      iconSize: 26,
      style: IconButton.styleFrom(
        backgroundColor: highlighted ? Colors.amber : Colors.black54,
        foregroundColor: highlighted ? Colors.black : Colors.white,
        fixedSize: const Size(48, 48),
      ),
      icon: Icon(icon),
      tooltip: '闪光灯',
      onPressed: onPressed,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: count > 1 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '×$count',
        style: TextStyle(
          color: count > 1 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
