import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/srs_config.dart';
import 'kyrgyz_grammar.dart';

/// Groq API (OpenAI-ге шайкеш) аркылуу текст жаратат.
class AiService {
  String _activeKey = '';

  static const String _base = 'https://api.groq.com/openai/v1';

  /// Groq моделдерди мезгил-мезгили менен өчүрүп турат, ошондуктан модель
  /// катуу жазылбай, /models тизмесинен тандалат.
  static const List<String> _preferredModels = <String>[
    'openai/gpt-oss-120b',
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-20b',
    'llama-3.1-8b-instant',
  ];

  String? _resolvedModel;
  final Set<String> _deadModels = <String>{};

  /// Ойлонуу параметрлерин кабыл албаган моделдер (400 кайтарса).
  final Set<String> _noReasoningParams = <String>{};

  String? get activeModel => _resolvedModel;

  void init(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed != _activeKey) {
      _resolvedModel = null;
      _deadModels.clear();
    }
    _activeKey = trimmed;
  }

  bool get hasKey => _activeKey.isNotEmpty;

  bool _isChatModel(String id) {
    final lower = id.toLowerCase();
    const skip = ['whisper', 'tts', 'guard', 'orpheus', 'embed', 'rerank'];
    return !skip.any(lower.contains);
  }

  Future<String> _resolveModel() async {
    final cached = _resolvedModel;
    if (cached != null) return cached;

    try {
      final r = await http.get(
        Uri.parse('$_base/models'),
        headers: {'Authorization': 'Bearer $_activeKey'},
      ).timeout(const Duration(seconds: 20));

      if (r.statusCode == 200) {
        final data = jsonDecode(utf8.decode(r.bodyBytes));
        final ids = <String>{
          for (final m in (data['data'] as List? ?? const []))
            if (m is Map && m['id'] != null) m['id'].toString(),
        }..removeWhere(_deadModels.contains);

        for (final want in _preferredModels) {
          if (ids.contains(want)) return _resolvedModel = want;
        }
        final any = ids.where(_isChatModel).toList()..sort();
        if (any.isNotEmpty) return _resolvedModel = any.first;
      }
    } catch (_) {
      // тизме алынбаса демейки менен аракет кылабыз
    }

    return _resolvedModel = _preferredModels.firstWhere(
      (m) => !_deadModels.contains(m),
      orElse: () => _preferredModels.first,
    );
  }

  /// «Ойлонуучу» моделдер (gpt-oss, qwen) токендерди адегенде ички ойлорго
  /// жумшайт; лимит жетпей калса, жооп БОШ келет. Ойлонууну азайтып, аны
  /// жоопко кошпоо үчүн параметрлер (Groq документациясы боюнча).
  Map<String, dynamic> _reasoningParams(String model) {
    if (_noReasoningParams.contains(model)) return const {};
    final m = model.toLowerCase();
    if (m.startsWith('openai/gpt-oss')) {
      return {'reasoning_effort': 'low', 'include_reasoning': false};
    }
    if (m.startsWith('qwen/qwen3')) {
      return {'reasoning_effort': 'none', 'reasoning_format': 'hidden'};
    }
    return const {};
  }

  Future<http.Response> _post(String model, String prompt, int maxTokens,
      {double temperature = 0.75, String? system}) {
    return http
        .post(
          Uri.parse('$_base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_activeKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              if (system != null) {'role': 'system', 'content': system},
              {'role': 'user', 'content': prompt}
            ],
            'temperature': temperature,
            'max_tokens': maxTokens,
            ..._reasoningParams(model),
          }),
        )
        .timeout(const Duration(seconds: 120));
  }

  Duration _retryAfter(http.Response r) {
    final fromHeader = double.tryParse(r.headers['retry-after'] ?? '');
    if (fromHeader != null && fromHeader > 0) {
      return Duration(
          milliseconds: (fromHeader * 1000).round().clamp(1000, 60000));
    }
    final m = RegExp(r'try again in ([\d.]+)\s*s').firstMatch(r.body);
    final secs = double.tryParse(m?.group(1) ?? '');
    if (secs != null) {
      return Duration(
          milliseconds: ((secs + 1) * 1000).round().clamp(1000, 60000));
    }
    return const Duration(seconds: 12);
  }

  /// Бекер тарифте мүнөтүнө 8000 токен чеги бар — 413/429 келсе
  /// автоматтык кичирейтип жана күтүп кайталайт.
  Future<String> _call(String prompt,
          {int maxTokens = 2000, String? system}) async =>
      (await _request(prompt, maxTokens: maxTokens, system: system)).text;

  /// Жооп жана ал токендин чегинен улам үзүлүп калдыбы.
  Future<({String text, bool truncated})> _request(String prompt,
      {int maxTokens = 2000, double temperature = 0.75, String? system}) async {
    if (_activeKey.isEmpty) {
      throw Exception(
          'API ачкыч киргизилген жок. Жөндөөлөрдөн Groq ачкычты коюңуз.');
    }

    var model = await _resolveModel();
    var tokens = maxTokens.clamp(400, 6000);
    Object? lastError;

    for (var attempt = 0; attempt < 5; attempt++) {
      http.Response response;
      try {
        response = await _post(model, prompt, tokens,
            temperature: temperature, system: system);
      } on TimeoutException {
        throw Exception(
            'Жооп 120 секунддан ашты. Интернет байланышын текшериңиз.');
      } catch (e) {
        throw Exception('Сурам жиберилбей калды: $e');
      }

      switch (response.statusCode) {
        case 200:
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) {
            throw Exception('Groq жооп кайтарган жок: $data');
          }
          final content = choices[0]['message']?['content'] as String?;
          final reason = choices[0]['finish_reason']?.toString();
          if (content == null || content.trim().isEmpty) {
            // Көбүнчө модель бардык токенди ойлонууга жумшап коёт —
            // лимитти чоңойтуп кайра суранабыз.
            lastError = 'Бош жооп (finish_reason: $reason)';
            if (attempt < 4) {
              tokens = (tokens * 1.8).round().clamp(400, 6000);
              await Future<void>.delayed(const Duration(seconds: 2));
              continue;
            }
            throw Exception('Groq бош жооп кайтарды ($reason). Бир аздан '
                'кийин кайра аракет кылыңыз же Жөндөөлөрдөн башка модель '
                'тандаңыз.');
          }
          return (text: content, truncated: reason == 'length');

        case 401:
          throw Exception('Groq ачкычы туура эмес (401). '
              'console.groq.com/keys дан жаңы ачкыч алыңыз.');

        case 404:
          if (!response.body.contains('model_not_found')) {
            throw Exception('Groq API катасы (404): ${response.body}');
          }
          _deadModels.add(model);
          _resolvedModel = null;
          final next = await _resolveModel();
          if (next == model) {
            throw Exception('Жарактуу модель табылган жок: ${response.body}');
          }
          model = next;
          continue;

        case 413:
          lastError = response.body;
          if (tokens <= 600) {
            throw Exception('Суроо өтө чоң: бекер тарифте мүнөтүнө 8000 '
                'токен чеги бар. Барак санын азайтып көрүңүз.');
          }
          tokens = (tokens * 0.55).round().clamp(600, 6000);
          continue;

        case 429:
          lastError = response.body;
          if (attempt >= 3) {
            throw Exception('Лимит бүттү (429). Бир-эки мүнөттөн кийин '
                'кайра аракет кылыңыз.\n${response.body}');
          }
          await Future<void>.delayed(_retryAfter(response));
          continue;

        case 400:
          final body = response.body.toLowerCase();
          if (!_noReasoningParams.contains(model) &&
              _reasoningParams(model).isNotEmpty &&
              (body.contains('reasoning') ||
                  body.contains('include_reasoning'))) {
            _noReasoningParams.add(model);
            continue;
          }
          throw Exception('Groq API катасы (HTTP 400): ${response.body}');

        default:
          throw Exception(
              'Groq API катасы (HTTP ${response.statusCode}): ${response.body}');
      }
    }

    throw Exception('Groq жооп бербеди. Акыркы ката: $lastError');
  }

  // ------------------------------------------------------------- промптор
  /// Кыргызча жазганда моделге берилүүчү системалык эскертүү (грамматика).
  String? _system(SrsConfig c) => c.language == Language.kyrgyz
      ? 'Сен кыргыз тилинде сабаттуу, академиялык стилде жазган '
          'окумуштуусуң. Кыргыз тилинин грамматикасын так сакта.\n'
          '${KyrgyzGrammar.rules}'
      : null;

  String _langLine(SrsConfig c) {
    switch (c.language) {
      case Language.kyrgyz:
        return 'Жоопту ТОЛУГУ МЕНЕН кыргыз тилинде жаз.';
      case Language.russian:
        return 'Пиши ПОЛНОСТЬЮ на русском языке.';
      case Language.english:
        return 'Write the answer ENTIRELY in English.';
    }
  }

  String _diagramRules(SrsConfig c) {
    if (!c.withDiagrams) return '';

    final wantChart = c.subject.needsChart;
    final wantCircuit = c.subject.needsCircuits;
    final wantBlock = c.subject.needsBlockDiagram;
    if (!wantChart && !wantCircuit && !wantBlock) return '';

    final buf = StringBuffer();
    buf.writeln('\nСҮРӨТ/СХЕМА (МИЛДЕТТҮҮ):');
    buf.writeln('Бөлүмгө ылайык келсе, 1-2 сүрөттү төмөнкү JSON блок түрүндө '
        'кош. JSON\'ду так ушул форматта жаз, башка текст кошпо.');

    if (wantChart) {
      buf.writeln('''
График үчүн:
```chart
{"title":"Аталышы","type":"line","x":"X огунун белгиси","y":"Y огунун белгиси","caption":"1-сүрөт. Түшүндүрмө","series":[{"name":"Сызыктын аты","points":[[0,0],[1,2],[2,4],[3,6]]}]}
```
"type": "line", "bar" же "scatter". points — реалдуу сандар, 5-12 чекит.''');
    }
    if (wantCircuit) {
      buf.writeln('''
Электр схемасы үчүн:
```circuit
{"title":"Аталышы","layout":"series","source":"U = 12 В","caption":"2-сүрөт. Түшүндүрмө","elements":[{"kind":"R","label":"R1 = 10 Ом"},{"kind":"C","label":"C1 = 100 мкФ"}]}
```
"layout": "series" же "parallel". kind: R, C, L, D, S, M.''');
    }
    if (wantBlock) {
      buf.writeln('''
Блок-схема үчүн:
```block
{"title":"Аталышы","caption":"3-сүрөт. Алгоритм","nodes":["Башталышы","Маалымат киргизүү","Шарт аткарылдыбы?","Натыйжаны чыгаруу","Аягы"],"shapes":["start","process","decision","process","end"]}
```
shapes: start, process, decision, end.''');
    }
    buf.writeln('Сүрөттөрдүн caption талаасын сөзсүз толтур.');
    return buf.toString();
  }

  String _formulaRules(SrsConfig c) {
    return '''
ФОРМУЛАЛАР: LaTeX форматта жаз. Өзүнчө сапта турган формуланы \$\$ ... \$\$
ичине ал, сап ичиндегини \$ ... \$ ичине ал. Мисалы: \$\$I = \\frac{U}{R}\$\$
''';
  }

  // ------------------------------------------- жүктөлгөн документ контексти
  /// Бөлүмдөрдүн тизмеси үчүн: документтин башталышы (негизги мазмуну).
  String _docForOutline(SrsConfig config) {
    final t = config.documentText;
    if (t == null || t.trim().isEmpty) return '';
    final clip = t.length > 6000 ? t.substring(0, 6000) : t;
    return '\nСтудент кошумча документ жүктөдү. Бөлүмдөрдүн аталышын ушул '
        'документтин мазмунуна дал келтирип, анын негизги темаларын камтып жаз:\n'
        '<<<\n$clip\n>>>';
  }

  /// Бөлүм үчүн: документти бөлүмдөргө бөлүп, тийиштүү бөлүгүн беребиз.
  String _docForSection(SrsConfig config, int index, int total) {
    final t = config.documentText;
    if (t == null || t.trim().isEmpty) return '';
    const maxSlice = 3500;
    String slice;
    if (t.length <= maxSlice) {
      slice = t;
    } else {
      final chunk = t.length ~/ total;
      final start = (index * chunk).clamp(0, t.length);
      final end = (start + maxSlice).clamp(0, t.length);
      slice = t.substring(start, end);
    }
    return '\nСтудент жүктөгөн документтен үзүндү (маалыматтарды, терминдерди, '
        'сандарды жана мисалдарды ушундан пайдаланып бөлүмдү толуктап жаз, '
        'бирок сөзмө-сөз көчүрбө; документте жок нерсени да теманын '
        'алкагында кошсоң болот):\n<<<\n$slice\n>>>';
  }

  // ----------------------------------------------------------- генерация
  Future<List<String>> generateSections(SrsConfig config) async {
    final pages = config.pageCount.value;
    final count = pages <= 5
        ? 4
        : pages <= 10
            ? 6
            : pages <= 15
                ? 8
                : 10;

    final doc = _docForOutline(config);

    final prompt = '''
"${config.topic}" темасы боюнча ${config.subjectName} предметинен СРС үчүн
$count бөлүмдүн аталышын жаз.
${_langLine(config)}
$doc
Биринчи бөлүм — киришүү, акыркы бөлүм — корутунду болсун.
Жөн гана номерленген тизме бер, башка эч нерсе жазба.
''';

    final text =
        await _call(prompt, maxTokens: 1200, system: _system(config));

    final numbered = RegExp(r'^\s*(?:\d+[.)]|[-*•])\s*(.+)$');
    final titles = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = numbered.firstMatch(line);
      if (m == null) continue;
      final title = m.group(1)!.replaceAll('**', '').replaceAll('#', '').trim();
      if (title.isEmpty) continue;
      titles.add(title);
      if (titles.length == count) break;
    }

    if (titles.isEmpty) {
      return text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(count)
          .toList();
    }
    return titles;
  }

  Future<String> generateSection(
    SrsConfig config,
    String sectionTitle,
    int index,
    int total,
  ) async {
    final words = (config.pageCount.value * 350) ~/ total;
    final doc = _docForSection(config, index, total);

    final prompt = '''
${config.subjectName} предметинен "${config.topic}" темасындагы СРСтин
"$sectionTitle" бөлүмүн жаз.
${_langLine(config)}
Болжол менен $words сөз. Академиялык, илимий стилде.
$doc
${_formulaRules(config)}
Керек болсо markdown таблица колдон (| бага | бага |).
${_diagramRules(config)}

Бөлүмдүн аталышын кайра жазба, дароо мазмундан башта.
''';

    final first = await _request(prompt,
        maxTokens: (words * 2.6).round().clamp(700, 3200),
        temperature: 0.6,
        system: _system(config));
    if (!first.truncated) return first.text;

    // Токен чегинен улам үзүлүп калса — улантып бүтүрөбүз.
    final tail = first.text.length > 400
        ? first.text.substring(first.text.length - 400)
        : first.text;
    try {
      final rest = await _request('''
$prompt

Мурда жазылганы (акыркы бөлүгү):
...$tail

Ушул жерден УЛАНТЫП, бөлүмдү аягына чыгар. Жазылганды кайталаба,
баш сөз жазба, дароо улант.
''', maxTokens: 1400, temperature: 0.6, system: _system(config));
      return '${first.text}\n${rest.text}';
    } catch (_) {
      return first.text;
    }
  }

  /// ГОСТ форматындагы адабияттар тизмеси.
  Future<String> generateReferences(SrsConfig config) async {
    final prompt = '''
"${config.topic}" темасы (${config.subjectName}) боюнча 5-7 реалдуу
илимий булакты ГОСТ 7.1 форматында тизмеле.
${_langLine(config)}

Формат так мындай болсун:
1. Автордун аты-жөнү. Китептин аталышы. – Шаар: Басмакана, Жыл. – 000 б.
2. Автор А.А. Макаланын аталышы // Журналдын аты. – 2020. – № 3. – Б. 12–18.

Жөн гана номерленген тизме бер, баш сөз жазба.
''';
    return _call(prompt, maxTokens: 900);
  }

  /// Бөлүмдөр табылбай калса — бүтүндөй СРСти бир жолу жазуу.
  Future<String> generateWhole(SrsConfig config) async {
    final pages = config.pageCount.value;
    final prompt = '''
${config.subjectName} предметинен "${config.topic}" темасында толук СРС жаз.
${_langLine(config)}
Болжол менен ${pages * 350} сөз.
Структура: Киришүү, Негизги бөлүм, Эсептөөлөр, Корутунду, Адабияттар.
${_formulaRules(config)}
${_diagramRules(config)}
''';
    return _call(prompt,
        maxTokens: (pages * 350 * 2).clamp(1200, 5000),
        system: _system(config));
  }

  // ------------------------------------------- кыргыз грамматика плагини
  /// Текстти кыргыз грамматикасы боюнча текшерип оңдойт: адегенде так
  /// эрежелер, анан AI редактор (керек болсо 2 жолу). Формулалар жана
  /// схемалар корголот. AI жообу ишенимсиз болсо, мурунку текст калат —
  /// ошондуктан текшерүү эч качан текстти бузбайт.
  Future<GrammarReport> proofreadKyrgyz(String text,
      {void Function(String status)? onStatus}) async {
    if (text.trim().isEmpty) return GrammarReport(text, 0, 0, const []);
    final prot = KyrgyzGrammar.protect(text);
    final saved = prot.$2;
    final fixed = KyrgyzGrammar.autoFix(prot.$1);
    var masked = fixed.$1;
    var autoFixes = fixed.$2;
    var rounds = 0;

    for (var round = 0; round < 2; round++) {
      final hints = KyrgyzGrammar.findIssues(masked);
      // Экинчи айлампа шектүү жер калса гана жасалат
      if (round > 0 && hints.isEmpty) break;
      onStatus?.call(round == 0
          ? 'Кыргыз грамматикасы текшерилүүдө...'
          : 'Калган каталар кайра текшерилүүдө...');
      ({String text, bool truncated}) r;
      try {
        r = await _request(
          KyrgyzGrammar.proofreadPrompt(masked, hints),
          maxTokens: (masked.length / 1.6).round().clamp(800, 6000),
          temperature: 0.15,
        );
      } catch (_) {
        break; // текшерүү болбосо да, СРС токтобойт
      }
      if (r.truncated) break;
      final out = KyrgyzGrammar.cleanResponse(r.text);
      if (KyrgyzGrammar.restore(out, saved) == null) break;
      if (!KyrgyzGrammar.plausible(masked, out)) break;
      final again = KyrgyzGrammar.autoFix(out);
      masked = again.$1;
      autoFixes += again.$2;
      rounds++;
    }

    final restored = KyrgyzGrammar.restore(masked, saved) ?? text;
    return GrammarReport(
        restored, autoFixes, rounds, KyrgyzGrammar.findIssues(masked));
  }

  /// Бөлүмдөрдүн аталыштарын текшерет (саны дал келбесе — өзгөртпөйт).
  Future<List<String>> proofreadTitles(List<String> titles) async {
    if (titles.isEmpty) return titles;
    final joined = [
      for (var i = 0; i < titles.length; i++) '${i + 1}. ${titles[i]}'
    ].join('\n');
    final rep = await proofreadKyrgyz(joined);
    final numbered = RegExp(r'^\s*\d+[.)]\s*(.+)$');
    final out = <String>[];
    for (final line in rep.text.split('\n')) {
      final m = numbered.firstMatch(line.trim());
      if (m != null) out.add(m.group(1)!.trim());
    }
    return out.length == titles.length ? out : titles;
  }
}
