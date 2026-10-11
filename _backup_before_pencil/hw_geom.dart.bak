/// Шаблонсуз (дептерге катар жазылган) тамгалар топтому.
class HwSet {
  final String id;
  final String title;
  final String chars;

  /// Өлчөмдү эсептөө үчүн тамгалар ('' — бардыгы).
  final String measure;

  /// Бул тамгалардын максаттагы бийиктиги (пиксель, ички масштабда).
  final double target;
  const HwSet(this.id, this.title, this.chars, this.measure, this.target);
}

/// Кол жазма шаблонунун геометриясы (миллиметр). Шаблон PDF жана сүрөттү
/// иштетүү ушул бир эле константаларды колдонот — өзгөртсөңүз экөө тең
/// өзгөрөт, ошондуктан бул сандарды кокус өзгөртпөңүз.
class HwGeom {
  /// Кыргыз алфавити (ө, ү, ң өз орундарында).
  static const String kyLower = 'абвгдеёжзийклмнңоөпрстуүфхцчшщъыьэюя';
  static const String kyUpper = 'АБВГДЕЁЖЗИЙКЛМНҢОӨПРСТУҮФХЦЧШЩЪЫЬЭЮЯ';

  static const List<HwSet> freeSets = [
    HwSet('lower', 'Кичине тамгалар', kyLower, 'аеоспинмз', 44),
    HwSet('upper', 'Баш тамгалар', kyUpper, '', 72),
    HwSet('digits', 'Цифралар', '0123456789', '', 66),
    HwSet('latlower', 'Латын кичине (a–z)', 'abcdefghijklmnopqrstuvwxyz',
        'acemnorsuvwxz', 44),
    HwSet('latupper', 'Латын баш (A–Z)', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '', 72),
  ];

  static const double pageW = 210;
  static const double pageH = 297;

  /// Бурчтардагы кара квадраттар: [борбор x, борбор y, өлчөм]. Тартибі:
  /// сол-жогорку (чоң), оң-жогорку, сол-төмөнкү, оң-төмөнкү.
  static const List<List<double>> markers = [
    [12, 12, 12],
    [199, 11, 8],
    [11, 286, 8],
    [199, 286, 8],
  ];

  static const double gridL = 14;
  static const double gridT = 22;
  static const double cellW = 26;
  static const double cellH = 28.5;
  static const int cols = 7;
  static const int rows = 9;
  static const double labelH = 5;
  static const double inset = 1.5;

  /// Түзөтүлгөн сүрөттүн тыгыздыгы: пиксель / мм.
  static const int scale = 8;
  static const double baseFrac = 0.62;

  static const String lower = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяөүң';
  static const String upper = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯӨҮҢ';
  static const String digits = '0123456789';
  static const String punct = '.,:;!?()-–+=/%"\'№•°×²';
  static const String latLower = 'abcdefghijklmnopqrstuvwxyz';
  static const String latUpper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String all = lower + upper + digits + punct + latLower + latUpper;

  static const int perPage = cols * rows;
  static const int pageCount = (all.length + perPage - 1) ~/ perPage;

  static String pageChars(int page) {
    final start = page * perPage;
    final end = start + perPage > all.length ? all.length : start + perPage;
    if (start >= all.length) return '';
    return all.substring(start, end);
  }

  static double cellX(int i) => gridL + (i % cols) * cellW;
  static double cellY(int i) => gridT + (i ~/ cols) * cellH;

  /// Жазуу аймагы (мм): [x0, y0, x1, y1].
  static List<double> writeRect(int i) {
    final ox = cellX(i);
    final oy = cellY(i);
    return [
      ox + inset,
      oy + labelH + inset,
      ox + cellW - inset,
      oy + cellH - inset,
    ];
  }

  static double baselineY(int i) {
    final r = writeRect(i);
    return r[1] + baseFrac * (r[3] - r[1]);
  }
}
