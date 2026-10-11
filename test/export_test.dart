import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srs_generator/models/srs_config.dart';
import 'package:srs_generator/services/docx_service.dart';
import 'package:srs_generator/services/markdown_parser.dart';
import 'package:srs_generator/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const author = AuthorInfo(
    student: 'Орозбий Ходжебеков',
    teacher: 'Асанов А.А.',
    group: 'ФЭ-1-24',
    university: 'К. Карасаев атындагы БМУ',
    faculty: 'Табигый илимдер факультети',
    department: 'Физика кафедрасы',
  );

  const content = '''
# Киришүү
Омдун мыйзамы: ө, ү, ң, Ө, Ү, Ң тамгалары менен текст.

\$\$
I = U/R
\$\$

| Параметр | Белгиси | Бирдиги |
|---|---|---|
| Кернөө | U | В |
| Ток | I | А |

- Биринчи пункт
- Экинчи пункт
''';

  for (final lang in Language.values) {
    test('${lang.label} PDF каталашпай жасалат', () async {
      final config = SrsConfig(
        subject: Subject.electronics,
        language: lang,
        pageCount: PageCount.five,
        topic: 'Омдун мыйзамы',
      );
      final bytes = await PdfService.build(
        config: config,
        blocks: MarkdownParser.parse(content),
        author: author,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
      expect(bytes.length, greaterThan(2000));
    });
  }

  test('Word файлы жарактуу ZIP/OOXML болот', () async {
    const config = SrsConfig(
      subject: Subject.physics,
      language: Language.kyrgyz,
      pageCount: PageCount.ten,
      topic: 'Омдун мыйзамы',
    );
    final bytes = await DocxService.build(
      config: config,
      blocks: MarkdownParser.parse(content),
      author: author,
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toList();
    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('word/document.xml'));
    expect(names, contains('word/_rels/document.xml.rels'));

    final doc = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    final xml = utf8.decode(doc.content as List<int>);
    expect(xml, contains('Омдун мыйзамы'));
    expect(xml, contains('<w:tbl>'));
    expect(xml, contains('Орозбий Ходжебеков'));
  });

  test('Узун текст көп бетке бөлүнөт', () async {
    const config = SrsConfig(
      subject: Subject.math,
      language: Language.kyrgyz,
      pageCount: PageCount.twenty,
      topic: 'Матрицалар',
    );
    final long = List.generate(
      300,
      (i) => 'Абзац №$i: математикалык объекттердин касиеттери жөнүндө '
          'кеңири түшүндүрмө берилет жана мисалдар каралат.',
    ).join('\n\n');

    final bytes = await PdfService.build(
      config: config,
      blocks: MarkdownParser.parse(long),
      author: author,
    );
    expect(bytes.length, greaterThan(10000));
  });
}
