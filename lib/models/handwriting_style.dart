/// Даяр кол жазма шрифттери (бардыгында кирилл жана ө, ү, ң тамгалары бар).
enum HandwritingStyle {
  caveat(
    id: 'caveat',
    label: 'Каветт',
    note: 'Тез жазылган, кыйгач кол жазма',
    asset: 'assets/fonts/handwriting/caveat.ttf',
    scale: 1.3,
  ),
  badScript(
    id: 'badscript',
    label: 'Каллиграфия',
    note: 'Кооз, байланышкан тамгалар',
    asset: 'assets/fonts/handwriting/badscript.ttf',
    scale: 1.05,
  ),
  marckKg(
    id: 'marckkg',
    label: 'Улана жазуу (ичке)',
    note: 'Ичке кыйгач ручка, тамгалар үзүлбөй улана жазылат (ө, ү, ң бар)',
    asset: 'assets/fonts/handwriting/marckscript_kg.ttf',
    scale: 1.15,
  ),
  pacifico(
    id: 'pacifico',
    label: 'Улана жазуу',
    note: 'Ручка үзбөй, бардык тамгалар бири-бирине улана жазылат',
    asset: 'assets/fonts/handwriting/pacifico.ttf',
    scale: 0.85,
  ),
  pangolin(
    id: 'pangolin',
    label: 'Студенттик',
    note: 'Жумшак, окуганга ыңгайлуу',
    asset: 'assets/fonts/handwriting/pangolin.ttf',
    scale: 1.05,
  ),
  shantell(
    id: 'shantell',
    label: 'Маркер',
    note: 'Тунук, маркер менен жазгандай',
    asset: 'assets/fonts/handwriting/shantell.ttf',
    scale: 0.95,
  ),
  playpen(
    id: 'playpen',
    label: 'Дептер',
    note: 'Мектеп дептериндей тегиз жазуу',
    asset: 'assets/fonts/handwriting/playpen.ttf',
    scale: 0.95,
  ),
  // Колдонуучунун өз кол жазмасы (сүрөттөн үйрөтүлгөн). Шрифт эмес,
  // ошондуктан asset бош; PDF кызматы аны өзүнчө иштетет.
  mine(
    id: 'mine',
    label: 'Менин кол жазмам',
    note: 'Өз кол жазмаңызды сүрөттөн үйрөтүңүз',
    asset: '',
    scale: 1.0,
  );

  final String id;
  final String label;
  final String note;
  final String asset;

  /// Шрифттин өлчөмүн кадимки текстке теңөө коэффициенти.
  final double scale;

  const HandwritingStyle({
    required this.id,
    required this.label,
    required this.note,
    required this.asset,
    required this.scale,
  });

  /// Flutter UI'да үлгү көрсөтүү үчүн (pubspec.yaml'дагы family аты).
  String get family => 'hw_$id';

  static HandwritingStyle? fromId(String? id) {
    for (final s in HandwritingStyle.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
