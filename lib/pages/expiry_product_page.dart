import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../expiry/expiry_math.dart';
import '../expiry/stock_group.dart';
import '../models/expiry_item.dart';
import '../services/expiry_db.dart';
import '../services/photo_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/expiry_style.dart';
import 'expiry_edit_page.dart';

class ExpiryProductPage extends StatefulWidget {
  const ExpiryProductPage({
    super.key,
    required this.productKey,
    this.initialBatchId,
    this.database,
  });

  final String productKey;
  final int? initialBatchId;
  final ExpiryDb? database;

  @override
  State<ExpiryProductPage> createState() => _ExpiryProductPageState();
}

class _ExpiryProductPageState extends State<ExpiryProductPage> {
  ExpiryDb get _db => widget.database ?? ExpiryDb.instance;
  late String _key = widget.productKey;
  late int? _selected = widget.initialBatchId;
  ExpiryProductGroup? _group;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _db.addListener(_reload);
    _reload();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _db.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final items = await _db.all();
      if (!mounted || generation != _generation) return;
      final groups = groupExpiryItems(items).where((g) => g.key == _key);
      setState(() {
        _group = groups.isEmpty ? null : groups.first;
        if (!(_group?.batches.any((b) => b.id == _selected) ?? false)) {
          _selected = _group?.earliest.id;
        }
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '读取失败，请重试';
        });
      }
    }
  }

  Future<void> _changeQuantity(ExpiryItem item, int delta) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _db.changeQuantity(item.id!, delta);
      await _reload();
    } catch (_) {
      if (mounted) showToast(context, '数量保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(ExpiryItem item) async {
    final result = await editExpiry(context, ExpiryDraft.of(item));
    if (!mounted) return;
    if (result?.saved case final saved?) {
      _key = expiryProductKey(saved);
      _selected = saved.id;
    }
    await _reload();
  }

  Future<void> _delete(ExpiryItem item) async {
    if (!await confirm(
      context,
      title: '删除当前批次？',
      message: '${batchLabel(item)}，库存 ${item.quantityLabel}。其他批次不受影响。',
      ok: '删除',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _db.delete(item.id!);
      await PhotoStore.delete(item.photo);
      await _reload();
    } catch (_) {
      if (mounted) showToast(context, '删除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final now = DateTime.now();
    final item = group?.batches.where((b) => b.id == _selected).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(group?.title ?? '商品批次')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: TextButton(onPressed: _reload, child: Text(_error!)),
            )
          : item == null || group == null
          ? const Center(child: Text('此商品暂无批次'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${group.batches.length} 个批次 · 共 ${group.quantityLabel}',
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final batch in group.batches)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('batch-${batch.id}'),
                            selected: batch.id == _selected,
                            avatar: CircleAvatar(
                              radius: 6,
                              backgroundColor: ExpiryStyle.of(
                                batch.levelAt(now),
                                Theme.of(context).colorScheme,
                              ).accent,
                            ),
                            label: Text(
                              '${batchLabel(batch)} · ${batch.quantityLabel}',
                            ),
                            onSelected: _busy
                                ? null
                                : (_) => setState(() => _selected = batch.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      BatchParameterPanel(item: item, now: now),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.outlined(
                            tooltip: '当前批次减一',
                            onPressed: _busy || item.qty == 0
                                ? null
                                : () => _changeQuantity(item, -1),
                            icon: const Icon(Icons.remove),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              item.quantityLabel,
                              key: const ValueKey('batch-quantity'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton.outlined(
                            tooltip: '当前批次加一',
                            onPressed: _busy
                                ? null
                                : () => _changeQuantity(item, 1),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: batchCopyText(item, DateTime.now()),
                            ),
                          );
                          if (context.mounted) showToast(context, '已复制当前批次参数');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('复制当前批次参数'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _edit(item),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('修改参数 / 数量 / 单位'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _delete(item),
                        child: const Text(
                          '删除当前批次',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class BatchParameterPanel extends StatelessWidget {
  const BatchParameterPanel({super.key, required this.item, required this.now});
  final ExpiryItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final style = ExpiryStyle.of(
      item.levelAt(now),
      Theme.of(context).colorScheme,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: style.background,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  '到期日期  ${formatDate(item.expiryDate)}',
                  style: TextStyle(
                    color: style.foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  expiryDaysLabel(item, now),
                  style: TextStyle(color: style.foreground),
                ),
              ],
            ),
          ),
          _row('条形码', item.barcode.isEmpty ? '未填写' : item.barcode),
          _row('商品名', item.title),
          if (item.photo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 88, child: Text('商品图片')),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('包装照片')),
                            body: InteractiveViewer(
                              maxScale: 6,
                              child: Center(
                                child: Image.file(
                                  File(item.photo),
                                  errorBuilder: (_, _, _) =>
                                      const Text('照片不可用'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: Image.file(
                        File(item.photo),
                        height: 140,
                        fit: BoxFit.contain,
                        cacheWidth: 600,
                        errorBuilder: (_, _, _) => const Text('照片不可用'),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            _row('商品图片', '未保存'),
          _row(
            '生产日期',
            item.productionDate == null
                ? '未填写（仅有到期日）'
                : formatDate(item.productionDate!),
          ),
          _row('保质期', item.shelfLife?.label ?? '未填写'),
          _row('数量', '${item.qty}'),
          _row('单位', item.unit),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 88, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
