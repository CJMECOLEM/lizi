import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../expiry/expiry_math.dart';
import '../models/expiry_item.dart';
import '../models/product.dart';
import '../services/expiry_db.dart';
import '../services/photo_store.dart';
import '../services/product_db.dart';
import '../widgets/dialogs.dart';
import '../widgets/expiry_style.dart';

/// What is known about a check before it is saved; also used to edit a saved
/// item.
class ExpiryDraft {
  ExpiryDraft({
    this.id,
    this.barcode = '',
    this.name = '',
    this.productionDate,
    this.shelfLife,
    this.printedExpiry,
    this.photo = '',
    this.lines = const [],
    this.qty = 1,
    this.unit = defaultUnit,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ExpiryDraft.of(ExpiryItem it) {
    final computed = it.productionDate != null && it.shelfLife != null
        ? it.shelfLife!.lastDayFrom(it.productionDate!)
        : null;
    return ExpiryDraft(
      id: it.id,
      barcode: it.barcode,
      name: it.name,
      productionDate: it.productionDate,
      shelfLife: it.shelfLife,
      printedExpiry: computed == it.expiryDate ? null : it.expiryDate,
      photo: it.photo,
      lines: it.ocrText.isEmpty ? const [] : it.ocrText.split('\n'),
      createdAt: it.createdAt,
      qty: it.qty,
      unit: it.unit,
    );
  }

  final int? id;
  final String barcode;
  final String name;
  final DateTime? productionDate;
  final ShelfLife? shelfLife;

  /// An expiry date read from the package or entered by hand; overrides the
  /// computed one.
  final DateTime? printedExpiry;
  final String photo;
  final List<String> lines;
  final DateTime createdAt;
  final int qty;
  final String unit;

  DateTime? get lastDay =>
      printedExpiry ??
      (productionDate != null && shelfLife != null
          ? shelfLife!.lastDayFrom(productionDate!)
          : null);

  ExpiryItem? toItem() {
    final last = lastDay;
    if (last == null) return null;
    return ExpiryItem(
      id: id,
      barcode: barcode,
      name: name,
      productionDate: productionDate,
      shelfLife: shelfLife,
      expiryDate: last,
      photo: photo,
      ocrText: lines.join('\n'),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      qty: qty,
      unit: stockUnit(unit),
    );
  }
}

typedef ExpiryEditResult = ({ExpiryItem? saved, bool deleted});

Future<ExpiryEditResult?> editExpiry(BuildContext context, ExpiryDraft draft) =>
    Navigator.of(context).push<ExpiryEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ExpiryEditPage(draft: draft),
      ),
    );

class ExpiryEditPage extends StatefulWidget {
  const ExpiryEditPage({super.key, required this.draft});
  final ExpiryDraft draft;

  @override
  State<ExpiryEditPage> createState() => _ExpiryEditPageState();
}

class _ExpiryEditPageState extends State<ExpiryEditPage> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _barcode = TextEditingController(text: widget.draft.barcode);
  late final _quantity = TextEditingController(text: '${widget.draft.qty}');
  late final _unit = TextEditingController(text: widget.draft.unit);
  bool _unitEdited = false;
  late final _shelfValue = TextEditingController(
    text: widget.draft.shelfLife?.value.toString() ?? '',
  );
  late ShelfLifeUnit _shelfUnit =
      widget.draft.shelfLife?.unit ?? ShelfLifeUnit.month;
  late DateTime? _production = widget.draft.productionDate;
  late DateTime? _manualExpiry = widget.draft.printedExpiry;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _quantity.dispose();
    _unit.dispose();
    _shelfValue.dispose();
    super.dispose();
  }

  ShelfLife? get _shelf {
    final n = int.tryParse(_shelfValue.text);
    return n == null || n <= 0 ? null : ShelfLife(n, _shelfUnit);
  }

  DateTime? get _computed {
    final p = _production;
    final s = _shelf;
    return p == null || s == null ? null : s.lastDayFrom(p);
  }

  DateTime? get _lastDay => _manualExpiry ?? _computed;

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  Future<void> _save() async {
    if (_saving) return;
    final d = widget.draft;
    final qty = int.tryParse(_quantity.text);
    if (qty == null || qty < (d.id == null ? 1 : 0) || qty > 2147483647) {
      showToast(context, d.id == null ? '入库数量须为正整数' : '库存数量须为非负整数');
      return;
    }
    setState(() => _saving = true);
    try {
      var unit = stockUnit(_unit.text);
      if (d.id == null && !_unitEdited) {
        final remembered = _barcode.text.trim().isNotEmpty
            ? await ProductDb.instance.get(_barcode.text.trim())
            : await ExpiryDb.instance.rememberedByName(_name.text.trim());
        unit = remembered?.unit ?? unit;
      }
      if (!mounted) return;
      final draft = ExpiryDraft(
        id: d.id,
        barcode: _barcode.text.trim(),
        name: _name.text.trim(),
        productionDate: _production,
        shelfLife: _shelf,
        printedExpiry: _manualExpiry,
        photo: d.photo,
        lines: d.lines,
        createdAt: d.createdAt,
        qty: qty,
        unit: unit,
      );
      final item = draft.toItem();
      if (item == null) {
        if (mounted) showToast(context, '请填写到期日，或者生产日期和保质期');
        return;
      }
      var saved = item;
      if (item.id == null) {
        final r = await ExpiryDb.instance.add(item);
        saved = r.item;
        if (r.existed) {
          if (item.photo.isNotEmpty && item.photo != saved.photo) {
            await PhotoStore.delete(item.photo);
          }
        }
      } else {
        await ExpiryDb.instance.update(item);
      }
      try {
        await ProductDb.instance.remember(
          saved.barcode,
          name: saved.name,
          shelfLife: saved.shelfLife,
          unit: saved.unit,
        );
      } catch (_) {
        if (mounted) showToast(context, '已保存批次，但商品默认参数未能更新');
      }
      if (mounted) {
        Navigator.pop<ExpiryEditResult>(context, (
          saved: saved,
          deleted: false,
        ));
      }
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.draft.id;
    if (id == null) return;
    if (!await confirm(
      context,
      title: '删除这条记录？',
      ok: '删除',
      destructive: true,
    )) {
      return;
    }
    await ExpiryDb.instance.delete(id);
    await PhotoStore.delete(widget.draft.photo);
    if (mounted) {
      Navigator.pop<ExpiryEditResult>(context, (saved: null, deleted: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    final last = _lastDay;
    final now = DateTime.now();
    final nameChoices = d.lines
        .where((l) => l.length >= 2 && l.length <= 30)
        .take(40)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(d.id == null ? '补填保质期' : '修改保质期'),
        actions: [
          if (d.id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (last != null) _Preview(lastDay: last, now: now),
          if (d.photo.isNotEmpty && File(d.photo).existsSync())
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () => _showPhoto(context, d.photo),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(d.photo),
                    height: 180,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '商品名称',
              border: OutlineInputBorder(),
            ),
          ),
          if (nameChoices.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('点选识别出的文字作为名称', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final l in nameChoices)
                  ActionChip(
                    label: Text(l, overflow: TextOverflow.ellipsis),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _name.text = l),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: d.id == null ? '本次入库数量' : '批次库存数量',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unit,
                  onChanged: (_) => _unitEdited = true,
                  decoration: const InputDecoration(
                    labelText: '单位',
                    hintText: '件 / 盒 / 瓶',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _barcode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '条码（可不填）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('生产日期'),
            subtitle: Text(
              _production == null ? '未填' : formatDate(_production!),
            ),
            trailing: _production == null
                ? const Icon(Icons.edit_calendar)
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _production = null),
                  ),
            onTap: () async {
              final v = await _pickDate(_production);
              if (v != null) setState(() => _production = v);
            },
          ),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _shelfValue,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '保质期',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<ShelfLifeUnit>(
                  segments: [
                    for (final u in ShelfLifeUnit.values)
                      ButtonSegment(value: u, label: Text(u.label)),
                  ],
                  selected: {_shelfUnit},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      setState(() => _shelfUnit = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('到期日（最后有效日）'),
            subtitle: Text(
              last == null
                  ? '未填'
                  : '${formatDate(last)}  ${_manualExpiry == null ? '按生产日期 + 保质期计算' : '包装上印的或手动填写'}',
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final v = await _pickDate(last);
              if (v != null) setState(() => _manualExpiry = v);
            },
          ),
          if (_manualExpiry != null &&
              _computed != null &&
              _computed != _manualExpiry)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _manualExpiry = null),
                child: Text('改用计算结果 ${formatDate(_computed!)}'),
              ),
            ),
        ],
      ),
    );
  }

  void _showPhoto(BuildContext context, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.file(File(path))),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.lastDay, required this.now});
  final DateTime lastDay;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final style = ExpiryStyle.of(
      expiryLevel(lastDay, now),
      Theme.of(context).colorScheme,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.accent),
      ),
      child: Text(
        '${formatDate(lastDay)} 到期 · ${remainingLabel(lastDay, now)}',
        style: TextStyle(
          color: style.foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
