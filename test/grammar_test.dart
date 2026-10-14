import 'package:flutter_test/flutter_test.dart';
import 'package:srs_generator/models/srs_config.dart';
import 'package:srs_generator/services/grammar.dart';
import 'package:srs_generator/services/text_sanitizer.dart';

void main() {
  group('Үч тилде тең плагин бар', () {
    test('ар бир тилге плагин табылат', () {
      for (final lang in Language.values) {
        final g = LanguageGrammar.of(lang);
        expect(g.rules.length, greaterThan(200));
        expect(g.system.isNotEmpty, isTrue);
        expect(g.proofreadPrompt('текст', const []).contains('текст'), isTrue);
      }
    });

    test('формулалар текшерүүдөн корголот', () {
      const text = r'Формула: $$E = mc^2$$ жана код ```chart{"a":1}``` бар.';
      final p = GrammarText.protect(text);
      expect(p.$2.length, 2);
      expect(p.$1.contains(r'$$'), isFalse);
      expect(GrammarText.restore(p.$1, p.$2), text);
    });

    test('формула жоголсо, текст өзгөртүлбөйт', () {
      final p = GrammarText.protect(r'Формула $x=1$ бар.');
      expect(GrammarText.restore('Формула бар.', p.$2), isNull);
    });
  });

  group('Орус грамматикасы', () {
    const g = RussianGrammar();

    test('кош жазылуучу сөздөр оңдолот', () {
      final r = g.autoFix('Из за этого и из под слоя. По этому ясно.');
      expect(r.$1.contains('Из-за'), isTrue);
      expect(r.$1.contains('из-под'), isTrue);
      expect(r.$1.contains('Поэтому'), isTrue);
      expect(r.$2, greaterThan(2));
    });

    test('кирилл сөздөгү латын тамгасы оңдолот', () {
      // «вoда» ичинде латын o
      final r = g.autoFix('Здесь вoда и рaствор.');
      expect(r.$1, 'Здесь вода и раствор.');
      expect(r.$2, 2);
    });

    test('казакча тамгалар оңдолот, кыргызча сөз эскертилет', () {
      final r = g.autoFix('Қислота әсер етеді.');
      expect(r.$1.contains('қ'), isFalse);
      expect(r.$1.contains('ә'), isFalse);

      final issues = g.findIssues('Это көл очень терең.');
      expect(issues.any((e) => e.contains('көл')), isTrue);
    });

    test('«в течении» жана «так же» шектүү деп белгиленет', () {
      final issues = g.findIssues('В течении года так же росло.');
      expect(issues.any((e) => e.contains('в течении')), isTrue);
      expect(issues.any((e) => e.contains('так же')), isTrue);
    });

    test('«также» жалган эскертүү бербейт', () {
      expect(g.findIssues('Также важно учитывать это.'), isEmpty);
    });

    test('«может окисляется» табылат', () {
      final issues = g.findIssues('Вещество может окисляется в воде.');
      expect(issues.any((e) => e.contains('инфинитив')), isTrue);
    });

    test('тырмакча жана боштуктар оңдолот', () {
      final r = g.autoFix('Он сказал "да" , потом  ушёл.');
      expect(r.$1.contains('«да»'), isTrue);
      expect(r.$1.contains('" ,'), isFalse);
      expect(r.$1.contains('потом ушёл'), isTrue);
    });
  });

  group('Англис грамматикасы', () {
    const g = EnglishGrammar();

    test('латын сөздөгү кирилл тамгасы оңдолот', () {
      // «wаter» ичинде кирилл а
      final r = g.autoFix('The wаter is clеar.');
      expect(r.$1, 'The water is clear.');
      expect(r.$2, 2);
    });

    test('орфография оңдолот', () {
      final r = g.autoFix('We recieve seperate data. Teh end.');
      expect(r.$1.contains('receive'), isTrue);
      expect(r.$1.contains('separate'), isTrue);
      expect(r.$1.contains('The end'), isTrue);
    });

    test('эки жолу жазылган сөз табылат', () {
      final issues = g.findIssues('This is the the result.');
      expect(issues.any((e) => e.contains('repeated')), isTrue);
    });
  });

  group('Кайталоону текшергич', () {
    test('цикл табылат жана өлчөнөт', () {
      final loop = List.filled(100, 'бир кээ').join(' ');
      expect(TextSanitizer.hasLoop('Текст. $loop Аягы.'), isTrue);
      expect(TextSanitizer.loopWords('Текст. $loop Аягы.'), greaterThan(150));
    });

    test('кадимки текстте цикл жок', () {
      const t = 'Көлдүн суусу тунук жана терең, анын экологиялык абалы '
          'жылдан жылга өзгөрүп турат.';
      expect(TextSanitizer.hasLoop(t), isFalse);
      expect(TextSanitizer.loopWords(t), 0);
    });

    test('катары менен эки жолу жазылган сөз бирөө калат', () {
      expect(TextSanitizer.dropDoubledWords('Бул процесс процесс жүрөт.'),
          'Бул процесс жүрөт.');
      expect(TextSanitizer.dropDoubledWords('Вещество вещество реагирует.'),
          'Вещество реагирует.');
    });

    test('сандар жана кыска сөздөр тийилбейт', () {
      expect(TextSanitizer.dropDoubledWords('2018 2018 жыл'), '2018 2018 жыл');
      expect(TextSanitizer.dropDoubledWords('а а б'), 'а а б');
    });
  });
}
