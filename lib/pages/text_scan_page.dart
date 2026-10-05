import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scan_record.dart';
import '../services/history_db.dart';
import '../services/scan_feedback.dart';
import 'history_page.dart';
import 'scan/text_scan_view.dart';

/// Continuous text recognition (optional extra): every line that enters the
/// band is saved to the text history.
class TextScanPage extends StatefulWidget {
  const TextScanPage({super.key});

  @override
  State<TextScanPage> createState() => _TextScanPageState();
}

class _TextScanPageState extends State<TextScanPage> {
  final _viewKey = GlobalKey<TextScanViewState>();
  final _torchOn = ValueNotifier(false);
  final _recent = <String>[];

  @override
  void dispose() {
    _torchOn.dispose();
    super.dispose();
  }

  void _onCounted(List<String> lines, DateTime at) {
    for (final l in lines) {
      HistoryDb.instance.addOccurrence(type: RecordType.text, content: l, at: at);
    }
    ScanFeedback.instance.counted();
    if (!mounted) return;
    setState(() {
      _recent.insertAll(0, lines);
      if (_recent.length > 50) _recent.removeRange(50, _recent.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      appBar: AppBar(
        title: const Text('连续识字'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _torchOn,
            builder: (context, on, _) => IconButton(
              icon: Icon(on ? Icons.flashlight_on : Icons.flashlight_off),
              tooltip: '闪光灯',
              onPressed: () => _viewKey.currentState?.toggleTorch(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '识字记录',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: height * 0.45,
            child: ColoredBox(
              color: Colors.black,
              child: TextScanView(key: _viewKey, onCounted: _onCounted, torchOn: _torchOn),
            ),
          ),
          Expanded(
            child: _recent.isEmpty
                ? const Center(child: Text('识别到的文字会显示在这里，并保存到识字记录'))
                : ListView.separated(
                    itemCount: _recent.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(_recent[i]),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _recent[i]));
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                            content: Text('已复制'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ));
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
