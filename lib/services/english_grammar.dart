import 'grammar.dart';
import 'grammar_text.dart';

/// Англис тилинин грамматика плагини.
///
/// Эң көп кездешкен эки катаны алдын алат: латын сөздүн ичине кирилл
/// тамгасы кирип кетиши (моделдин классикалык катасы) жана көп жолуккан
/// орфографиялык каталар. Калганын AI редактор карайт.
class EnglishGrammar extends LanguageGrammar {
  const EnglishGrammar();

  @override
  String get name => 'Англис';

  /// Көп кездешкен орфографиялык каталар.
  static const Map<String, String> _misspellings = {
    'recieve': 'receive',
    'occured': 'occurred',
    'seperate': 'separate',
    'definately': 'definitely',
    'enviroment': 'environment',
    'goverment': 'government',
    'neccessary': 'necessary',
    'occurence': 'occurrence',
    'refered': 'referred',
    'acheive': 'achieve',
    'beleive': 'believe',
    'calender': 'calendar',
    'existance': 'existence',
    'independant': 'independent',
    'maintainance': 'maintenance',
    'occassion': 'occasion',
    'persistant': 'persistent',
    'succesful': 'successful',
    'teh': 'the',
    'wich': 'which',
  };

  static final RegExp _wordRe = RegExp(r"[A-Za-zЀ-ԯ']+", unicode: true);

  @override
  (String, int) autoFix(String text) {
    var n = 0;

    // Латын сөздүн ичиндеги кирилл тамгалары
    final mixed = GrammarText.fixMixedLetters(text, toCyrillic: false);
    var s = mixed.$1;
    n += mixed.$2;

    // Орфография
    s = s.replaceAllMapped(RegExp(r'\b[A-Za-z]+\b'), (m) {
      final w = m.group(0)!;
      final fix = _misspellings[w.toLowerCase()];
      if (fix == null) return w;
      n++;
      final isCap = w[0] == w[0].toUpperCase();
      return isCap ? '${fix[0].toUpperCase()}${fix.substring(1)}' : fix;
    });

    final sp = GrammarText.fixSpacing(s);
    s = sp.$1;
    n += sp.$2;

    return (s, n);
  }

  @override
  List<String> findIssues(String text) {
    final out = <String>{};
    final words = _wordRe.allMatches(text).toList();

    for (var i = 0; i < words.length; i++) {
      final orig = words[i].group(0)!;
      // Кирилл сөз англисче тексттте
      if (orig.codeUnits.any(GrammarText.isCyrillic)) {
        out.add('"$orig" — non-English word, translate it');
        continue;
      }
      // Эки жолу жазылган сөз
      if (i > 0) {
        final prev = words[i - 1].group(0)!;
        if (prev.toLowerCase() == orig.toLowerCase() && orig.length > 2) {
          out.add('"$prev $orig" — the word is repeated twice');
        }
      }
    }

    if (RegExp(r'\bits\s+(a|an|the|not|very)\b', caseSensitive: false)
        .hasMatch(text)) {
      out.add('"its" before a/an/the/not — should probably be "it\'s"');
    }
    if (RegExp(r"\bit's\s+\w+(ness|tion|ity)\b", caseSensitive: false)
        .hasMatch(text)) {
      out.add('"it\'s" before a noun — should probably be possessive "its"');
    }
    if (RegExp(r'\ba\s+[aeiouAEIOU]\w+').hasMatch(text)) {
      out.add('"a" before a vowel sound — check whether "an" is needed');
    }

    return out.take(40).toList();
  }

  @override
  String get rules => '''
ENGLISH LANGUAGE RULES (follow strictly):
1. Alphabet: Latin letters only. Cyrillic look-alikes (а, е, о, р, с, х)
   inside English words are errors.
2. Subject-verb agreement: "the data show", "the result shows",
   "each of the samples was measured".
3. Articles: use "a/an/the" correctly; "an" before a vowel sound
   (an hour, a university); no article with uncountable nouns in general
   statements (water is essential).
4. Tense: use the present tense for established facts and the past tense
   for what was done in the study ("the temperature was measured").
5. Academic voice: prefer the passive or impersonal form
   ("it was found that"), avoid contractions (don't, isn't) and
   colloquialisms.
6. Prepositions: "based on", "consistent with", "in contrast to",
   "compared with", "an increase in", "a decrease of".
7. Numbers and units: 3.6 (decimal point), 10 m, 25 °C, 5 mg/L;
   ranges with an en dash: 2018-2024.
8. Punctuation: the serial comma before "and" in a list; a comma before
   "which" in non-defining clauses, none before "that".
9. Capitalisation: sentence case in running text; proper nouns capitalised.
10. Do not repeat the same word or idea twice in a row.''';

  @override
  String get system => 'You are a scholar writing in precise academic '
      'English. Follow English grammar strictly.\n$rules';

  @override
  String proofreadPrompt(String masked, List<String> hints) {
    final h = hints.isEmpty
        ? ''
        : '\nAn automatic check found these suspicious places (check each '
            'one: keep it if correct, fix it if wrong):\n'
            '${hints.map((e) => '- $e').join('\n')}\n';
    return '''
You are an experienced English copy editor. Below is one section of a
student's independent work. Read it word by word and fix ENGLISH grammar,
spelling and punctuation.

$rules
$h
STRICT REQUIREMENTS:
- Do not change the content, facts or numbers; do not shorten or add anything.
- Markers like ⟦0⟧, ⟦1⟧ are formulas; leave them EXACTLY as they are,
  in the same places.
- Keep the markdown structure: lines, lists (-, 1.), the | characters in
  tables, **bold** markers.
- Do not write explanations, prefaces or phrases like "Here is the corrected
  text".
- Reply with THE CORRECTED TEXT ONLY.

TEXT:
<<<
$masked
>>>''';
  }
}
