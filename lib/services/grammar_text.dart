/// Грамматика текшерүүнүн тилден көз каранды эмес бөлүгү.
///
/// Формулаларды жана сүрөт блокторун коргоо, AI редактордун жообун тазалоо
/// жана ал жооп ишенимдүүбү деп текшерүү — булар кыргызча да, орусча да,
/// англисче да бирдей иштейт.
class GrammarText {
  static final RegExp _protectRe = RegExp(
    r'```[\s\S]*?```|\$\$[\s\S]*?\$\$|\$[^$\n]+\$',
  );

  /// Формула жана код блокторун ⟦0⟧, ⟦1⟧ ... белгилери менен алмаштырат.
  static (String, List<String>) protect(String text) {
    final saved = <String>[];
    final masked = text.replaceAllMapped(_protectRe, (m) {
      saved.add(m.group(0)!);
      return '⟦${saved.length - 1}⟧';
    });
    return (masked, saved);
  }

  /// Белгилерди кайра ордуна коёт. Бир белги жоголсо же кайталанса — null
  /// (ошондо текст өзгөртүлбөй, мурунку бойдон калат).
  static String? restore(String masked, List<String> saved) {
    for (var i = 0; i < saved.length; i++) {
      if ('⟦$i⟧'.allMatches(masked).length != 1) return null;
    }
    var out = masked;
    for (var i = 0; i < saved.length; i++) {
      out = out.replaceFirst('⟦$i⟧', saved[i]);
    }
    return out;
  }

  /// AI жообунан ашыкча нерселерди (баш сөз, ``` рамкасы) тазалайт.
  static String cleanResponse(String r) {
    var s = r.trim();
    s = s.replaceAll('<<<', '').replaceAll('>>>', '').trim();
    // Бүт жооп ``` ичине оролгон болсо
    final fence = RegExp(r'^```[a-zA-Z]*\n([\s\S]*?)\n```$');
    final fm = fence.firstMatch(s);
    if (fm != null) s = fm.group(1)!.trim();
    // «Мына оңдолгон текст:» сыяктуу баш сөз
    final lines = s.split('\n');
    if (lines.length > 2) {
      final first = lines.first.trim().toLowerCase();
      if (first.endsWith(':') && first.length < 90 && _prefaceWords.any(first.contains)) {
        s = lines.skip(1).join('\n').trim();
      }
    }
    return s;
  }

  static const List<String> _prefaceWords = [
    'текст', 'оңдол', 'мына', 'вот', 'исправлен', 'отредактирован',
    'corrected', 'revised', 'here is', 'here\'s',
  ];

  /// AI жообу ишенимдүүбү: көлөмү жана таблица саптары сакталганбы.
  /// Ишенимсиз болсо текст өзгөртүлбөйт — текшерүү эч качан бузбайт.
  static bool plausible(String before, String after) {
    if (after.trim().isEmpty) return false;
    final ratio = after.length / before.length.clamp(1, 1 << 30);
    if (ratio < 0.85 || ratio > 1.2) return false;
    int rows(String t) =>
        t.split('\n').where((l) => l.trimLeft().startsWith('|')).length;
    if (rows(before) != rows(after)) return false;
    return true;
  }

  // ------------------------------------------------- жалпы автооңдоолор
  /// Кирилл сөздүн ичине кирип калган латын тамгалары (сырты бирдей).
  static const Map<String, String> latinLook = {
    'a': 'а', 'e': 'е', 'o': 'о', 'p': 'р', 'c': 'с', 'x': 'х', 'y': 'у',
    'A': 'А', 'B': 'В', 'E': 'Е', 'K': 'К', 'M': 'М', 'H': 'Н', 'O': 'О',
    'P': 'Р', 'C': 'С', 'T': 'Т', 'X': 'Х',
  };

  /// Латын сөздүн ичине кирип калган кирилл тамгалары (тескериси).
  static const Map<String, String> cyrillicLook = {
    'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'х': 'x', 'у': 'y',
    'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H', 'О': 'O',
    'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X',
  };

  static bool isCyrillic(int c) =>
      (c >= 0x0400 && c <= 0x04FF) || (c >= 0x0500 && c <= 0x052F);

  static final RegExp wordRe = RegExp(r'[A-Za-zЀ-ԯ]+');

  /// Аралашып кеткен тамгаларды оңдойт.
  /// [toCyrillic] true болсо — кирилл сөздөгү латын тамгалары оңдолот,
  /// false болсо — латын сөздөгү кирилл тамгалары.
  static (String, int) fixMixedLetters(String text, {bool toCyrillic = true}) {
    var n = 0;
    final table = toCyrillic ? latinLook : cyrillicLook;
    final out = text.replaceAllMapped(wordRe, (m) {
      final w = m.group(0)!;
      final hasCyr = w.codeUnits.any(isCyrillic);
      final hasLat = w.codeUnits.any((c) => c < 128);
      if (!hasCyr || !hasLat) return w;
      final b = StringBuffer();
      for (final ch in w.split('')) {
        final rep = table[ch];
        if (rep != null) {
          b.write(rep);
          n++;
        } else {
          b.write(ch);
        }
      }
      return b.toString();
    });
    return (out, n);
  }

  /// Ашыкча боштуктар жана тыныш белгилеринин алдындагы боштук.
  static (String, int) fixSpacing(String text) {
    var n = 0;
    var s = text.replaceAllMapped(RegExp(r'(\S) {2,}(?=\S)'), (m) {
      n++;
      return '${m.group(1)} ';
    });
    s = s.replaceAllMapped(RegExp(r'(\S) +([,.;:!?])(?=\s|$)'), (m) {
      n++;
      return '${m.group(1)}${m.group(2)}';
    });
    return (s, n);
  }

  /// Кирилл тексттеги "..." → «...».
  static (String, int) fixQuotes(String text) {
    var n = 0;
    final s = text.replaceAllMapped(RegExp(r'"([^"\n]{1,120})"'), (m) {
      final inner = m.group(1)!;
      if (!inner.codeUnits.any(isCyrillic)) return m.group(0)!;
      n++;
      return '«$inner»';
    });
    return (s, n);
  }
}

/// Грамматиканы текшерүүнүн жыйынтыгы.
class GrammarReport {
  final String text;

  /// Жергиликтүү эрежелер менен оңдолгон жерлер.
  final int autoFixes;

  /// AI редактор канча жолу текстти карап чыкты.
  final int aiRounds;

  /// Акырында калган шектүү жерлер (көбүнчө туура болот).
  final List<String> remaining;

  const GrammarReport(this.text, this.autoFixes, this.aiRounds, this.remaining);
}
