import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/doc_item.dart';
import '../models/srs_config.dart';
import '../models/handwriting_style.dart';
import '../services/ai_service.dart';
import '../services/document_reader.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import '../widgets/generation_dialog.dart';
import '../widgets/option_card.dart';
import 'document_select_screen.dart';
import 'editor_screen.dart';
import 'handwriting_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _topic = TextEditingController();
  final _ai = AiService();

  Subject _subject = Subject.physics;
  Language _language = Language.kyrgyz;
  PageCount _pages = PageCount.ten;
  bool _withDiagrams = true;
  bool _busy = false;
  bool _readingDoc = false;
  HandwritingStyle? _hand; // null — кадимки жазуу

  /// «Менин кол жазмам» тандалса — кимдики (профилдин id'си жана аты).
  String? _handProfile;
  String? _handProfileName;

  List<DocItem>? _docItems; // документтин бөлүктөрү (белгилери менен)
  String? _docName;

  /// AI'га берилүүчү текст — документтен тандалган бөлүктөр гана.
  String? get _docText {
    final items = _docItems;
    if (items == null) return null;
    final t = DocItem.join(items);
    return t.isEmpty ? null : t;
  }
  AuthorInfo _author = const AuthorInfo();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await PrefsService.apiKey();
    final author = await PrefsService.author();
    final (s, l, p, d) = await PrefsService.lastChoice();
    if (!mounted) return;
    setState(() {
      _author = author;
      _subject = s;
      _language = l;
      _pages = p;
      _withDiagrams = d;
    });
    _ai.init(key);
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (saved == true) {
      await _load();
      _snack('Жөндөөлөр сакталды');
    }
  }

  /// Документтин бөлүктөрүн тизме кылып көрсөтүп, тандатат (каалаган учурда).
  Future<void> _editSelection() async {
    final items = _docItems;
    if (items == null || !mounted) return;
    final result = await Navigator.push<List<DocItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentSelectScreen(
          fileName: _docName ?? 'Документ',
          items: items,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _docItems = result);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _snack('Файлды окуу мүмкүн болгон жок.');
      return;
    }

    setState(() => _readingDoc = true);
    try {
      final text = await DocumentReader.read(f.name, bytes);
      if (!mounted) return;
      setState(() {
        _docName = f.name;
        _docItems = DocItem.split(text);
      });
      // Документтин мазмунун көрсөтүп, тандатабыз.
      await _editSelection();
    } on DocumentReadException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Файлды окуу мүмкүн болгон жок.');
    } finally {
      if (mounted) setState(() => _readingDoc = false);
    }
  }

  Future<void> _chooseHandwriting() async {
    final picked = await Navigator.push<HandChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => HandwritingScreen(
          selected: _hand,
          selectedProfile: _handProfile,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _hand = picked.style;
        _handProfile = picked.profileId;
        _handProfileName = picked.profileName;
      });
    }
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.07)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppTheme.primary : AppTheme.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (_topic.text.trim().isEmpty) {
      _snack('Тема киргизиңиз');
      return;
    }
    if (!_ai.hasKey) {
      _showMissingKey();
      return;
    }
    if (_author.student.trim().isEmpty) {
      _snack('Жөндөөлөрдөн студенттин атын коюңуз');
      await _openSettings();
      return;
    }

    await PrefsService.setLastChoice(
        _subject, _language, _pages, _withDiagrams);

    final config = SrsConfig(
      subject: _subject,
      language: _language,
      pageCount: _pages,
      topic: _topic.text.trim(),
      documentText: _docText,
      withDiagrams: _withDiagrams,
      handwriting: _hand,
      handProfile: _hand == HandwritingStyle.mine ? _handProfile : null,
    );

    setState(() => _busy = true);
    try {
      if (!mounted) return;
      final content = await showDialog<String>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: false,
            builder: (_) => GenerationDialog(config: config, ai: _ai),
          ) ??
          '';
      if (content.trim().isEmpty) return;
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            config: config,
            author: _author,
            content: content,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMissingKey() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_off_outlined,
            color: AppTheme.warning, size: 36),
        title: const Text('API ачкыч жок'),
        content: const Text(
          'СРС жазуу үчүн Groq ачкычы керек. Ал акысыз жана банк картасы '
          'талап кылынбайт: console.groq.com/keys',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Кийин'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openSettings();
            },
            child: const Text('Жөндөөлөр'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories_outlined, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('СРС Генератор'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
            icon: const Icon(Icons.folder_open_outlined, size: 19),
            label: const Text('Менин СРСтерим'),
          ),
          IconButton(
            tooltip: 'Жөндөөлөр',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              _hero(),
              const SizedBox(height: 22),
              const SectionLabel(Icons.menu_book_outlined, 'Предмет'),
              _grid(
                Subject.values
                    .map((s) => OptionCard(
                          glyph: s.icon,
                          title: s.nameIn(_language),
                          selected: _subject == s,
                          onTap: () => setState(() => _subject = s),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 22),
              const SectionLabel(Icons.translate_outlined, 'Тил'),
              _grid(
                Language.values
                    .map((l) => OptionCard(
                          glyph: l.code,
                          title: l.label,
                          selected: _language == l,
                          color: AppTheme.secondary,
                          onTap: () => setState(() => _language = l),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 22),
              const SectionLabel(Icons.description_outlined, 'Барак саны'),
              _grid(
                PageCount.values
                    .map((p) => OptionCard(
                          glyph: '${p.value}',
                          title: p.label(_language),
                          selected: _pages == p,
                          color: AppTheme.accent,
                          onTap: () => setState(() => _pages = p),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 22),
              const SectionLabel(Icons.draw_outlined, 'Жазуу түрү'),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: w.clamp(220, 600),
                        child: _modeCard(
                          icon: Icons.text_fields,
                          title: '1 — Кадимки',
                          subtitle: 'Азыркыдай басма текст',
                          selected: _hand == null,
                          onTap: () => setState(() {
                            _hand = null;
                            _handProfile = null;
                            _handProfileName = null;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: w.clamp(220, 600),
                        child: _modeCard(
                          icon: Icons.draw_outlined,
                          title: '2 — Кол жазма',
                          subtitle: _hand == null
                              ? '5 даяр кол жазмадан тандоо'
                              : 'Тандалды: ${_hand == HandwritingStyle.mine ? (_handProfileName ?? _hand!.label) : _hand!.label} (өзгөртүү)',
                          selected: _hand != null,
                          onTap: _chooseHandwriting,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const SectionLabel(Icons.edit_outlined, 'Тема'),
              TextField(
                controller: _topic,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Мисалы: Омдун мыйзамы, Конденсатор, Матрицалар...',
                  prefixIcon: Icon(Icons.lightbulb_outline),
                ),
              ),
              const SizedBox(height: 18),
              _diagramSwitch(),
              const SizedBox(height: 14),
              _docTile(),
              const SizedBox(height: 26),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? 'Жасалып жатат...' : 'СРС Жасоо'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = children.length <= 3 ? children.length : 4;
        final width =
            (c.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: width.clamp(120, 400), child: child),
          ],
        );
      },
    );
  }

  Widget _hero() {
    final name =
        _author.student.isEmpty ? 'студент' : _author.student.split(' ').first;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.shadow(y: 10, blur: 26, a: 0.18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Салам, $name 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Теманы жазыңыз — формулалары, схемалары жана адабияттары '
                  'менен даяр СРС PDF жана Word форматында чыгат.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13.5, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.school_outlined,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _diagramSwitch() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, color: AppTheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'График жана схемаларды кошуу',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _subject.diagramHint,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _withDiagrams,
            onChanged: (v) => setState(() => _withDiagrams = v),
          ),
        ],
      ),
    );
  }

  String _selectionInfo() {
    final items = _docItems ?? const <DocItem>[];
    final sel = items.where((e) => e.selected).length;
    if (sel == 0) {
      return 'Эч нерсе тандалган жок — "Тандоо" баскычын басыңыз';
    }
    final chars = _docText?.length ?? 0;
    return 'Тандалды: $sel / ${items.length} бөлүк ($chars символ) — '
        'СРС ушулар боюнча толукталат';
  }

  Widget _docTile() {
    if (_docItems == null) {
      return InkWell(
        onTap: _readingDoc ? null : _pickDocument,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.attach_file_outlined, color: AppTheme.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _readingDoc
                      ? 'Документ окулуп жатат...'
                      : 'Кошумча документ жүктөө (PDF, Word, PowerPoint, Excel, TXT...) — милдеттүү эмес',
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.muted),
                ),
              ),
              if (_readingDoc)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_docName ?? 'Документ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  _selectionInfo(),
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _editSelection,
            icon: const Icon(Icons.checklist, size: 18),
            label: const Text('Тандоо'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 19),
            onPressed: () => setState(() {
              _docItems = null;
              _docName = null;
            }),
          ),
        ],
      ),
    );
  }
}
