import 'dart:async';

import 'package:flutter/material.dart';

import '../expiry/expiry_math.dart';
import '../expiry/stock_group.dart';
import '../models/expiry_item.dart';
import '../services/exporter.dart';
import '../services/expiry_db.dart';
import '../services/photo_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/expiry_style.dart';
import 'expiry_capture_page.dart';
import 'expiry_product_page.dart';

/// Shelf-life tab: every checked product, soonest expiry first.
class ExpiryListPage extends StatefulWidget {
  const ExpiryListPage({super.key});

  @override
  State<ExpiryListPage> createState() => _ExpiryListPageState();
}

class _ExpiryListPageState extends State<ExpiryListPage> {
  final _search = TextEditingController();
  List<ExpiryItem> _items = [];
  ExpiryLevel? _filter;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ExpiryDb.instance.addListener(_reload);
    _reload();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ExpiryDb.instance.removeListener(_reload);
    _search.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final items = await ExpiryDb.instance.all();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '读取失败，点此重试';
        });
      }
    }
  }

  Future<void> _export(ExportFormat f) async {
    if (_items.isEmpty) {
      showToast(context, '没有可导出的记录');
      return;
    }
    try {
      final now = DateTime.now();
      final batches = _shown(now)
          .expand((g) => g.batches)
          .where((b) => _filter == null || b.levelAt(now) == _filter)
          .toList();
      await exportExpiry(batches, f);
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    }
  }

  Future<void> _clear() async {
    if (_items.isEmpty) return;
    final ok = await confirm(
      context,
      title: '清空保质期记录？',
      message: '所有记录和照片都会删除，无法恢复。',
      ok: '清空',
      destructive: true,
    );
    if (!ok) return;
    await ExpiryDb.instance.clear();
    await PhotoStore.deleteAll();
  }

  List<ExpiryProductGroup> get _groups =>
      groupExpiryItems(_items)
          .where((g) => g.matchesSearch(_search.text))
          .toList();

  List<ExpiryProductGroup> _shown(DateTime now) =>
      _groups.where((g) => g.matchesLevel(_filter, now)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final counts = {for (final l in ExpiryLevel.values) l: 0};
    for (final group in _groups) {
      for (final level in ExpiryLevel.values) {
        if (group.matchesLevel(level, now)) counts[level] = counts[level]! + 1;
      }
    }
    final shown = _shown(now);
    return Scaffold(
      appBar: AppBar(
        title: const Text('保质期'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'xlsx' => _export(ExportFormat.xlsx),
              'csv' => _export(ExportFormat.csv),
              _ => _clear(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'xlsx', child: Text('导出 Excel')),
              PopupMenuItem(value: 'csv', child: Text('导出 CSV')),
              PopupMenuItem(
                value: 'clear',
                child: Text('清空全部', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ExpiryCapturePage()),
        ),
        icon: const Icon(Icons.photo_camera),
        label: const Text('拍照识别'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SearchBar(
              controller: _search,
              hintText: '搜索名称或条码',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (_) => setState(() {}),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _chip(null, '全部 ${_groups.length} 种', theme),
                for (final level in [
                  ExpiryLevel.withinOneMonth,
                  ExpiryLevel.withinTwoMonths,
                  ExpiryLevel.expired,
                  ExpiryLevel.ok,
                ])
                  _chip(
                    level,
                    '${ExpiryStyle.of(level, theme.colorScheme).label} ${counts[level]}',
                    theme,
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '按商品展示，含符合条件批次即显示；点商品查看全部批次',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : _error != null
                ? Center(
                    child: TextButton(onPressed: _reload, child: Text(_error!)),
                  )
                : shown.isEmpty
                ? Center(
                    child: Text(
                      _items.isEmpty ? '点右下角“拍照识别”开始检查保质期' : '没有符合条件的记录',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _ExpiryProductTile(
                      group: shown[i],
                      now: now,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExpiryProductPage(
                            productKey: shown[i].key,
                            initialBatchId: shown[i].batches
                                .firstWhere(
                                  (b) =>
                                      _filter == null ||
                                      b.levelAt(now) == _filter,
                                )
                                .id,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ExpiryLevel? level, String label, ThemeData theme) {
    final style = level == null
        ? null
        : ExpiryStyle.of(level, theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: _filter == level,
        avatar: style == null
            ? null
            : CircleAvatar(backgroundColor: style.accent, radius: 6),
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = level),
      ),
    );
  }
}

class _ExpiryProductTile extends StatelessWidget {
  const _ExpiryProductTile({
    required this.group,
    required this.now,
    required this.onTap,
  });
  final ExpiryProductGroup group;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = group.earliest;
    final level = item.levelAt(now);
    final style = ExpiryStyle.of(level, Theme.of(context).colorScheme);
    final meta = [
      '${group.batches.length} 个批次 · 共 ${group.quantityLabel}',
      if (item.barcode.isNotEmpty) item.barcode,
    ].join(' · ');
    return Container(
      key: ValueKey(group.key),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: style.accent, width: 5)),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          group.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: style.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          [
            meta,
            '最早到期 ${formatDate(item.expiryDate)} · ${remainingLabel(item.expiryDate, now)}',
          ].join('\n'),
          style: TextStyle(color: style.foreground.withValues(alpha: 0.8)),
        ),
        trailing: Icon(Icons.chevron_right, color: style.foreground),
      ),
    );
  }
}
