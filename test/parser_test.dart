import 'package:flutter_test/flutter_test.dart';
import 'package:srs_generator/models/diagram_spec.dart';
import 'package:srs_generator/models/doc_block.dart';
import 'package:srs_generator/services/latex_text.dart';
import 'package:srs_generator/services/markdown_parser.dart';

void main() {
  test('LaTeX окулуучу текстке айланат', () {
    expect(LatexText.toPlain(r'I = \frac{U}{R}'), 'I = U/R');
    expect(LatexText.toPlain(r'P = \frac{V^{2}}{R}'), 'P = V²/R');
    expect(LatexText.toPlain(r'R_{1} = 10\,\Omega'), 'R₁ = 10 Ω');
    expect(LatexText.toPlain(r'a \cdot b \approx c'), 'a · b ≈ c');
  });

  test('Сап ичиндеги формулалар тазаланат', () {
    expect(LatexText.inline(r'мында \(V\) жана $I$ бар'),
        'мында V жана I бар');
    expect(LatexText.inline('**калың** текст'), 'калың текст');
  });

  test('Аталыштар, тизмелер жана формулалар таанылат', () {
    final blocks = MarkdownParser.parse('''
# Киришүү
Биринчи абзац.
- бир
- эки
1. номер бир

\$\$
I = U/R
\$\$
''');
    expect(blocks.any((b) => b.type == BlockType.h1), isTrue);
    expect(blocks.where((b) => b.type == BlockType.bullet).length, 2);
    expect(blocks.where((b) => b.type == BlockType.numbered).length, 1);
    expect(blocks.any((b) => b.type == BlockType.formula), isTrue);
  });

  test('Кайталанган аталыш бир жолу гана калат', () {
    final blocks = MarkdownParser.parse('## Киришүү\n## Киришүү\nтекст');
    expect(blocks.where((b) => b.type == BlockType.h2).length, 1);
  });

  test('Markdown таблица таанылат', () {
    final blocks = MarkdownParser.parse('''
| Параметр | Белгиси |
|---|---|
| Кернөө | U |
| Ток | I |
''');
    final table = blocks.firstWhere((b) => b.type == BlockType.table);
    expect(table.rows!.length, 3);
    expect(table.rows!.first.first, 'Параметр');
  });

  test('chart блогу диаграммага айланат', () {
    final blocks = MarkdownParser.parse('''
```chart
{"title":"ВАХ","type":"line","x":"U","y":"I","caption":"1-сүрөт",
 "series":[{"name":"R=10","points":[[0,0],[1,0.1],[2,0.2]]}]}
```
''');
    final d = blocks.firstWhere((b) => b.type == BlockType.diagram);
    expect(d.diagram!.kind, DiagramKind.chart);
    expect(d.diagram!.series.single.points.length, 3);
    expect(d.diagram!.caption, '1-сүрөт');
  });

  test('circuit жана block блоктору таанылат', () {
    final blocks = MarkdownParser.parse('''
```circuit
{"title":"Чынжыр","layout":"series","source":"12 В",
 "elements":[{"kind":"R","label":"R1"},{"kind":"C","label":"C1"}]}
```
```block
{"title":"Алгоритм","nodes":["Башы","Иштетүү","Аягы"],
 "shapes":["start","process","end"]}
```
''');
    final specs = blocks
        .where((b) => b.type == BlockType.diagram)
        .map((b) => b.diagram!)
        .toList();
    expect(specs.length, 2);
    expect(specs[0].kind, DiagramKind.circuit);
    expect(specs[0].elements.length, 2);
    expect(specs[1].kind, DiagramKind.block);
    expect(specs[1].nodes.length, 3);
  });

  test('``` белгисиз JSON да диаграмма болуп таанылат', () {
    final blocks = MarkdownParser.parse('''
Текст мурун.

{
"title":"Параллель схема",
"layout":"parallel",
"source":"U = 12 B",
"elements":[
{"kind":"R","label":"R1 = 10 Om"},
{"kind":"R","label":"R2 = 20 Om"}
]
}

Текст кийин.
''');
    final d = blocks.firstWhere((b) => b.type == BlockType.diagram);
    expect(d.diagram!.kind, DiagramKind.circuit);
    expect(d.diagram!.elements.length, 2);
    expect(blocks.where((b) => b.type == BlockType.paragraph).length, 2);
  });

  test('Кыркылган (API жабылбай калган) JSON чийки текст болуп чыкпайт', () {
    final blocks = MarkdownParser.parse('''
Схеманы карайлы.

{
"title":"Параллелдик ВАХ-лердин схемасы",
"layout":"parallel",
"source":"U = 36 В",
"caption":"2-сурет. Параллелдик туташкан ВАХ-лер.",
"elements":[
{"kind":"R","label":"R1 = 10 Om"},
{"kind":"R","label":"R2 = 20 Om"},
{"kind":"D","label":"D1"
''');
    // Диаграмма катары таанылбайт (бузук), бирок JSON сабы параграф
    // болуп да чыкпашы керек.
    expect(blocks.any((b) => b.type == BlockType.diagram), isFalse);
    for (final b in blocks) {
      if (b.type == BlockType.paragraph) {
        expect(b.text.contains('"title"'), isFalse);
        expect(b.text.contains('"elements"'), isFalse);
        expect(b.text.trim().startsWith('{'), isFalse);
      }
    }
    expect(blocks.any((b) => b.type == BlockType.paragraph && b.text.contains('Схеманы')), isTrue);
  });

  test('Атайын тили жок ``` блогундагы формула LaTeX\'тен тазаланат', () {
    final blocks = MarkdownParser.parse('''
Эсептөө:

```
\$\$\\frac{1}{R_{eq}}}=\\frac{1}{10}+\\frac{1}{20}=0.15\\;\\text{Om}^{-1},\\qquad R_{eq} \\approx 6\\;\\text{Om}.\$\$
```

Жыйынтык.
''');
    final f = blocks.firstWhere((b) => b.type == BlockType.formula);
    expect(f.text.contains(r'\frac'), isFalse);
    expect(f.text.contains('{'), isFalse);
    expect(f.text.contains('approx'), isFalse);
    expect(f.text.contains('≈'), isTrue);
    expect(f.text.contains('1/10'), isTrue);
  });

  test('Акыркы | жок таблица сабы да таблица болуп чыгат', () {
    final blocks = MarkdownParser.parse('''
| Корсотку | Маани |
| --- | --- |
| Ток | 5 А
| Чыңалуу | 12 В |
''');
    final table = blocks.firstWhere((b) => b.type == BlockType.table);
    expect(table.rows, isNotNull);
    expect(table.rows!.length, 3);
    expect(table.rows![1][0], 'Ток');
    for (final b in blocks) {
      if (b.type == BlockType.paragraph) {
        expect(b.text.trim().startsWith('|'), isFalse);
      }
    }
  });

  test('Бузук JSON программаны жыкпайт', () {
    final blocks = MarkdownParser.parse('```chart\n{бузук}\n```\nтекст');
    expect(blocks.any((b) => b.type == BlockType.diagram), isFalse);
    expect(blocks.any((b) => b.type == BlockType.paragraph), isTrue);
  });
}
