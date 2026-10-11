import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../services/my_handwriting/hw_geom.dart';
import '../services/my_handwriting/hw_importer.dart';
import '../services/my_handwriting/hw_profile.dart';
import '../services/my_handwriting/hw_render.dart';
import '../services/my_handwriting/hw_template.dart';
import '../theme/app_theme.dart';

/// Колдонуучунун өз кол жазмасын үйрөтүү: шаблон -> жазуу -> сүрөт жүктөө.
class MyHandwritingScreen extends StatefulWidget {
  const MyHandwritingScreen({super.key});

  @override
  State<MyHandwritingScreen> createState() => _MyHandwritingScreenState();
}

class _MyHandwritingScreenState extends State<MyHandwritingScreen> {
  List<int> _counts = List<int>.filled(HwGeom.pageCount, 0);
  Map<String, int> _freeCounts = {};
  MyHandwriting? _profile;
  List<HwLineImage> _preview = const [];
  bool _busy = false;
  String _busyText = '';

  static const _sample =
      'Омдун мыйзамы: чынжырдын бөлүгүндөгү ток күчү чыңалууга түз '
      'пропорционал. Өткөргүчтүн каршылыгы ү, ө, ң тамгалары менен: '
      'U = I R, 12 В, 3,5 А.';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final counts = await MyHandwritingStore.pageCounts();
    final profile = await MyHandwritingStore.load();
    final free = <String, int>{};
    for (final st in HwGeom.freeSets) {
      free[st.id] = await MyHandwritingStore.freeCount(st);
    }
    var preview = <HwLineImage>[];
    if (profile != null && profile.usable) {
      preview = HwRender.renderParagraph(profile, _sample,
          sizePt: 16, availPt: 470, lineHeight: 1.5, seed: 7);
    }
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _freeCounts = free;
      _profile = profile;
      _preview = preview;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openTemplate() async {
    setState(() {
      _busy = true;
      _busyText = 'Шаблон даярдалып жатат...';
    });
    try {
      final bytes = await HwTemplate.build();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}kol_jazma_shablon.pdf');
      await file.writeAsBytes(bytes, flush: true);
      final res = await OpenFile.open(file.path);
      if (res.type != ResultType.done) {
        _snack('PDF автоматтык ачылган жок. Файл: ${file.path}');
      }
    } catch (e) {
      _snack('Шаблонду түзүү мүмкүн болгон жок: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPage(int page) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _snack('Файлды окуу мүмкүн болгон жок.');
      return;
    }

    setState(() {
      _busy = true;
      _busyText = '${page + 1}-барак иштетилип жатат...';
    });
    try {
      final res = await HwImporter.importPage(page, bytes);
      if (res.ok && res.bin != null) {
        await MyHandwritingStore.savePage(page, res.bin!);
        await _reload();
      }
      _snack(res.message);
    } catch (e) {
      _snack('Ката: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFree(HwSet set) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _snack('Файлды окуу мүмкүн болгон жок.');
      return;
    }
    setState(() {
      _busy = true;
      _busyText = '${set.title} иштетилип жатат...';
    });
    try {
      final res = await HwImporter.importFreeform(set.id, bytes);
      if (res.ok && res.bin != null) {
        await MyHandwritingStore.saveFree(set.id, res.bin!);
        await _reload();
        _snack(res.message);
      } else {
        await _showError(set.title, res.message);
      }
    } catch (e) {
      _snack('Ката: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showError(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(height: 1.45)),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Түшүндүм')),
        ],
      ),
    );
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Кол жазманы өчүрөсүзбү?'),
        content: const Text('Бардык жүктөлгөн тамгалар өчүрүлөт.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Жок')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Өчүрүү')),
        ],
      ),
    );
    if (ok != true) return;
    await MyHandwritingStore.deleteAll();
    await _reload();
  }

  bool get _ready => _profile != null && _profile!.usable;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_ready);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Менин кол жазмам'),
          actions: [
            if (_profile != null)
              TextButton.icon(
                onPressed: _busy ? null : _deleteAll,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Өчүрүү'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: [
                      _stepCard(
                        number: 1,
                        title: 'Шаблонду басып чыгарыңыз',
                        text:
                            'A4 форматында ${HwGeom.pageCount} барак. Басып '
                            'чыгарууда масштабды 100% кылыңыз (“Fit to page” '
                            'эмес).',
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _openTemplate,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Шаблонду ачуу (PDF)'),
                        ),
                      ),
                      _stepCard(
                        number: 2,
                        title: 'Тамгаларды жазыңыз',
                        text:
                            'Ар бир чиймеге көрсөтүлгөн тамганы кара сыя же '
                            'ручка менен, адаттагыдай өлчөмдө, ичке сызыктын '
                            'үстүнө жазыңыз. Чийменин четине жана бурчтагы '
                            'кара квадраттарга тийбеңиз.',
                      ),
                      _stepCard(
                        number: 3,
                        title: 'Ар бир баракты сүрөткө тартып жүктөңүз',
                        text:
                            'Баракты үстөлгө жайып, түз жогортон тартыңыз. '
                            'Төрт кара квадрат толук көрүнсүн, жарык тегиз '
                            'болсун (же сканер колдонуңуз).',
                        child: Column(
                          children: [
                            for (var p = 0; p < HwGeom.pageCount; p++)
                              _pageRow(p),
                          ],
                        ),
                      ),
                      _freeCard(),
                      if (_profile != null) _checkCard(),
                      if (_preview.isNotEmpty) _previewCard(),
                      if (_profile != null && !_profile!.usable)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Колдонуу үчүн жок дегенде кичине кирилл тамгаларды '
                            'жүктөңүз (1-барак же “Кичине тамгалар”).',
                            style: TextStyle(
                                fontSize: 12.5, color: AppTheme.warning),
                          ),
                        ),
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
                          _busy
                              ? _busyText
                              : _ready
                                  ? 'Кол жазма даяр'
                                  : 'Кол жазма азырынча даяр эмес',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(_ready),
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

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: child,
    );
  }

  Widget _stepCard({
    required int number,
    required String title,
    required String text,
    Widget? child,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.primary,
                child: Text('$number',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.muted, height: 1.4)),
          if (child != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: child),
          ],
        ],
      ),
    );
  }

  Widget _glyphTile(String ch) {
    final g = _profile?.glyphs[ch.codeUnitAt(0)];
    return Container(
      width: 54,
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      decoration: BoxDecoration(
        color: g == null ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: g == null ? AppTheme.error : AppTheme.line),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Center(
              child: g == null
                  ? const Icon(Icons.close, size: 16, color: AppTheme.error)
                  : Image.memory(
                      HwRender.glyphPng(g),
                      height: 40,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Text(ch,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _checkCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Тамгаларды текшериңиз',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Ар бир сүрөттүн астындагы тамга дал келип турушу керек. Эгер '
            'бир жерден жылып кетсе (мисалы «ч»-нын ордунда «ш» турса), ошол '
            'топтомду кайра жүктөңүз: бир тамга жазылбай калган же эки тамга '
            'бири-бирине тийип калган.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          for (final st in HwGeom.freeSets)
            if ((_freeCounts[st.id] ?? 0) > 0) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 2),
                child: Text(st.title,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Wrap(children: [
                for (final ch in (st.id == 'lower'
                        ? HwGeom.kyLowerAll
                        : st.id == 'upper'
                            ? HwGeom.kyUpperAll
                            : st.chars)
                    .split(''))
                  _glyphTile(ch)
              ]),
            ],
        ],
      ),
    );
  }

  Widget _freeCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Же шаблонсуз: дептерге жазып, сүрөткө тартыңыз',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Тамгаларды алфавит тартибинде, бир же бир нече сапка жазыңыз. '
            'Тамгалар бири-бирине тийбесин (ортосунда боштук болсун), кара '
            'же көк ручка менен. Сапта тамгадан башка эч нерсе жазбаңыз '
            '(сөз, нумерация жок). Ө, Ү, Ң тамгалары өз ордунда болсун. '
            'Ё жана Й тамгаларын ЖАЗБАҢЫЗ — аларды программа Е жана И '
            'тамгаларыңыздан өзү жасайт (чекит жана кашка ручка менен '
            'кошулат). '
            'Ар бир топтомго өзүнчө сүрөт жүктөйсүз.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          for (final st in HwGeom.freeSets) _freeRow(st),
        ],
      ),
    );
  }

  Widget _freeRow(HwSet st) {
    final got = _freeCounts[st.id] ?? 0;
    final done = got > 0;
    final chars = st.chars.length > 40 ? '${st.chars.substring(0, 40)}…' : st.chars;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? AppTheme.success : AppTheme.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(st.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  done
                      ? 'Жүктөлдү: $got / ${st.chars.length}'
                      : 'Тартип: $chars',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _importFree(st),
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(done ? 'Кайра жүктөө' : 'Сүрөт жүктөө'),
          ),
        ],
      ),
    );
  }

  Widget _pageRow(int p) {
    final chars = HwGeom.pageChars(p);
    final expected = chars.length;
    final got = _counts[p];
    final done = got > 0;
    final shown = chars.length > 14 ? '${chars.substring(0, 14)}…' : chars;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? AppTheme.success : AppTheme.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p + 1}-барак  ($shown)',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  done
                      ? 'Жүктөлдү: $got / $expected тамга'
                      : 'Жүктөлө элек',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _importPage(p),
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(done ? 'Кайра жүктөө' : 'Сүрөт жүктөө'),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    final missing = _profile?.missingLetters ?? const <String>[];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Алдын ала көрүү',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
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
                  for (final l in _preview)
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
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Табылбаган тамгалар: ${missing.join(' ')} — ушул тамгалар '
              'жазылбай калат. Шаблонду кайра жүктөп көрүңүз.',
              style: const TextStyle(fontSize: 12, color: AppTheme.warning),
            ),
          ],
        ],
      ),
    );
  }
}
