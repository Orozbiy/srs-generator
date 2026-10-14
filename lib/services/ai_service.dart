import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/srs_config.dart';
import 'grammar.dart';
import 'page_fitter.dart';
import 'text_sanitizer.dart';

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

  /// Кайталоого каршы параметрлерди кабыл албаган моделдер.
  final Set<String> _noPenalty = <String>{};

  Future<http.Response> _post(String model, String prompt, int maxTokens,
      {double temperature = 0.75,
      String? system,
      String? continueFrom,
      double penalty = 0}) {
    final usePenalty = penalty > 0 && !_noPenalty.contains(model);
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
              {'role': 'user', 'content': prompt},
              // Улантуу: мурда жазылган текст ассистенттин жообу катары
              // берилет, ошондо модель аны башынан жазбай, уланта берет.
              if (continueFrom != null)
                {'role': 'assistant', 'content': continueFrom},
            ],
            'temperature': temperature,
            'max_tokens': maxTokens,
            // Бир сөздү жүз жолу кайталап жазып кетпеши үчүн.
            if (usePenalty) 'frequency_penalty': penalty,
            if (usePenalty) 'presence_penalty': 0.2,
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
  /// [continueFrom] берилсе — мурда жазылган тексттин уландысы суралат.
  Future<({String text, bool truncated})> _request(String prompt,
      {int maxTokens = 2000,
      double temperature = 0.75,
      String? system,
      String? continueFrom,
      double penalty = 0}) async {
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
            temperature: temperature,
            system: system,
            continueFrom: continueFrom,
            penalty: penalty);
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
          if (penalty > 0 &&
              !_noPenalty.contains(model) &&
              body.contains('penalty')) {
            _noPenalty.add(model);
            continue;
          }
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
  /// Моделге берилүүчү системалык эскертүү: тандалган тилдин грамматикасы
  /// (кыргызча, орусча жана англисче үчүн өзүнчө эрежелер).
  String? _system(SrsConfig c) => LanguageGrammar.of(c.language).system;

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
    buf.writeln('\nСҮРӨТ/СХЕМА:');
    buf.writeln('Бул бөлүмгө ылайык келсе, ЭҢ КӨП БИР сүрөт кош (керек '
        'болбосо такыр кошпо). Сүрөттү төмөнкү JSON блок түрүндө жаз.');
    buf.writeln('JSONду МИЛДЕТТҮҮ ТҮРДӨ БИР САПКА жаз жана сөзсүз жап '
        '(үзүлүп калса сүрөт жоголот). Бир эле маалыматты эки жолу '
        'сүрөткө салба.');
    buf.writeln('caption ичине "1-сүрөт" деген номерди жазба — номер '
        'автоматтык коюлат, сен түшүндүрмөнү гана жаз.');

    if (wantChart) {
      buf.writeln('''
График үчүн:
```chart
{"title":"Аталышы","type":"line","x":"X огунун белгиси","y":"Y огунун белгиси","caption":"Түшүндүрмө","series":[{"name":"Сызыктын аты","points":[[2018,3.2],[2019,3.5],[2020,3.9]]}]}
```
"type": "line", "bar" же "scatter". points — реалдуу сандар, 5-12 чекит.
x мааниси жыл болсо жылды өзүн жаз (2018, 2019 ...).''');
    }
    if (wantCircuit) {
      buf.writeln('''
Электр схемасы үчүн:
```circuit
{"title":"Аталышы","layout":"series","source":"U = 12 В","caption":"Түшүндүрмө","elements":[{"kind":"R","label":"R1 = 10 Ом"},{"kind":"C","label":"C1 = 100 мкФ"}]}
```
"layout": "series" же "parallel". kind: R, C, L, D, S, M.''');
    }
    if (wantBlock) {
      buf.writeln('''
Блок-схема үчүн:
```block
{"title":"Аталышы","caption":"Алгоритм","nodes":["Башталышы","Маалымат киргизүү","Шарт аткарылдыбы?","Натыйжаны чыгаруу","Аягы"],"shapes":["start","process","decision","process","end"]}
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

  /// Бир бөлүмгө тийиштүү сөз саны. Барак саны, жазуунун өлчөмү (кол жазма
  /// тамгалары басма тамгадан эки эсе чоң) эсепке алынат.
  int sectionWords(SrsConfig config, int total) {
    final all = PageFitter.totalWords(config);
    // 10% ашыгыраак суралат — кийин артыкчасы кыскартылат, кем болсо
    // толуктай албайбыз.
    return (all * 1.1 / (total < 1 ? 1 : total)).round().clamp(90, 900);
  }

  Future<String> generateSection(
    SrsConfig config,
    String sectionTitle,
    int index,
    int total, {
    void Function(String status)? onStatus,
  }) async {
    final words = sectionWords(config, total);
    final doc = _docForSection(config, index, total);

    final prompt = '''
${config.subjectName} предметинен "${config.topic}" темасындагы СРСтин
"$sectionTitle" бөлүмүн жаз.
${_langLine(config)}
КӨЛӨМҮ: $words сөз (±15%). Мындан ашык жазба — ашыгы кесилип ташталат.
Академиялык, илимий стилде, кайталоосуз.
$doc
${_formulaRules(config)}
Керек болсо markdown таблица колдон (| бага | бага |).
${_diagramRules(config)}

Бөлүмдүн аталышын кайра жазба, дароо мазмундан башта.
Бир эле ойду же сөздү кайра-кайра жазба.
''';

    final tokens = (words * 2.8).round().clamp(700, 3200);
    var first = await _request(prompt,
        maxTokens: tokens,
        temperature: 0.6,
        penalty: 0.35,
        system: _system(config));

    // КАЙТАЛООНУ ТЕКШЕРҮҮ: модель бир сөздү же сөз айкашын кайра-кайра
    // жазып таштаса, тазалап коюу аз — бөлүмдү кайра жаздырабыз.
    if (TextSanitizer.hasLoop(first.text)) {
      onStatus?.call('Кайталоо табылды — бөлүм кайра жазылууда...');
      try {
        final retry = await _request(prompt,
            maxTokens: tokens,
            temperature: 0.45,
            penalty: 0.6,
            system: _system(config));
        // Кайсынысы таза болсо, ошону алабыз.
        if (TextSanitizer.loopWords(retry.text) <
            TextSanitizer.loopWords(first.text)) {
          first = retry;
        }
      } catch (_) {
        // кайра жазылбаса да, тазаланган нускасы калат
      }
    }

    var text = TextSanitizer.deloop(first.text);
    var truncated = first.truncated;

    // Токен чегинен улам үзүлүп калса — улантып бүтүрөбүз (эң көп 2 жолу).
    for (var i = 0; i < 2 && truncated; i++) {
      try {
        final tail = text.length > 1500
            ? text.substring(text.length - 1500)
            : text;
        final rest = await _request(prompt,
            maxTokens: 900,
            temperature: 0.6,
            penalty: 0.4,
            system: _system(config),
            continueFrom: tail);
        final add = TextSanitizer.deloop(rest.text).trim();
        // Модель уланткандын ордуна башынан жаза баштаса — токтотобуз.
        if (add.isEmpty || TextSanitizer.repeatsStart(text, add)) break;
        text = '${text.trimRight()} $add';
        truncated = rest.truncated;
      } catch (_) {
        break;
      }
    }

    return TextSanitizer.section(text, sectionTitle);
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
    final words = PageFitter.totalWords(config);
    final prompt = '''
${config.subjectName} предметинен "${config.topic}" темасында толук СРС жаз.
${_langLine(config)}
КӨЛӨМҮ: $words сөз (±15%). Мындан ашык жазба.
Структура: Киришүү, Негизги бөлүм, Эсептөөлөр, Корутунду, Адабияттар.
${_formulaRules(config)}
${_diagramRules(config)}
''';
    final r = await _request(prompt,
        maxTokens: (words * 2.8).round().clamp(1200, 5000),
        penalty: 0.35,
        system: _system(config));
    return TextSanitizer.document(r.text);
  }

  // ----------------------------------------------- грамматика плагини
  /// Текстти тандалган тилдин грамматикасы боюнча текшерип оңдойт:
  /// адегенде так эрежелер, анан AI редактор (керек болсо 2 жолу).
  /// Кыргызча, орусча жана англисче үчүн өз эрежелери колдонулат.
  /// Формулалар жана схемалар корголот. AI жообу ишенимсиз болсо,
  /// мурунку текст калат — ошондуктан текшерүү эч качан текстти бузбайт.
  Future<GrammarReport> proofread(String text, Language language,
      {void Function(String status)? onStatus}) async {
    if (text.trim().isEmpty) return GrammarReport(text, 0, 0, const []);
    final g = LanguageGrammar.of(language);
    final prot = GrammarText.protect(text);
    final saved = prot.$2;
    final fixed = g.autoFix(prot.$1);
    var masked = fixed.$1;
    var autoFixes = fixed.$2;
    var rounds = 0;

    for (var round = 0; round < 2; round++) {
      final hints = g.findIssues(masked);
      // Экинчи айлампа шектүү жер калса гана жасалат
      if (round > 0 && hints.isEmpty) break;
      onStatus?.call(round == 0
          ? g.statusChecking
          : 'Калган каталар кайра текшерилүүдө...');
      ({String text, bool truncated}) r;
      try {
        r = await _request(
          g.proofreadPrompt(masked, hints),
          maxTokens: (masked.length / 1.6).round().clamp(800, 6000),
          temperature: 0.15,
        );
      } catch (_) {
        break; // текшерүү болбосо да, СРС токтобойт
      }
      if (r.truncated) break;
      final out = GrammarText.cleanResponse(r.text);
      if (GrammarText.restore(out, saved) == null) break;
      if (!GrammarText.plausible(masked, out)) break;
      // Редактор да циклге түшүп калышы мүмкүн — текшерип алабыз.
      if (TextSanitizer.loopWords(out) > 0) break;
      final again = g.autoFix(out);
      masked = again.$1;
      autoFixes += again.$2;
      rounds++;
    }

    final restored = GrammarText.restore(masked, saved) ?? text;
    return GrammarReport(restored, autoFixes, rounds, g.findIssues(masked));
  }

  /// Бөлүмдөрдүн аталыштарын текшерет (саны дал келбесе — өзгөртпөйт).
  Future<List<String>> proofreadTitles(
      List<String> titles, Language language) async {
    if (titles.isEmpty) return titles;
    final joined = [
      for (var i = 0; i < titles.length; i++) '${i + 1}. ${titles[i]}'
    ].join('\n');
    final rep = await proofread(joined, language);
    final numbered = RegExp(r'^\s*\d+[.)]\s*(.+)$');
    final out = <String>[];
    for (final line in rep.text.split('\n')) {
      final m = numbered.firstMatch(line.trim());
      if (m != null) out.add(m.group(1)!.trim());
    }
    return out.length == titles.length ? out : titles;
  }
}
