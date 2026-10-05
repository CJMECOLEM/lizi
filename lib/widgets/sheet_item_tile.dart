import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stock_sheet.dart';
import '../services/inventory_db.dart';
import '../services/product_db.dart';
import 'dialogs.dart';

String itemTitle(SheetItem it) => it.hasName ? it.name : it.barcode;

/// One counted line: name, barcode and a −/quantity/+ stepper. Swipe left to
/// delete (undoable); tap for more actions.
class SheetItemTile extends StatelessWidget {
  const SheetItemTile({
    super.key,
    required this.item,
    required this.onRemove,
    this.dense = false,
  });

  final SheetItem item;

  /// Called on swipe; the parent must drop the line from its list right away.
  final VoidCallback onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('${item.sheetId}|${item.barcode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        dense: dense,
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        title: Text(itemTitle(item), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          item.hasName ? item.barcode : '未填品名',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: item.hasName ? null : TextStyle(color: theme.colorScheme.outline),
        ),
        trailing: _QtyStepper(item: item),
        onTap: () => showItemActions(context, item, onRemove: onRemove),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.item});
  final SheetItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = InventoryDb.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: '减一',
          visualDensity: VisualDensity.compact,
          onPressed: item.qty <= 0 ? null : () => db.add(item.sheetId, item.barcode, -1),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final n = await askNewQuantity(context, title: itemTitle(item), current: item.qty);
            if (n != null) await db.setQuantity(item.sheetId, item.barcode, n);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${item.qty}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '加一',
          visualDensity: VisualDensity.compact,
          onPressed: () => db.add(item.sheetId, item.barcode, 1),
        ),
      ],
    );
  }
}

Future<void> showItemActions(BuildContext context, SheetItem item, {required VoidCallback onRemove}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              children: [
                Text(itemTitle(item), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                SelectableText(item.barcode, textAlign: TextAlign.center),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(item.hasName ? '修改品名' : '填写品名'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await askText(context, title: item.barcode, label: '品名', initial: item.name);
              if (name == null || name.isEmpty) return;
              await ProductDb.instance.remember(item.barcode, name: name);
              // Lists join names from the product table; nudge them to reload.
              InventoryDb.instance.refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('修改数量'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final n = await askNewQuantity(context, title: itemTitle(item), current: item.qty);
              if (n != null) await InventoryDb.instance.setQuantity(item.sheetId, item.barcode, n);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制条码'),
            onTap: () {
              Navigator.pop(sheetContext);
              Clipboard.setData(ClipboardData(text: item.barcode));
              showToast(context, '已复制');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除这一行', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(sheetContext);
              onRemove();
            },
          ),
        ],
      ),
    ),
  );
}
