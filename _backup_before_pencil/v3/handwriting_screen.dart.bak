import 'package:flutter/material.dart';

import '../models/handwriting_style.dart';
import '../services/my_handwriting/hw_profile.dart';
import '../services/my_handwriting/hw_render.dart';
import '../theme/app_theme.dart';
import 'my_handwriting_screen.dart';

/// Кол жазманын 7 түрүнөн бирин мышка менен тандоо бети.
class HandwritingScreen extends StatefulWidget {
  final HandwritingStyle? selected;

  const HandwritingScreen({super.key, this.selected});

  @override
  State<HandwritingScreen> createState() => _HandwritingScreenState();
}

class _HandwritingScreenState extends State<HandwritingScreen> {
  HandwritingStyle? _picked;
  bool _mineReady = false;
  List<HwLineImage> _minePreview = const [];

  static const _sample =
      'Омдун мыйзамы: чынжырдын бөлүгүндөгү ток күчү чыңалууга түз '
      'пропорционал. Өткөргүчтүн каршылыгы ү, ө, ң тамгалары менен.';

  @override
  void initState() {
    super.initState();
    _picked = widget.selected;
    _loadMine();
  }

  /// "Менин кол жазмам" даярбы жана алдын ала көрүнүшүн даярдайт.
  Future<void> _loadMine() async {
    final profile = await MyHandwritingStore.load();
    final ready = profile != null && profile.usable;
    var preview = <HwLineImage>[];
    if (ready) {
      preview = HwRender.renderParagraph(profile, _sample,
          sizePt: 13, availPt: 440, lineHeight: 1.45, seed: 3);
    }
    if (!mounted) return;
    setState(() {
      _mineReady = ready;
      _minePreview = preview;
      if (!ready && _picked == HandwritingStyle.mine) _picked = null;
    });
  }

  Future<void> _openTeach() async {
    final wasReady = _mineReady;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MyHandwritingScreen()),
    );
    await _loadMine();
    if (mounted && _mineReady && !wasReady) {
      setState(() => _picked = HandwritingStyle.mine);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Текст тандалган кол жазма менен жазылат. Сүрөттөр, '
                  'графиктер жана формулалар өзгөрүүсүз калат.',
                  style: TextStyle(fontSize: 13, color: AppTheme.muted),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    _mineCard(),
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
                        _picked == null
                            ? 'Кол жазма тандалган жок'
                            : 'Тандалды: ${_picked!.label}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _picked == null
                          ? null
                          : () => Navigator.pop(context, _picked),
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

  Widget _mineCard() {
    final s = HandwritingStyle.mine;
    final sel = _picked == s && _mineReady;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_mineReady) {
              setState(() => _picked = s);
            } else {
              _openTeach();
            }
          },
          onDoubleTap: _mineReady ? () => Navigator.pop(context, s) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.primary.withValues(alpha: 0.06)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel ? AppTheme.primary : AppTheme.line,
                width: sel ? 2 : 1,
              ),
            ),
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
                      Text(
                        _mineReady
                            ? 'Сиздин өз кол жазмаңыз — текст сиздин '
                                'тамгаларыңыз менен жазылат'
                            : s.note,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.muted),
                      ),
                      const SizedBox(height: 10),
                      if (_mineReady && _minePreview.isNotEmpty)
                        Container(
                          width: double.infinity,
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
                                for (final l in _minePreview)
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
                          onPressed: _openTeach,
                          icon: const Icon(Icons.draw_outlined, size: 18),
                          label: Text(_mineReady
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
          onTap: () => setState(() => _picked = s),
          onDoubleTap: () => Navigator.pop(context, s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.primary.withValues(alpha: 0.06)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel ? AppTheme.primary : AppTheme.line,
                width: sel ? 2 : 1,
              ),
            ),
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
