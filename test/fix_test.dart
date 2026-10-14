import 'package:flutter_test/flutter_test.dart';
import 'package:srs_generator/models/doc_block.dart';
import 'package:srs_generator/models/handwriting_style.dart';
import 'package:srs_generator/models/srs_config.dart';
import 'package:srs_generator/services/markdown_parser.dart';
import 'package:srs_generator/services/page_fitter.dart';
import 'package:srs_generator/services/text_sanitizer.dart';

SrsConfig _cfg(PageCount pages, {HandwritingStyle? hand}) => SrsConfig(
      subject: Subject.geography,
      language: Language.kyrgyz,
      pageCount: pages,
      topic: 'Ысык көл',
      handwriting: hand,
    );

void main() {
  group('Кайталанган сөздөр', () {
    test('циклге түшкөн сөздөр жоюлат', () {
      final loop = List.filled(200, 'бир кээ').join(' ');
      final out = TextSanitizer.deloop('Текст башталат. $loop Аягы.');
      expect(out.length, lessThan(80));
      expect(out.contains('Текст башталат.'), isTrue);
      expect('кээ'.allMatches(out).length, lessThan(3));
    });

    test('кадимки текст өзгөрбөйт', () {
      const text = 'Ысык көл Кыргызстандын түндүгүндө жайгашкан чоң көл '
          'болуп саналат жана анын суусу туздуу.';
      expect(TextSanitizer.deloop(text), text);
    });

    test('бөлүм башынан кайра жазылса, кесилет', () {
      const title = 'Ысык көлдүн географиялык өзгөчөлүктөрү';
      final text = 'Көл Теңир-Тоодо жайгашкан жана терең. ' * 6 +
          '\n$title\n1. Орношу жана көлөмү\nКайра башталган текст.';
      final out = TextSanitizer.section(text, title);
      expect(out.contains('Кайра башталган'), isFalse);
      expect(out.contains('Теңир-Тоодо'), isTrue);
    });

    test('эки жолу жазылган абзац бир калат', () {
      const p = 'Көлдүн гидрологиялык режими анын суу балансы менен '
          'аныкталат жана жыл сайын өзгөрүп турат, бул климатка байланыштуу.';
      final out = TextSanitizer.document('$p\n\nБашка сап.\n\n$p');
      expect(p.allMatches(out).length, 1);
    });
  });

  group('Барак саны', () {
    test('кол жазмада бир бетке аз сөз батат', () {
      final plain = PageFitter.wordsPerPage(_cfg(PageCount.five));
      final hand =
          PageFitter.wordsPerPage(_cfg(PageCount.five, hand: HandwritingStyle.caveat));
      expect(hand, lessThan(plain));
      expect(plain, greaterThan(250));
      expect(hand, greaterThan(80));
    });

    test('көп барак — көп сөз', () {
      expect(PageFitter.totalWords(_cfg(PageCount.ten)),
          greaterThan(PageFitter.totalWords(_cfg(PageCount.five))));
    });

    test('ашыкча текст суралган барак санына кыскарат', () {
      final config = _cfg(PageCount.five, hand: HandwritingStyle.marckKg);
      final buf = StringBuffer();
      for (var s = 1; s <= 4; s++) {
        buf.writeln('## $s-бөлүм\n');
        for (var i = 0; i < 12; i++) {
          buf.writeln('Көлдүн гидрологиялык жана экологиялык абалы жөнүндө '
              'кеңири маалымат берилет, анын суу балансы, температурасы жана '
              'биологиялык ар түрдүүлүгү талданат. Бул $s-$i абзац.\n');
        }
      }
      final before = PageFitter.estimatePages(
          MarkdownParser.parse(buf.toString()), config);
      expect(before, greaterThan(5));

      final fitted = PageFitter.fit(buf.toString(), config);
      final after =
          PageFitter.estimatePages(MarkdownParser.parse(fitted), config);
      expect(after, lessThanOrEqualTo(5));
      // Бардык бөлүмдөр ордунда калышы керек
      for (var s = 1; s <= 4; s++) {
        expect(fitted.contains('## $s-бөлүм'), isTrue);
      }
    });

    test('жетиштүү текст кыскарбайт', () {
      final config = _cfg(PageCount.twenty);
      const md = '## Киришүү\n\nКыска текст.\n\n## Корутунду\n\nБүттү.';
      expect(PageFitter.fit(md, config), md);
    });
  });

  group('Сүрөттөр', () {
    const chart = '{"title":"Көлөм","type":"line","caption":"Түшүндүрмө",'
        '"series":[{"name":"V","points":[[2000,3.6],[2001,3.7]]}]}';

    test('бирдей сүрөт эки жолу кирбейт', () {
      final blocks = MarkdownParser.parse(
        '```chart\n$chart\n```\n\nТекст.\n\n```chart\n$chart\n```',
        lang: Language.kyrgyz,
      );
      expect(blocks.where((b) => b.type == BlockType.diagram).length, 1);
    });

    test('сүрөттөр кезеги менен номерленет', () {
      final other = chart.replaceAll('[[2000,3.6],[2001,3.7]]',
          '[[2000,1.1],[2001,1.4]]');
      final blocks = MarkdownParser.parse(
        '```chart\n$chart\n```\n\nТекст.\n\n```chart\n$other\n```',
        lang: Language.kyrgyz,
      );
      final caps = [
        for (final b in blocks)
          if (b.type == BlockType.diagram) b.diagram!.caption
      ];
      expect(caps.length, 2);
      expect(caps[0].startsWith('1-сүрөт.'), isTrue);
      expect(caps[1].startsWith('2-сүрөт.'), isTrue);
    });

    test('эски номер кайра жазылат', () {
      final old = chart.replaceAll('"caption":"Түшүндүрмө"',
          '"caption":"1-сүрөт. Көлдүн көлөмү"');
      final blocks =
          MarkdownParser.parse('```chart\n$old\n```', lang: Language.kyrgyz);
      final cap = blocks.firstWhere((b) => b.type == BlockType.diagram)
          .diagram!
          .caption;
      expect(cap, '1-сүрөт. Көлдүн көлөмү');
    });
  });
}
