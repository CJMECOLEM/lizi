import 'package:flutter/material.dart';

import '../barcode/scan_resolver.dart';
import '../models/stock_sheet.dart';
import '../scan/barcode_camera_view.dart';
import '../scan/occurrence_tracker.dart';
import '../services/app_settings.dart';
import '../services/exporter.dart';
import '../services/inventory_db.dart';
import '../services/product_db.dart';
import '../services/scan_feedback.dart';
import '../widgets/dialogs.dart';
import '../widgets/sheet_item_tile.dart';

/// Loads the current counting sheet and keeps its lines up to date.
mixin _SheetItems<T extends StatefulWidget> on State<T> {
  int? sheetId;
  List<SheetItem> items = [];
  bool loading = true;
  bool canUndo = false;

  int get total => items.fold(0, (s, it) => s + it.qty);

  void initSheet() {
    InventoryDb.instance.addListener(reload);
    ProductDb.instance.addListener(reload);
    InventoryDb.instance.currentSheet(AppSettings.instance.currentSheetId).then((s) {
      AppSettings.instance.currentSheetId = s.id;
      sheetId = s.id;
      reload();
    });
  }

  void disposeSheet() {
    InventoryDb.instance.removeListener(reload);
    ProductDb.instance.removeListener(reload);
  }

  Future<void> reload() async {
    final id = sheetId;
    if (id == null) return;
    final list = await InventoryDb.instance.items(id);
    final undo = await InventoryDb.instance.canUndo(id);
    if (!mounted) return;
    setState(() {
      items = list;
      canUndo = undo;
      loading = false;
    });
  }

  Future<void> undo() async {
    final id = sheetId;
    if (id == null) return;
    final r = await InventoryDb.instance.undoLast(id);
    if (r != null && mounted) {
      showToast(context, '已撤销 ${r.barcode} ${r.delta > 0 ? '+' : ''}${r.delta}');
    }
  }

  void removeLine(SheetItem it) {
    setState(() => items.remove(it));
    InventoryDb.instance.removeItem(it.sheetId, it.barcode);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已删除 ${itemTitle(it)}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '撤销', onPressed: () => InventoryDb.instance.undoLast(it.sheetId)),
      ));
  }
}

/// Counting tab: the list of counted codes; scanning opens full screen.
class CountPage extends StatefulWidget {
  const CountPage({super.key});

  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> with _SheetItems {
  @override
  void initState() {
    super.initState();
    initSheet();
  }

  @override
  void dispose() {
    disposeSheet();
    super.dispose();
  }

  Future<void> _export(ExportFormat f) async {
    if (items.isEmpty) {
      showToast(context, '还没有计数');
      return;
    }
    try {
      await exportSheet(items, f);
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    }
  }

  Future<void> _clear() async {
    final id = sheetId;
    if (id == null || items.isEmpty) return;
    final ok = await confirm(context, title: '清空计数？', message: '所有条码和数量都会删除，无法撤销。', ok: '清空', destructive: true);
    if (ok) await InventoryDb.instance.clearSheet(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('计数'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: '撤销上一步', onPressed: canUndo ? undo : null),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'xlsx' => _export(ExportFormat.xlsx),
              'csv' => _export(ExportFormat.csv),
              _ => _clear(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'xlsx', child: Text('导出 Excel')),
              PopupMenuItem(value: 'csv', child: Text('导出 CSV')),
              PopupMenuItem(value: 'clear', child: Text('清空计数', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CountScanPage())),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('扫码计数'),
      ),
      body: loading
          ? const SizedBox.shrink()
          : Column(
              children: [
                _Summary(kinds: items.length, total: total),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text('点右下角开始扫码，每扫到一次加 1',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                          itemBuilder: (context, i) =>
                              SheetItemTile(item: items[i], onRemove: () => removeLine(items[i])),
                        ),
                ),
              ],
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.kinds, required this.total});
  final int kinds;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text('$kinds 种 · 共 $total 件', style: theme.textTheme.titleSmall),
    );
  }
}

/// Camera on top, live counts below. A code is counted once per appearance:
/// holding it in view does not count it again; it must leave the window
/// briefly first.
class CountScanPage extends StatefulWidget {
  const CountScanPage({super.key});

  @override
  State<CountScanPage> createState() => _CountScanPageState();
}

class _CountScanPageState extends State<CountScanPage> with _SheetItems {
  final _cameraKey = GlobalKey<BarcodeCameraViewState>();
  final _tracker = OccurrenceTracker(confirmFrames: 1, goneAfter: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    initSheet();
  }

  @override
  void dispose() {
    disposeSheet();
    super.dispose();
  }

  /// Outer cases are counted under their own code here; converting them to
  /// units needs case sizes, which this version does not keep.
  String _countKey(ResolvedScan s) => s.kind == ScanKind.outerCase ? (s.caseCode ?? s.key) : s.key;

  void _onDetect(List<ResolvedScan> scans) {
    final id = sheetId;
    if (id == null) return;
    final byKey = {for (final s in scans) _countKey(s): s};
    final counted = _tracker.update(byKey.keys, DateTime.now());
    if (counted.isEmpty) return;
    for (final key in counted) {
      InventoryDb.instance.add(id, key, 1, format: byKey[key]!.symbology.label);
    }
    ScanFeedback.instance.counted();
    _cameraKey.currentState?.flash();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      appBar: AppBar(
        title: Text('扫码计数 · ${items.length} 种 $total 件'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: '撤销上一步', onPressed: canUndo ? undo : null),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: height * 0.42,
            child: BarcodeCameraView(key: _cameraKey, onDetect: _onDetect, hint: '条码移出框再移入，才会再加 1'),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('扫到的条码会显示在这里'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                    itemBuilder: (context, i) =>
                        SheetItemTile(item: items[i], dense: true, onRemove: () => removeLine(items[i])),
                  ),
          ),
        ],
      ),
    );
  }
}
