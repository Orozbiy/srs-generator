/// AI кайтарган текстти тазалайт.
///
/// Тил модели кээде «циклге» түшүп калат: бир эле сөздү же сөз айкашын
/// жүздөгөн жолу кайталап жазат («бир кээ бир кээ бир кээ ...»), же токенинин
/// чеги жеткенде бөлүмдү башынан кайра жаза баштайт. Ушул класс ошондой
/// бузук жерлерди текст PDFке түшөөрдөн мурун алып салат.
class TextSanitizer {
  /// Кайталанган айкаштын эң узун өлчөмү (сөз менен).
  static const int _maxPattern = 8;

  /// Ушунчадан көп сөз кайталанса — бул жөн эле цикл, бир көчүрмөсү да
  /// калтырылбайт (мааниси жок таштанды).
  static const int _junkWords = 60;

  static bool _same(List<String> w, int a, int b, int n) {
    for (var k = 0; k < n; k++) {
      if (w[a + k] != w[b + k]) return false;
    }
    return true;
  }

  /// Сүрөттүн JSON блогу же таблицанын сабы — буларды тийбейбиз.
  static bool _structural(String t) =>
      t.startsWith('{') || t.startsWith('|') || t.contains('":');

  /// Бир саптагы циклди жыйнайт: «бир кээ бир кээ бир кээ» → «бир кээ».
  static String _deloopLine(String line) {
    final lead = RegExp(r'^[ \t]*').firstMatch(line)?.group(0) ?? '';
    final body = line.trim();
    if (body.isEmpty || _structural(body)) return line;

    final w = body.split(RegExp(r'\s+'));
    if (w.length < 6) return line;

    final out = <String>[];
    var i = 0;
    var changed = false;
    while (i < w.length) {
      var bestN = 0;
      var bestRep = 0;
      for (var n = 1; n <= _maxPattern && i + n * 2 <= w.length; n++) {
        var rep = 1;
        while (i + (rep + 1) * n <= w.length && _same(w, i, i + rep * n, n)) {
          rep++;
        }
        // Бир сөз 4 жолудан, айкаш 3 жолудан ашык катары менен
        // кайталанса — бул цикл.
        final looping = n == 1 ? rep >= 4 : rep >= 3;
        if (looping && n * rep > bestN * bestRep) {
          bestN = n;
          bestRep = rep;
        }
      }
      if (bestN > 0) {
        if (bestN * bestRep < _junkWords) {
          out.addAll(w.sublist(i, i + bestN)); // бир көчүрмөсүн калтырабыз
        }
        i += bestN * bestRep;
        changed = true;
      } else {
        out.add(w[i]);
        i++;
      }
    }
    if (!changed) return line;
    final joined = out.join(' ').trim();
    return joined.isEmpty ? '' : '$lead$joined';
  }

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\wа-яёөүңґ]', unicode: true), '')
      .trim();

  /// Катары менен кайталанган бирдей саптарды бирөөгө калтырат.
  static String _collapseLines(String text) {
    final out = <String>[];
    var prev = '';
    for (final line in text.split('\n')) {
      final t = line.trim();
      final k = _structural(t) ? '' : _key(line);
      if (k.isNotEmpty && k == prev) continue;
      prev = k;
      out.add(line);
    }
    return out.join('\n');
  }

  /// Сөз циклдерин жана кайталанган саптарды жоёт.
  static String deloop(String text) {
    if (text.isEmpty) return text;
    final lines = text.split('\n').map(_deloopLine).toList();
    return _collapseLines(lines.join('\n'));
  }

  /// Эки жолу жазылган абзацтарды алып салат (биринчиси калат).
  static String dropDuplicateParagraphs(String text) {
    final parts = text.split(RegExp(r'\n[ \t]*\n'));
    final seen = <String>{};
    final out = <String>[];
    for (final p in parts) {
      final k = _key(p);
      // Кыска саптар (аталыш, формула) кайталанышы мүмкүн — аларды тийбейбиз.
      if (k.length > 80 && !seen.add(k)) continue;
      out.add(p);
    }
    return out.join('\n\n');
  }

  /// Модель бөлүмдү башынан кайра жаза баштаса — ошол жерден кыябыз.
  static String dropRestart(String text, String title) {
    final key = _key(title);
    if (key.length < 8) return text;

    final lines = text.split('\n');
    final out = <String>[];
    var chars = 0;
    for (var i = 0; i < lines.length; i++) {
      final k = _key(lines[i]);
      if (k == key) {
        // Эң башында турса — жөн гана ашыкча аталыш, өткөрүп жиберебиз.
        if (chars < 120) continue;
        break; // ортосунда чыкса — модель кайра баштаган, калганы керексиз
      }
      out.add(lines[i]);
      chars += lines[i].length;
    }
    return out.join('\n');
  }

  /// Бир бөлүмдүн текстин толук тазалайт.
  static String section(String text, String title) => dropDoubledWords(
      dropDuplicateParagraphs(deloop(dropRestart(text, title)))).trim();

  /// Бүтүндөй СРСтин текстин тазалайт.
  static String document(String text) =>
      dropDoubledWords(dropDuplicateParagraphs(deloop(text))).trim();

  // ------------------------------------------------------- текшерүү
  static int _words(String t) =>
      t.trim().isEmpty ? 0 : t.trim().split(RegExp(r'\s+')).length;

  /// Текстте цикл барбы жана ага канча сөз кеткен.
  /// 0 — цикл жок, текст таза.
  static int loopWords(String text) {
    if (text.trim().isEmpty) return 0;
    return _words(text) - _words(deloop(text));
  }

  /// Текст кайталоого (циклге) түшүп калганбы?
  /// [limit] — ушунчадан көп сөз кайталанса цикл деп эсептейбиз.
  static bool hasLoop(String text, {int limit = 25}) =>
      loopWords(text) >= limit;

  /// Катары менен эки жолу жазылган бирдей сөздү бирөөгө калтырат:
  /// «процесс процесс жүрөт» → «процесс жүрөт».
  /// Академиялык текстте мындай кайталоо ар дайым ката.
  static String dropDoubledWords(String text) {
    final re = RegExp(
      r'(?<![\wЀ-ӿ])([\wЀ-ӿ]{3,})(\s+)\1(?![\wЀ-ӿ])',
      caseSensitive: false,
      unicode: true,
    );
    var s = text;
    for (var i = 0; i < 3; i++) {
      final before = s;
      s = s.replaceAllMapped(re, (m) {
        final whole = m.group(0)!;
        final word = m.group(1)!;
        // Сандарга (таблицадагы маанилер) жана формулаларга тийбейбиз.
        if (RegExp(r'^\d+$').hasMatch(word)) return whole;
        if (whole.contains('"') || whole.contains(r'$')) return whole;
        return word;
      });
      if (s == before) break;
    }
    return s;
  }

  /// [addition] мурда жазылганды кайра баштап жатабы?
  /// (улантуу сурамынан кийин текшерилет).
  static bool repeatsStart(String existing, String addition) {
    final a = _key(addition);
    if (a.length < 40) return false;
    final head = a.substring(0, 40);
    return _key(existing).contains(head);
  }
}
