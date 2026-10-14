import '../models/srs_config.dart';
import 'english_grammar.dart';
import 'grammar_text.dart';
import 'kyrgyz_grammar.dart';
import 'russian_grammar.dart';

export 'english_grammar.dart';
export 'grammar_text.dart' show GrammarReport, GrammarText;
export 'kyrgyz_grammar.dart';
export 'russian_grammar.dart';

/// Бир тилдин грамматика плагини.
///
/// Ар бир тил үчүн үч нерсе керек:
///  1. [autoFix] — AIсыз, так эрежелер менен оңдоо (тамга, боштук, тырмакча);
///  2. [findIssues] — шектүү жерлерди табуу (AI редакторго кеңеш катары);
///  3. [proofreadPrompt] — AI редакторго берилүүчү тапшырма.
///
/// Жалпы машина (формулаларды коргоо, жоопту тазалоо, ишенимдүүлүктү
/// текшерүү) [GrammarText] ичинде, бардык тилге бирдей.
abstract class LanguageGrammar {
  const LanguageGrammar();

  /// Тандалган тилдин плагини.
  static LanguageGrammar of(Language lang) {
    switch (lang) {
      case Language.kyrgyz:
        return const KyrgyzGrammarPlugin();
      case Language.russian:
        return const RussianGrammar();
      case Language.english:
        return const EnglishGrammar();
    }
  }

  /// Тилдин аты (колдонуучуга көрсөтүлөт): «Кыргыз», «Орус», «Англис».
  String get name;

  /// Текст жазганда да, текшергенде да берилүүчү эрежелер.
  String get rules;

  /// Моделге берилүүчү системалык эскертүү.
  String get system;

  /// Так эрежелер менен оңдойт. Кайтарат: (текст, оңдоолордун саны).
  (String, int) autoFix(String text);

  /// Шектүү жерлер (AI редакторго кеңеш).
  List<String> findIssues(String text);

  /// Текшерүү үчүн промпт.
  String proofreadPrompt(String masked, List<String> hints);

  /// Диалогдо көрсөтүлүүчү абал.
  String get statusChecking => '$name грамматикасы текшерилүүдө...';
}

/// Кыргыз тили — эрежелери [KyrgyzGrammar] ичинде.
class KyrgyzGrammarPlugin extends LanguageGrammar {
  const KyrgyzGrammarPlugin();

  @override
  String get name => 'Кыргыз';

  @override
  String get rules => KyrgyzGrammar.rules;

  @override
  String get system =>
      'Сен кыргыз тилинде сабаттуу, академиялык стилде жазган '
      'окумуштуусуң. Кыргыз тилинин грамматикасын так сакта.\n'
      '${KyrgyzGrammar.rules}';

  @override
  (String, int) autoFix(String text) => KyrgyzGrammar.autoFix(text);

  @override
  List<String> findIssues(String text) => KyrgyzGrammar.findIssues(text);

  @override
  String proofreadPrompt(String masked, List<String> hints) =>
      KyrgyzGrammar.proofreadPrompt(masked, hints);
}
