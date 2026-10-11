import 'package:flutter/material.dart';

import '../models/doc_item.dart';
import '../theme/app_theme.dart';

enum _Filter { all, headings, lists, selected }

/// Жүктөлгөн документтин бардык бөлүктөрүн тизме кылып көрсөтөт.
/// Колдонуучу каалаганын белгилейт — СРС ошол бөлүктөр боюнча толукталат.
class DocumentSelectScreen extends StatefulWidget {
  final String fileName;
  final List<DocItem> items;

  const DocumentSelectScreen({
    super.key,
    required this.fileName,
    required this.items,
  });

  @override
  State<DocumentSelectScreen> createState() => _DocumentSelectScreenState();
}

class _DocumentSelectScreenState extends State<DocumentSelectScreen> {
  late final List<DocItem> _items;
  final TextEditingController _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((e) => e.copy()).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<int> get _visible {
    final q = _search.text.trim().toLowerCase();
    final out = <int>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_filter == _Filter.headings && !it.isHeading) continue;
      if (_filter == _Filter.lists && !it.isListItem) continue;
      if (_filter == _Filter.selected && !it.selected) continue;
      if (q.isNotEmpty && !it.text.toLowerCase().contains(q)) continue;
      out.add(i);
    }
    return out;
  }

  int get _selectedCount => _items.where((e) => e.selected).length;

  int get _selectedChars => _items
      .where((e) => e.selected)
      .fold<int>(0, (sum, e) => sum + e.text.length);

  void _toggle(int i, bool value) {
    setState(() {
      _items[i].selected = value;
      // Аталышты белгилесе — анын бөлүмүндөгү бардык пункттар да белгиленет.
      if (_items[i].isHeading) {
        for (var j = i + 1; j < _items.length && !_items[j].isHeading; j++) {
          _items[j].selected = value;
        }
      }
    });
  }

  void _setAll(bool value) {
    setState(() {
      // Издөө/чыпка иштеп турса — көрүнгөндөргө гана колдонулат.
      for (final i in _visible) {
        _items[i].selected = value;
      }
    });
  }

  void _done() => Navigator.of(context).pop(_items);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Документтен тандаңыз'),
          actions: [
            TextButton(
                onPressed: () => _setAll(true), child: const Text('Баарын')),
            TextButton(
                onPressed: () => _setAll(false),
                child: const Text('Тазалоо')),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.fileName} — СРС тандалган бөлүктөр боюнча '
                      'жазылат. Аталышты белгилесеңиз, анын бөлүмү толугу '
                      'менен белгиленет.',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppTheme.muted),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Документтен издөө...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(() => _search.clear()),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _chip('Баары', _Filter.all),
                        _chip('Аталыштар', _Filter.headings),
                        _chip('Тизмелер', _Filter.lists),
                        _chip('Тандалгандар', _Filter.selected),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppTheme.line),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text('Эч нерсе табылган жок',
                              style: TextStyle(color: AppTheme.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: visible.length,
                          itemBuilder: (context, k) => _row(visible[k]),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(top: BorderSide(color: AppTheme.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Тандалды: $_selectedCount / ${_items.length} · '
                          '$_selectedChars символ',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _done,
                        icon: const Icon(Icons.check),
                        label: const Text('Даяр'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, _Filter f) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == f,
      onSelected: (_) => setState(() => _filter = f),
    );
  }

  Widget _row(int i) {
    final it = _items[i];
    final TextStyle style = it.isHeading
        ? const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)
        : TextStyle(
            fontSize: 13,
            height: 1.35,
            color: it.selected ? AppTheme.ink : AppTheme.muted);
    return Padding(
      padding: EdgeInsets.only(top: it.isHeading ? 8 : 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle(i, !it.selected),
        child: Container(
          decoration: BoxDecoration(
            color: it.selected
                ? AppTheme.primary.withValues(alpha: it.isHeading ? 0.10 : 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.fromLTRB(it.isListItem ? 20 : 4, 2, 8, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: it.selected,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _toggle(i, v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 7),
                  child: Text(
                    it.text,
                    maxLines: it.isHeading ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
