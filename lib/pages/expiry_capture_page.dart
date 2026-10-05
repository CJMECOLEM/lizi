import 'package:flutter/material.dart';

import '../barcode/scan_resolver.dart';
import '../expiry/expiry_math.dart';
import '../expiry/expiry_parser.dart';
import '../models/expiry_item.dart';
import '../models/product.dart';
import '../scan/barcode_camera_view.dart';
import '../scan/photo_camera_view.dart';
import '../scan/photo_ocr.dart';
import '../services/app_settings.dart';
import '../services/expiry_db.dart';
import '../services/photo_store.dart';
import '../services/product_db.dart';
import '../services/scan_feedback.dart';
import '../widgets/expiry_style.dart';
import 'expiry_edit_page.dart';

/// Scan the barcode, photograph the date, and the result is saved right away;
/// the page then returns to scanning for the next product. The last result is
/// shown at the bottom and can be tapped to correct it.
class ExpiryCapturePage extends StatefulWidget {
  const ExpiryCapturePage({super.key});

  @override
  State<ExpiryCapturePage> createState() => _ExpiryCapturePageState();
}

class _Result {
  const _Result({this.item, this.draft, this.existed = false, this.error});

  /// Saved check.
  final ExpiryItem? item;

  /// Recognition that found no usable date; not saved yet.
  final ExpiryDraft? draft;
  final bool existed;
  final String? error;
}

class _ExpiryCapturePageState extends State<ExpiryCapturePage> {
  final _ocr = PhotoOcr();
  final _photoKey = GlobalKey<PhotoCameraViewState>();
  final _scanBarcode = AppSettings.instance.expiryScanBarcode;
  late bool _photoStep = !_scanBarcode;
  String _barcode = '';
  Product? _product;
  bool _busy = false;
  bool _editing = false;
  _Result? _result;
  int _saved = 0;
  String _lastCode = '';
  DateTime _lastCodeAt = DateTime(2000);

  @override
  void dispose() {
    _discardDraftPhoto(_result);
    _ocr.close();
    super.dispose();
  }

  void _discardDraftPhoto(_Result? r) {
    final photo = r?.draft?.photo;
    if (photo != null && photo.isNotEmpty) PhotoStore.delete(photo);
  }

  void _setResult(_Result r) {
    if (!mounted) return;
    final old = _result;
    if (old?.draft != null && !identical(old?.draft, r.draft)) _discardDraftPhoto(old);
    setState(() => _result = r);
  }

  Future<void> _onBarcode(List<ResolvedScan> scans) async {
    if (_photoStep || _busy || _editing) return;
    final scan = scans.first;
    final code = scan.key;
    final now = DateTime.now();
    // The code stays in view for a moment after it was handled.
    if (code == _lastCode && now.difference(_lastCodeAt) < const Duration(seconds: 3)) return;
    _lastCode = code;
    _lastCodeAt = now;
    _busy = true;
    try {
      final product = await ProductDb.instance.get(code);
      final gs1 = scan.gs1;
      final printed = gs1?.expiry ?? gs1?.bestBefore;
      if (printed != null) {
        // GS1 labels (some outer cases, imported goods) carry the date in the
        // code itself, so no photo is needed.
        final item = ExpiryItem(
          barcode: code,
          name: product?.name ?? '',
          productionDate: gs1?.productionDate,
          shelfLife: product?.shelfLife,
          expiryDate: printed,
          createdAt: now,
          updatedAt: now,
        );
        final r = await ExpiryDb.instance.add(item);
        ScanFeedback.instance.counted();
        _saved += r.existed ? 0 : 1;
        _setResult(_Result(item: r.item, existed: r.existed));
        return;
      }
      ScanFeedback.instance.counted();
      if (!mounted) return;
      setState(() {
        _barcode = code;
        _product = product;
        _photoStep = true;
      });
    } finally {
      _busy = false;
    }
  }

  void _toBarcodeStep() {
    if (!_scanBarcode) return;
    setState(() {
      _photoStep = false;
      _barcode = '';
      _product = null;
      _lastCodeAt = DateTime.now();
    });
  }

  Future<void> _shoot() async {
    final cam = _photoKey.currentState;
    if (_busy || cam == null || !cam.isReady) return;
    setState(() => _busy = true);
    String? temp;
    try {
      temp = await cam.takePicture();
      if (temp == null) return;
      final lines = await _ocr.read(temp);
      final parse = parseExpiry(lines);
      final photo = await PhotoStore.keep(temp);
      temp = null;
      final product = _product;
      final draft = ExpiryDraft(
        barcode: _barcode,
        name: product != null && product.name.isNotEmpty ? product.name : (parse.name ?? ''),
        productionDate: parse.productionDate,
        shelfLife: parse.shelfLife ?? product?.shelfLife,
        printedExpiry: parse.printedExpiry,
        photo: photo,
        lines: parse.lines,
      );
      final item = draft.toItem();
      if (item == null) {
        ScanFeedback.instance.attention();
        _setResult(_Result(draft: draft));
      } else {
        final r = await ExpiryDb.instance.add(item);
        if (r.existed) await PhotoStore.delete(photo);
        if (parse.shelfLife != null) await ProductDb.instance.remember(_barcode, shelfLife: parse.shelfLife);
        ScanFeedback.instance.counted();
        _saved += r.existed ? 0 : 1;
        _setResult(_Result(item: r.item, existed: r.existed));
      }
      if (mounted) _toBarcodeStep();
    } catch (e) {
      ScanFeedback.instance.attention();
      _setResult(_Result(error: '识别失败：$e'));
      if (temp != null) await PhotoStore.delete(temp);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openResult() async {
    final r = _result;
    if (r == null || r.error != null) return;
    final draft = r.item != null ? ExpiryDraft.of(r.item!) : r.draft!;
    // Closing the camera while editing keeps it from scanning in the
    // background and turns the torch off.
    setState(() => _editing = true);
    final edited = await editExpiry(context, draft);
    if (!mounted) return;
    setState(() => _editing = false);
    if (edited == null) return;
    if (edited.deleted) {
      setState(() => _result = null);
    } else if (edited.saved != null) {
      if (r.draft != null) _saved++;
      // The draft's photo now belongs to the saved item.
      setState(() => _result = _Result(item: edited.saved));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: Text(
                    _photoStep ? (_scanBarcode ? '② 拍生产日期 / 保质期' : '拍生产日期 / 保质期') : '① 扫商品条码',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('本次 $_saved 条', style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
            Expanded(child: _camera()),
            _bottomPanel(theme),
          ],
        ),
      ),
    );
  }

  Widget _camera() {
    if (_editing) return const ColoredBox(color: Colors.black);
    if (!_photoStep) {
      return BarcodeCameraView(key: const ValueKey('barcode'), onDetect: _onBarcode, hint: '将商品条码放入框内');
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PhotoCameraView(key: _photoKey, hint: '让生产日期、保质期清晰地出现在画面中\n点画面可对焦'),
        if (_busy)
          const ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('识别中…', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bottomPanel(ThemeData theme) {
    final product = _product;
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_result != null) _ResultBar(result: _result!, onTap: _openResult),
          const SizedBox(height: 8),
          if (_photoStep) ...[
            Text(
              _barcode.isEmpty
                  ? '未扫条码'
                  : '条码 $_barcode${product != null && product.name.isNotEmpty ? ' · ${product.name}' : ''}',
              style: const TextStyle(color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _scanBarcode
                      ? TextButton.icon(
                          onPressed: _busy ? null : _toBarcodeStep,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('重扫条码'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                        )
                      : const SizedBox.shrink(),
                ),
                _ShutterButton(onPressed: _busy ? null : _shoot),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ] else
            TextButton.icon(
              onPressed: () => setState(() {
                _barcode = '';
                _product = null;
                _photoStep = true;
              }),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('没有条码，直接拍照'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.result, required this.onTap});
  final _Result result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = result.item;
    final Color bg;
    final Color fg;
    final String title;
    final String detail;
    if (result.error != null) {
      bg = const Color(0xFF5C1A1A);
      fg = Colors.white;
      title = '出错了';
      detail = result.error!;
    } else if (item != null) {
      final style = ExpiryStyle.of(item.levelAt(DateTime.now()), scheme);
      bg = item.levelAt(DateTime.now()) == ExpiryLevel.ok ? const Color(0xFF1B5E20) : style.background;
      fg = item.levelAt(DateTime.now()) == ExpiryLevel.ok ? Colors.white : style.foreground;
      title = item.title;
      detail = [
        if (result.existed) '已在清单中',
        '${formatDate(item.expiryDate)} 到期',
        remainingLabel(item.expiryDate, DateTime.now()),
      ].join(' · ');
    } else {
      final d = result.draft!;
      bg = const Color(0xFF4E342E);
      fg = Colors.white;
      title = d.name.isNotEmpty ? d.name : (d.barcode.isNotEmpty ? d.barcode : '这张照片');
      detail = d.lines.isEmpty ? '没识别到文字，点此手动填写' : '没认出完整的日期，点此补填';
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: result.error == null ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg)),
                  ],
                ),
              ),
              if (result.error == null) Icon(Icons.edit, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
