import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/scan_record.dart';
import '../services/exporter.dart';
import '../services/history_db.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _search = TextEditingController();
  final _time = DateFormat('MM-dd HH:mm');
  List<ScanRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    HistoryDb.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    HistoryDb.instance.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final records = await HistoryDb.instance.query(search: _search.text);
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
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

  void _copy(ScanRecord r) {
    Clipboard.setData(ClipboardData(text: r.content));
    _toast('已复制');
  }

  Future<void> _export(ExportFormat format) async {
    if (_records.isEmpty) {
      _toast('没有可导出的记录');
      return;
    }
    try {
      await exportAndShare(_records, format);
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史记录？'),
        content: const Text('所有记录将被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await HistoryDb.instance.clear();
  }

  void _showActions(ScanRecord r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: SelectableText(
                r.content,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(context);
                _copy(r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(context);
                shareText(r.content);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                HistoryDb.instance.delete(r.id!);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [
          PopupMenuButton<ExportFormat>(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出',
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: ExportFormat.xlsx, child: Text('导出 Excel')),
              PopupMenuItem(value: ExportFormat.csv, child: Text('导出 CSV')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空',
            onPressed: _records.isEmpty && _search.text.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: '搜索内容',
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
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : _records.isEmpty
                    ? Center(
                        child: Text(
                          _search.text.isEmpty ? '还没有记录' : '没有匹配的记录',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _records.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                        itemBuilder: (context, i) {
                          final r = _records[i];
                          final meta = [
                            r.type.label,
                            if (r.format.isNotEmpty) r.format,
                            _time.format(r.lastSeen),
                          ].join(' · ');
                          return Dismissible(
                            key: ValueKey(r.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              setState(() => _records.removeAt(i));
                              HistoryDb.instance.delete(r.id!);
                            },
                            child: ListTile(
                              title: Text(
                                r.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(meta),
                              trailing: Text(
                                '×${r.count}',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(color: theme.colorScheme.primary),
                              ),
                              onTap: () => _copy(r),
                              onLongPress: () => _showActions(r),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
