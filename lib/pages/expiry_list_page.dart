import 'package:flutter/material.dart';

import '../expiry/expiry_math.dart';
import '../models/expiry_item.dart';
import '../services/exporter.dart';
import '../services/expiry_db.dart';
import '../services/photo_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/expiry_style.dart';
import 'expiry_capture_page.dart';
import 'expiry_edit_page.dart';

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

  @override
  void initState() {
    super.initState();
    ExpiryDb.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    ExpiryDb.instance.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await ExpiryDb.instance.all(search: _search.text);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _export(ExportFormat f) async {
    if (_items.isEmpty) {
      showToast(context, '没有可导出的记录');
      return;
    }
    try {
      await exportExpiry(_shown(DateTime.now()), f);
    } catch (e) {
      if (mounted) showToast(context, '导出失败：$e');
    }
  }

  Future<void> _clear() async {
    if (_items.isEmpty) return;
    final ok = await confirm(context, title: '清空保质期记录？', message: '所有记录和照片都会删除，无法恢复。', ok: '清空', destructive: true);
    if (!ok) return;
    await ExpiryDb.instance.clear();
    await PhotoStore.deleteAll();
  }

  void _delete(ExpiryItem it) {
    setState(() => _items.remove(it));
    ExpiryDb.instance.delete(it.id!);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    var undone = false;
    messenger
        .showSnackBar(SnackBar(
          content: Text('已删除 ${it.title}'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              undone = true;
              ExpiryDb.instance.restore(it);
            },
          ),
        ))
        .closed
        .then((_) {
      if (!undone) PhotoStore.delete(it.photo);
    });
  }

  List<ExpiryItem> _shown(DateTime now) =>
      _filter == null ? _items : _items.where((it) => it.levelAt(now) == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final counts = {for (final l in ExpiryLevel.values) l: 0};
    for (final it in _items) {
      counts[it.levelAt(now)] = counts[it.levelAt(now)]! + 1;
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
              PopupMenuItem(value: 'clear', child: Text('清空全部', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExpiryCapturePage())),
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
              onChanged: (_) => _reload(),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      _reload();
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
                _chip(null, '全部 ${_items.length}', theme),
                for (final level in [
                  ExpiryLevel.withinOneMonth,
                  ExpiryLevel.withinTwoMonths,
                  ExpiryLevel.expired,
                  ExpiryLevel.ok,
                ])
                  _chip(level, '${ExpiryStyle.of(level, theme.colorScheme).label} ${counts[level]}', theme),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : shown.isEmpty
                    ? Center(
                        child: Text(
                          _items.isEmpty ? '点右下角“拍照识别”开始检查保质期' : '没有符合条件的记录',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _ExpiryTile(
                          item: shown[i],
                          now: now,
                          onTap: () => editExpiry(context, ExpiryDraft.of(shown[i])),
                          onDelete: () => _delete(shown[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ExpiryLevel? level, String label, ThemeData theme) {
    final style = level == null ? null : ExpiryStyle.of(level, theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: _filter == level,
        avatar: style == null ? null : CircleAvatar(backgroundColor: style.accent, radius: 6),
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = level),
      ),
    );
  }
}

class _ExpiryTile extends StatelessWidget {
  const _ExpiryTile({required this.item, required this.now, required this.onTap, required this.onDelete});
  final ExpiryItem item;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final level = item.levelAt(now);
    final style = ExpiryStyle.of(level, Theme.of(context).colorScheme);
    final meta = [
      if (item.productionDate != null) '生产 ${formatDate(item.productionDate!)}',
      if (item.shelfLife != null) '保质 ${item.shelfLife!.label}',
      if (item.barcode.isNotEmpty) item.barcode,
    ].join(' · ');
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: style.accent, width: 5)),
        ),
        child: ListTile(
          onTap: onTap,
          title: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.foreground,
              fontWeight: FontWeight.w600,
              decoration: level == ExpiryLevel.expired ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            [ '到期 ${formatDate(item.expiryDate)}', if (meta.isNotEmpty) meta ].join('\n'),
            style: TextStyle(color: style.foreground.withValues(alpha: 0.8)),
          ),
          trailing: Text(
            remainingLabel(item.expiryDate, now).replaceFirst('剩 ', '剩\n'),
            textAlign: TextAlign.right,
            style: TextStyle(color: style.foreground, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
