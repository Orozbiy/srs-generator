import 'diagram_spec.dart';

enum BlockType {
  h1,
  h2,
  h3,
  paragraph,
  bullet,
  numbered,
  formula,
  table,
  diagram,
  spacer,
}

/// PDF жана Word экспорту үчүн жалпы, форматтан көз каранды эмес блок.
class DocBlock {
  final BlockType type;
  final String text;

  /// Таблица үчүн: биринчи сап — аталыштар.
  final List<List<String>>? rows;

  /// Сүрөт/схема үчүн.
  final DiagramSpec? diagram;

  /// Номерленген тизме үчүн.
  final String marker;

  const DocBlock(
    this.type,
    this.text, {
    this.rows,
    this.diagram,
    this.marker = '',
  });
}
