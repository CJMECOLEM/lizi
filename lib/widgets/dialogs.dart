import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void showToast(BuildContext context, String msg, {Duration duration = const Duration(seconds: 2)}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: duration, behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String ok = '确定',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(ok, style: destructive ? const TextStyle(color: Colors.red) : null),
        ),
      ],
    ),
  );
  return result == true;
}

/// Asks for a new quantity.
Future<int?> askNewQuantity(BuildContext context, {required String title, required int current}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(title: title, initial: '$current', label: '数量', numeric: true),
  ).then((v) => v == null ? null : int.tryParse(v));
}

/// Asks for a line of text; returns null when cancelled.
Future<String?> askText(BuildContext context, {required String title, required String label, String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(title: title, initial: initial, label: label),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.initial, required this.label, this.numeric = false});
  final String title;
  final String initial;
  final String label;
  final bool numeric;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (widget.numeric && int.tryParse(v) == null) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: widget.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
