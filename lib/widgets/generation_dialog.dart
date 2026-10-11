import 'package:flutter/material.dart';

import '../models/srs_config.dart';
import '../services/ai_service.dart';
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

  /// Кыргыз грамматика плагини иштейби (кыргызча СРС үчүн гана).
  bool get _checkGrammar => widget.config.language == Language.kyrgyz;
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
        _sections = await widget.ai.proofreadTitles(_sections);
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
            _status = 'Кыргыз грамматикасы текшерилүүдө...';
            _progress = 0.7;
          });
          final rep = await widget.ai.proofreadKyrgyz(text);
          if (!mounted || _cancelled) return;
          text = rep.text;
          _grammarFixes += rep.autoFixes;
          _grammarRounds += rep.aiRounds;
        }
        _content.write(text);
      } else {
        final total = _sections.length;
        for (var i = 0; i < total; i++) {
          if (_cancelled) return;
          final section = _sections[i];
          _set(() {
            _current = i;
            _status = section;
            _progress = 0.06 + (i / total) * 0.80;
          });

          var text = await widget.ai
              .generateSection(widget.config, section, i, total);
          if (!mounted || _cancelled) return;

          // Кыргыз грамматика плагини: шашылбай текшерип, оңдойт
          if (_checkGrammar) {
            _set(() {
              _status = '$section\nГрамматика текшерилүүдө...';
              _progress = 0.06 + ((i + 0.5) / total) * 0.80;
            });
            final rep = await widget.ai.proofreadKyrgyz(
              text,
              onStatus: (st) => _set(() => _status = '$section\n$st'),
            );
            if (!mounted || _cancelled) return;
            text = rep.text;
            _grammarFixes += rep.autoFixes;
            _grammarRounds += rep.aiRounds;
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
          _content.writeln('\n## Колдонулган адабияттар\n');
          _content.writeln(refs);
        } catch (e) {
          // Адабияттар алынбаса да СРС даяр — бирок билинип турсун
          _content.writeln('\n## Колдонулган адабияттар\n');
          _content.writeln(
              '_(Тизме алынбай калды: \$e — "Текстти текшерүү" экранынан '
              'кол менен кошсоңуз болот.)_');
        }
      }

      if (_cancelled) return;
      _set(() {
        _status = _checkGrammar
            ? 'Даяр! Грамматика текшерилди: AI редактор $_grammarRounds жолу '
                'окуп чыкты, $_grammarFixes тамга/белги автоматтык оңдолду.'
            : 'Даяр!';
        _progress = 1;
        _done = true;
      });

      await Future<void>.delayed(
          Duration(milliseconds: _checkGrammar ? 1800 : 400));
      if (mounted && !_cancelled) Navigator.pop(context, _content.toString());
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
