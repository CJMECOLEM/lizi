import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/history_db.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _confirmClear(BuildContext context) async {
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
    if (ok != true) return;
    await HistoryDb.instance.clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('暗处自动开闪光灯'),
              subtitle: const Text('光线不足时自动打开；手动关闭后，本次扫描不再自动打开'),
              value: settings.autoTorch,
              onChanged: (v) => settings.autoTorch = v,
            ),
            SwitchListTile(
              title: const Text('识别成功时震动'),
              value: settings.vibrate,
              onChanged: (v) => settings.vibrate = v,
            ),
            const Divider(),
            ListTile(
              title: const Text('清空历史记录', style: TextStyle(color: Colors.red)),
              onTap: () => _confirmClear(context),
            ),
            const ListTile(
              title: Text('版本'),
              trailing: Text('1.0.0'),
            ),
          ],
        ),
      ),
    );
  }
}
