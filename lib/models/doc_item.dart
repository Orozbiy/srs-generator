/// Жүктөлгөн документтин бир бөлүгү: аталыш, тизме пункту же абзац.
class DocItem {
  String text;
  final bool isHeading;
  final bool isListItem;
  bool selected;

  DocItem(
    this.text, {
    this.isHeading = false,
    this.isListItem = false,
    this.selected = true,
  });

  DocItem copy() => DocItem(
        text,
        isHeading: isHeading,
        isListItem: isListItem,
        selected: selected,
      );

  // "1." "1)" "1.2" "а)" "(а)" "-" "•" ж.б.
  static final RegExp _listRe = RegExp(
      r'^(?:[-•*–—▪●○◦■□►✓]|\d{1,3}[.)]|\(?[A-Za-zА-Яа-яӨөҮүҢң]\)|\d+(?:\.\d+)+\.?)\s+\S');
  static final RegExp _markerRe = RegExp(r'^---\s.*\s---$');
  static final RegExp _lowerStart = RegExp(r'^[a-zа-яёөүң]');
  static final RegExp _endsSentence = RegExp(r'[.!?;,»")]$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-zА-Яа-яЁёӨөҮүҢң]');

  /// Текстти аталыштарга, тизме пункттарына жана абзацтарга бөлөт.
  static List<DocItem> split(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final out = <DocItem>[];

    for (final line in lines) {
      // "--- Слайд 1 ---", "--- Барак 2 ---" белгилери
      if (_markerRe.hasMatch(line)) {
        out.add(DocItem(line.replaceAll('---', '').trim(), isHeading: true));
        continue;
      }

      final isList = _listRe.hasMatch(line);

      // PDFте сап бөлүнүп калган учурда мурунку пунктка улайбыз.
      if (!isList && out.isNotEmpty && _lowerStart.hasMatch(line)) {
        final prev = out.last;
        if (!prev.isHeading && !_endsSentence.hasMatch(prev.text)) {
          prev.text = '${prev.text} $line';
          continue;
        }
      }

      final heading = !isList &&
          line.length <= 80 &&
          !_endsSentence.hasMatch(line) &&
          !line.contains(' | ') &&
          _hasLetter.hasMatch(line);

      out.add(DocItem(line, isHeading: heading, isListItem: isList));
    }
    return out;
  }

  /// Тандалган бөлүктөрдү бир текстке бириктирет (AI'га берилет).
  static String join(Iterable<DocItem> items) {
    final buf = StringBuffer();
    for (final it in items) {
      if (!it.selected) continue;
      if (it.isHeading && buf.isNotEmpty) buf.writeln();
      buf.writeln(it.text);
    }
    return buf.toString().trim();
  }
}
