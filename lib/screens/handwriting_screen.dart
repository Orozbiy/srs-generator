import 'package:flutter/material.dart';

import '../models/handwriting_style.dart';
import '../services/my_handwriting/hw_profile.dart';
import '../services/my_handwriting/hw_render.dart';
import '../theme/app_theme.dart';
import 'my_handwriting_screen.dart';

/// Тандалган кол жазма: даяр шрифт же кимдир бирөөнүн өз кол жазмасы.
class HandChoice {
  final HandwritingStyle style;

  /// «Менин кол жазмам» болсо — кимдики (профилдин id'си жана аты).
  final String? profileId;
  final String? profileName;
  const HandChoice(this.style, [this.profileId, this.profileName]);

  String get label => style == HandwritingStyle.mine
      ? (profileName ?? style.label)
      : style.label;
}

class _Mine {
  final HwProfileInfo info;
  final bool ready;
  final List<HwLineImage> preview;
  const _Mine(this.info, this.ready, this.preview);
}

/// Кол жазманы тандоо бети: адамдардын өз кол жазмалары + даяр шрифттер.
class HandwritingScreen extends StatefulWidget {
  final HandwritingStyle? selected;
  final String? selectedProfile;

  const HandwritingScreen({super.key, this.selected, this.selectedProfile});

  @override
  State<HandwritingScreen> createState() => _HandwritingScreenState();
}

class _HandwritingScreenState extends State<HandwritingScreen> {
  HandwritingStyle? _picked;
  String? _pickedProfile;
  List<_Mine> _mines = const [];
  bool _loading = true;

  static const _sample =
      'Омдун мыйзамы: чынжырдын бөлүгүндөгү ток күчү чыңалууга түз '
      'пропорционал. Өткөргүчтүн каршылыгы ү, ө, ң тамгалары менен.';

  @override
  void initState() {
    super.initState();
    _picked = widget.selected;
    _pickedProfile = widget.selected == HandwritingStyle.mine
        ? (widget.selectedProfile ?? MyHandwritingStore.defaultId)
        : null;
    _loadMines();
  }

  /// Бардык адамдардын кол жазмасын жана алдын ала көрүнүшүн жүктөйт.
  Future<void> _loadMines() async {
    final list = <_Mine>[];
    for (final p in await MyHandwritingStore.profiles()) {
      final prof = await MyHandwritingStore.load(profile: p.id);
      final ready = prof != null && prof.usable;
      var preview = <HwLineImage>[];
      if (prof != null && prof.usable) {
        preview = HwRender.renderParagraph(prof, _sample,
            sizePt: 13, availPt: 440, lineHeight: 1.45, seed: 3);
      }
      list.add(_Mine(p, ready, preview));
    }
    if (!mounted) return;
    setState(() {
      _mines = list;
      _loading = false;
      if (_picked == HandwritingStyle.mine &&
          !list.any((m) => m.info.id == _pickedProfile && m.ready)) {
        _picked = null;
        _pickedProfile = null;
      }
    });
  }

  _Mine? _mineById(String? id) {
    for (final m in _mines) {
      if (m.info.id == id) return m;
    }
    return null;
  }

  Future<void> _openTeach(HwProfileInfo p) async {
    final wasReady = _mineById(p.id)?.ready ?? false;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MyHandwritingScreen(profileId: p.id, profileName: p.name),
      ),
    );
    await _loadMines();
    final now = _mineById(p.id);
    if (mounted && now != null && now.ready && !wasReady) {
      setState(() {
        _picked = HandwritingStyle.mine;
        _pickedProfile = p.id;
      });
    }
  }

  Future<String?> _askName({String initial = '', required String title}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Мисалы: Айгерим, Бакыт, 2-курс Нурбек',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Жокко чыгаруу'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Сактоо'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProfile() async {
    final name = await _askName(title: 'Жаңы кол жазма — кимдики?');
    if (name == null || name.trim().isEmpty) return;
    final p = await MyHandwritingStore.addProfile(name);
    await _loadMines();
    if (!mounted) return;
    await _openTeach(p);
  }

  Future<void> _rename(HwProfileInfo p) async {
    final name = await _askName(initial: p.name, title: 'Атын өзгөртүү');
    if (name == null || name.trim().isEmpty) return;
    await MyHandwritingStore.renameProfile(p.id, name);
    await _loadMines();
  }

  Future<void> _delete(HwProfileInfo p) async {
    final isDefault = p.id == MyHandwritingStore.defaultId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDefault ? 'Тамгаларды өчүрөсүзбү?' : 'Өчүрөсүзбү?'),
        content: Text(isDefault
            ? '«${p.name}» кол жазмасынын бардык жүктөлгөн тамгалары '
                'өчүрүлөт. Аларды кайра жүктөөгө туура келет.'
            : '«${p.name}» кол жазмасы жана анын бардык тамгалары биротоло '
                'өчүрүлөт.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Жок'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Өчүрүү'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MyHandwritingStore.deleteProfile(p.id);
    if (_pickedProfile == p.id) {
      _picked = null;
      _pickedProfile = null;
    }
    await _loadMines();
  }

  HandChoice? get _choice {
    final s = _picked;
    if (s == null) return null;
    if (s != HandwritingStyle.mine) return HandChoice(s);
    final m = _mineById(_pickedProfile);
    if (m == null || !m.ready) return null;
    return HandChoice(s, m.info.id, m.info.name);
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    return Scaffold(
      appBar: AppBar(title: const Text('Кол жазманы тандаңыз')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Text(
                  'Текст тандалган кол жазма менен жазылат. Бир нече адамдын '
                  'кол жазмасын кошуп, ар бир СРС үчүн керектүүсүн тандай '
                  'аласыз.',
                  style: TextStyle(fontSize: 13, color: AppTheme.muted),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('Адамдардын өз кол жазмасы',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          for (final m in _mines) _mineCard(m),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: OutlinedButton.icon(
                              onPressed: _addProfile,
                              icon: const Icon(Icons.add),
                              label: const Text('Кол жазма кошуу'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('Даяр кол жазмалар',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          for (final s in HandwritingStyle.values)
                            if (s != HandwritingStyle.mine) _card(s),
                        ],
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
                        choice == null
                            ? 'Кол жазма тандалган жок'
                            : 'Тандалды: ${choice.label}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: choice == null
                          ? null
                          : () => Navigator.pop(context, choice),
                      icon: const Icon(Icons.check),
                      label: const Text('Тандоо'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _box(bool sel) => BoxDecoration(
        color: sel ? AppTheme.primary.withValues(alpha: 0.06) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: sel ? AppTheme.primary : AppTheme.line,
          width: sel ? 2 : 1,
        ),
      );

  Widget _mineCard(_Mine m) {
    final p = m.info;
    final sel = _picked == HandwritingStyle.mine &&
        _pickedProfile == p.id &&
        m.ready;
    final isDefault = p.id == MyHandwritingStore.defaultId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (m.ready) {
              setState(() {
                _picked = HandwritingStyle.mine;
                _pickedProfile = p.id;
              });
            } else {
              _openTeach(p);
            }
          },
          onDoubleTap: m.ready
              ? () => Navigator.pop(
                  context, HandChoice(HandwritingStyle.mine, p.id, p.name))
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            decoration: _box(sel),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(
                    sel ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: sel ? AppTheme.primary : AppTheme.muted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 18, color: AppTheme.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(p.name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Дагы',
                            onSelected: (v) {
                              if (v == 'rename') _rename(p);
                              if (v == 'delete') _delete(p);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Атын өзгөртүү'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(isDefault
                                    ? 'Тамгаларын өчүрүү'
                                    : 'Өчүрүү'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        m.ready
                            ? 'Текст ушул адамдын тамгалары менен жазылат'
                            : 'Тамгалары али жүктөлгөн жок — үйрөтүңүз',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.muted),
                      ),
                      const SizedBox(height: 8),
                      if (m.ready && m.preview.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFEF8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.line),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final l in m.preview)
                                  Image.memory(
                                    l.png,
                                    width: l.widthPt,
                                    height: l.heightPt,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openTeach(p),
                          icon: const Icon(Icons.draw_outlined, size: 18),
                          label: Text(m.ready
                              ? 'Өзгөртүү / кайра үйрөтүү'
                              : 'Кол жазманы үйрөтүү'),
                        ),
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

  Widget _card(HandwritingStyle s) {
    final sel = _picked == s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            _picked = s;
            _pickedProfile = null;
          }),
          onDoubleTap: () => Navigator.pop(context, HandChoice(s)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: _box(sel),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: sel ? AppTheme.primary : AppTheme.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(s.note,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.muted)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFEF8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.line),
                        ),
                        child: Text(
                          _sample,
                          style: TextStyle(
                            fontFamily: s.family,
                            fontSize: 19 * s.scale,
                            height: 1.4,
                            color: const Color(0xFF1F2F7A),
                          ),
                        ),
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
}
