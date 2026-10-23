import 'package:flutter/material.dart';

import '../models/srs_config.dart';
import '../services/ai_service.dart';
import '../services/grammar.dart';
import '../services/markdown_parser.dart';
import '../services/page_fitter.dart';
import '../services/text_sanitizer.dart';
import '../theme/app_theme.dart';

/// Генерациянын жүрүшүн көрсөткөн диалог. Натыйжада markdown текст кайтарат.
class GenerationDialog extends StatefulWidget {
  final SrsConfig config;
  final AiService ai;

  const GenerationDialog({super.key, required this.config, required this.ai});

  @override
  State<GenerationDialog> createState() => _GenerationDialogState();
}

class _GenerationDialogState extends State<GenerationDialog> {
  String _status = 'Серверге байланышуу...';
  double _progress = 0;
  final StringBuffer _content = StringBuffer();
  bool _done = false;
  bool _error = false;
  bool _cancelled = false;
  List<String> _sections = [];
  int _current = 0;

  /// Грамматика плагини: кыргызча, орусча жана англисче үчүн иштейт.
  LanguageGrammar get _grammar => LanguageGrammar.of(widget.config.language);
  bool get _checkGrammar => true;
  int _grammarFixes = 0;
  int _grammarRounds = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _set(VoidCallback fn) {
    if (!mounted) {
      fn();
      return;
    }
    setState(fn);
  }

  /// Кайсы бөлүмдөргө сүрөт чийилет: киришүү/корутундудан башка, барак
  /// санына жараша бирдей аралыкта (документ жүктөлсө — бирөө көп).
  Set<int> _pickFigureSections(int total) {
    final cfg = widget.config;
    if (!cfg.withDiagrams || total == 0) return {};
    final cands = <int>[
      for (var i = 0; i < total; i++)
        if (total <= 2 || (i > 0 && i < total - 1)) i
    ];
    if (cands.isEmpty) return {};
    var want = (cfg.pageCount.value / 3).round().clamp(2, 6);
    if ((cfg.documentText ?? '').trim().isNotEmpty) want += 1;
    want = want.clamp(1, cands.length);
    return {
      for (var k = 0; k < want; k++) cands[(k * cands.length / want).floor()]
    };
  }

  String _refsTitle(Language l) {
    switch (l) {
      case Language.kyrgyz:
        return 'Колдонулган адабияттар';
      case Language.russian:
        return 'Список литературы';
      case Language.english:
        return 'References';
    }
  }

  Future<void> _start() async {
    try {
      _set(() {
        _status = 'Мазмундун планы түзүлүп жатат...';
        _progress = 0.04;
      });

      _sections = await widget.ai.generateSections(widget.config);
      if (!mounted || _cancelled) return;
      if (_checkGrammar && _sections.isNotEmpty) {
        _set(() => _status = 'Бөлүмдөрдүн аталыштары текшерилүүдө...');
        _sections = await widget.ai
            .proofreadTitles(_sections, widget.config.language);
        if (!mounted || _cancelled) return;
      }

      if (_sections.isEmpty) {
        _set(() {
          _status = 'СРС жазылып жатат...';
          _progress = 0.2;
        });
        var text = await widget.ai.generateWhole(widget.config);
        if (!mounted || _cancelled) return;
        if (_checkGrammar) {
          _set(() {
            _status = _grammar.statusChecking;
            _progress = 0.7;
          });
          final rep =
              await widget.ai.proofread(text, widget.config.language);
          if (!mounted || _cancelled) return;
          text = rep.text;
          _grammarFixes += rep.autoFixes;
          _grammarRounds += rep.aiRounds;
        }
        _content.write(text);
      } else {
        final total = _sections.length;
        final figureAt = _pickFigureSections(total);
        for (var i = 0; i < total; i++) {
          if (_cancelled) return;
          final section = _sections[i];
          _set(() {
            _current = i;
            _status = section;
            _progress = 0.06 + (i / total) * 0.80;
          });

          var text = await widget.ai.generateSection(
            widget.config,
            section,
            i,
            total,
            onStatus: (st) => _set(() => _status = '$section\n$st'),
          );
          if (!mounted || _cancelled) return;

          // Грамматика плагини: шашылбай текшерип, оңдойт
          if (_checkGrammar) {
            _set(() {
              _status = '$section\n${_grammar.statusChecking}';
              _progress = 0.06 + ((i + 0.5) / total) * 0.80;
            });
            final rep = await widget.ai.proofread(
              text,
              widget.config.language,
              onStatus: (st) => _set(() => _status = '$section\n$st'),
            );
            if (!mounted || _cancelled) return;
            text = rep.text;
            _grammarFixes += rep.autoFixes;
            _grammarRounds += rep.aiRounds;
          }

          // Сүрөт: документке жана бөлүмдүн мазмунуна таянып чийилет
          if (figureAt.contains(i)) {
            _set(() {
              _status = '$section\nСүрөт чийилип жатат...';
              _progress = 0.06 + ((i + 0.8) / total) * 0.80;
            });
            try {
              text = await widget.ai
                  .addFigure(widget.config, section, text, i, total);
            } catch (_) {
              // сүрөт чийилбесе да, бөлүм текст менен калат
            }
            if (!mounted || _cancelled) return;
          }

          _content.writeln('\n## $section\n');
          _content.writeln(text);
        }

        _set(() {
          _status = 'Колдонулган адабияттар...';
          _progress = 0.9;
        });
        try {
          final refs = await widget.ai.generateReferences(widget.config);
          if (_cancelled) return;
          _content.writeln('\n## ${_refsTitle(widget.config.language)}\n');
          _content.writeln(refs);
        } catch (e) {
          // Адабияттар алынбаса да СРС даяр — бирок билинип турсун
          _content.writeln('\n## ${_refsTitle(widget.config.language)}\n');
          _content.writeln(
              '_(Тизме алынбай калды: $e — "Текстти текшерүү" экранынан '
              'кол менен кошсоңуз болот.)_');
        }
      }

      if (_cancelled) return;

      // Кайталанган сөздөрдү тазалап, суралган барак санына батырабыз.
      _set(() {
        _status = 'Текст тазаланып, барак санына ылайыкташтырылууда...';
        _progress = 0.96;
      });
      final cleaned = TextSanitizer.document(_content.toString());
      final fitted = PageFitter.fit(cleaned, widget.config);
      final pages = PageFitter.estimatePages(
        MarkdownParser.parse(fitted, lang: widget.config.language),
        widget.config,
      );

      if (_cancelled) return;
      _set(() {
        _status = _checkGrammar
            ? 'Даяр! Болжол менен $pages барак. ${_grammar.name} '
                'грамматикасын AI редактор $_grammarRounds жолу окуп чыкты, '
                '$_grammarFixes тамга/белги автоматтык оңдолду.'
            : 'Даяр! Болжол менен $pages барак.';
        _progress = 1;
        _done = true;
      });

      await Future<void>.delayed(
          Duration(milliseconds: _checkGrammar ? 1800 : 400));
      if (mounted && !_cancelled) Navigator.pop(context, fitted);
    } catch (e) {
      _set(() {
        _error = true;
        _status = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _error ? _errorView() : _progressView(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _progressView() {
    final total = _sections.isEmpty ? 1 : _sections.length;
    return [
      SizedBox(
        width: 62,
        height: 62,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                backgroundColor: AppTheme.line,
                color: _done ? AppTheme.success : AppTheme.primary,
              ),
            ),
            if (_done)
              const Icon(Icons.check_rounded,
                  color: AppTheme.success, size: 28)
            else
              Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Text(
        _done ? 'СРС даяр' : 'СРС жазылып жатат',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        _status,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.muted, fontSize: 13),
      ),
      if (_sections.isNotEmpty && !_done) ...[
        const SizedBox(height: 16),
        Text(
          '${_current + 1} / $total бөлүм',
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context, '');
          },
          child: const Text('Токтотуу'),
        ),
      ],
    ];
  }

  List<Widget> _errorView() {
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.priority_high_rounded,
            color: AppTheme.error, size: 30),
      ),
      const SizedBox(height: 18),
      const Text('Ката кетти',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: SelectableText(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
          ),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Жабуу'),
        ),
      ),
    ];
  }
}
