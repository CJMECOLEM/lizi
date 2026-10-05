import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import 'history_page.dart';
import 'text_scan_page.dart';

const appVersion = '2.0.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('扫描时打开闪光灯'),
              subtitle: const Text('相机打开时自动亮起，离开扫描界面或切到后台就关闭'),
              value: settings.torchWhileScanning,
              onChanged: (v) => settings.torchWhileScanning = v,
            ),
            SwitchListTile(
              title: const Text('检查保质期前先扫条码'),
              subtitle: const Text('用条码记住商品名称和保质期，下次同一商品只需拍生产日期'),
              value: settings.expiryScanBarcode,
              onChanged: (v) => settings.expiryScanBarcode = v,
            ),
            SwitchListTile(
              title: const Text('提示音'),
              value: settings.beep,
              onChanged: (v) => settings.beep = v,
            ),
            SwitchListTile(
              title: const Text('震动'),
              value: settings.vibrate,
              onChanged: (v) => settings.vibrate = v,
            ),
            const ListTile(
              title: Text('到期提醒规则'),
              subtitle: Text('按自然月计算：1 个月内到期标红，2 个月内标黄，已过期标灰。'
                  '到期日是最后有效日，例如 2025-03-01 生产、保质期 12 个月，到期日为 2026-02-28。'),
            ),
            const Divider(),
            const ListTile(dense: true, title: Text('附加功能')),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('连续识字'),
              subtitle: const Text('对准文字自动识别并保存'),
              onTap: () => open(const TextScanPage()),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('识字记录'),
              onTap: () => open(const HistoryPage()),
            ),
            const Divider(),
            const ListTile(title: Text('版本'), trailing: Text(appVersion)),
          ],
        ),
      ),
    );
  }
}
