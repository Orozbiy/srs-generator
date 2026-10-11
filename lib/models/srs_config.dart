import 'handwriting_style.dart';

/// Предметтер КУУ (Жусуп Баласагын атындагы КУУ) негизги багыттары боюнча.
/// Эскертүү: enum аттары сакталган СРС тарыхында колдонулат, ошондуктан
/// эски аттарды өзгөртпөңүз — жаңыларын тизменин аягына кошуңуз.
enum Subject {
  physics,
  electronics,
  math,
  informatics,
  chemistry,
  biology,
  geography,
  history,
  economics,
  law,
  kyrgyzLang,
  russianLang,
  foreignLang,
  pedagogy,
  journalism,
  management,
  philosophy,
  intlRelations,
}

enum Language { kyrgyz, russian, english }

enum PageCount { five, ten, fifteen, twenty }

extension SubjectExt on Subject {
  String get icon {
    switch (this) {
      case Subject.physics:
        return '⚛';
      case Subject.electronics:
        return '⚡';
      case Subject.math:
        return '∑';
      case Subject.informatics:
        return '⌨';
      case Subject.chemistry:
        return '⚗';
      case Subject.biology:
        return '🧬';
      case Subject.geography:
        return '🌍';
      case Subject.history:
        return '🏛';
      case Subject.economics:
        return '📈';
      case Subject.law:
        return '⚖';
      case Subject.kyrgyzLang:
        return '📖';
      case Subject.russianLang:
        return '✎';
      case Subject.foreignLang:
        return 'Aa';
      case Subject.pedagogy:
        return '🎓';
      case Subject.journalism:
        return '📰';
      case Subject.management:
        return '💼';
      case Subject.philosophy:
        return '💭';
      case Subject.intlRelations:
        return '🌐';
    }
  }

  /// (кыргызча, орусча, англисче) аталыштар.
  (String, String, String) get _names {
    switch (this) {
      case Subject.physics:
        return ('Физика', 'Физика', 'Physics');
      case Subject.electronics:
        return ('Электроника', 'Электроника', 'Electronics');
      case Subject.math:
        return ('Математика', 'Математика', 'Mathematics');
      case Subject.informatics:
        return ('Информатика', 'Информатика', 'Computer Science');
      case Subject.chemistry:
        return ('Химия', 'Химия', 'Chemistry');
      case Subject.biology:
        return ('Биология', 'Биология', 'Biology');
      case Subject.geography:
        return (
          'География жана экология',
          'География и экология',
          'Geography and Ecology'
        );
      case Subject.history:
        return ('Тарых', 'История', 'History');
      case Subject.economics:
        return ('Экономика', 'Экономика', 'Economics');
      case Subject.law:
        return ('Укук таануу', 'Правоведение', 'Law');
      case Subject.kyrgyzLang:
        return (
          'Кыргыз тили жана адабияты',
          'Кыргызский язык и литература',
          'Kyrgyz Language and Literature'
        );
      case Subject.russianLang:
        return (
          'Орус тили жана адабияты',
          'Русский язык и литература',
          'Russian Language and Literature'
        );
      case Subject.foreignLang:
        return (
          'Чет тили (англис тили)',
          'Иностранный язык (английский)',
          'English Language'
        );
      case Subject.pedagogy:
        return (
          'Педагогика жана психология',
          'Педагогика и психология',
          'Pedagogy and Psychology'
        );
      case Subject.journalism:
        return ('Журналистика', 'Журналистика', 'Journalism');
      case Subject.management:
        return ('Менеджмент', 'Менеджмент', 'Management');
      case Subject.philosophy:
        return ('Философия', 'Философия', 'Philosophy');
      case Subject.intlRelations:
        return (
          'Эл аралык мамилелер',
          'Международные отношения',
          'International Relations'
        );
    }
  }

  String nameIn(Language lang) {
    final n = _names;
    switch (lang) {
      case Language.kyrgyz:
        return n.$1;
      case Language.russian:
        return n.$2;
      case Language.english:
        return n.$3;
    }
  }

  /// Бул предметке мүнөздүү сүрөттөрдүн түрлөрү (AI промптуна кирет).
  String get diagramHint {
    switch (this) {
      case Subject.physics:
        return 'көз карандылык графиктери (мис. v(t), F(x)), күчтөрдүн схемасы';
      case Subject.electronics:
        return 'принципиалдык электр схемалары (R, C, L, булак), ВАХ графиктери';
      case Subject.math:
        return 'функциялардын графиктери, координаталык тегиздик';
      case Subject.informatics:
        return 'алгоритмдин блок-схемасы, маалымат агымынын структурасы';
      case Subject.chemistry:
        return 'реакциянын ылдамдыгы же концентрациянын көз карандылык графиги';
      case Subject.biology:
        return 'популяциянын өсүшү жана биологиялык көрсөткүчтөрдүн графиги';
      case Subject.geography:
        return 'климат, температура жана экологиялык көрсөткүчтөрдүн графиги';
      case Subject.history:
        return 'окуялардын хронологиялык диаграммасы, статистикалык график';
      case Subject.economics:
        return 'суроо-сунуш, өсүү жана инфляция графиктери';
      case Subject.law:
        return 'укуктук процесстин жана органдардын түзүмүнүн блок-схемасы';
      case Subject.kyrgyzLang:
        return 'тил түзүмүнүн схемасы, адабий мезгилдердин диаграммасы';
      case Subject.russianLang:
        return 'тил түзүмүнүн схемасы, адабий мезгилдердин диаграммасы';
      case Subject.foreignLang:
        return 'грамматикалык схема, тил деңгээлдеринин диаграммасы';
      case Subject.pedagogy:
        return 'окутуу процессинин схемасы, сурамжылоо жыйынтыгынын диаграммасы';
      case Subject.journalism:
        return 'маалымат таркатуу схемасы, аудитория статистикасынын диаграммасы';
      case Subject.management:
        return 'уюштуруу түзүмүнүн схемасы, көрсөткүчтөрдүн графиги';
      case Subject.philosophy:
        return 'агымдардын жана түшүнүктөрдүн байланыш схемасы';
      case Subject.intlRelations:
        return 'мамлекеттердин байланыш схемасы, соода статистикасынын графиги';
    }
  }

  /// Формулалар милдеттүүбү?
  bool get needsFormulas {
    switch (this) {
      case Subject.physics:
      case Subject.electronics:
      case Subject.math:
      case Subject.informatics:
      case Subject.chemistry:
      case Subject.biology:
      case Subject.economics:
        return true;
      default:
        return false;
    }
  }

  /// Сандык көз карандылык графиги (chart) керекпи?
  bool get needsChart {
    switch (this) {
      case Subject.physics:
      case Subject.electronics:
      case Subject.math:
      case Subject.chemistry:
      case Subject.biology:
      case Subject.geography:
      case Subject.economics:
      case Subject.management:
        return true;
      default:
        return false;
    }
  }

  bool get needsCircuits => this == Subject.electronics;

  bool get needsBlockDiagram =>
      this == Subject.informatics ||
      this == Subject.management ||
      this == Subject.law;
}

extension LanguageExt on Language {
  String get label {
    switch (this) {
      case Language.kyrgyz:
        return 'Кыргызча';
      case Language.russian:
        return 'Орусча';
      case Language.english:
        return 'English';
    }
  }

  String get code {
    switch (this) {
      case Language.kyrgyz:
        return 'KG';
      case Language.russian:
        return 'RU';
      case Language.english:
        return 'EN';
    }
  }

  /// AI промптунда колдонулуучу тилдин аты.
  String get promptName {
    switch (this) {
      case Language.kyrgyz:
        return 'кыргыз';
      case Language.russian:
        return 'русском';
      case Language.english:
        return 'English';
    }
  }

  bool get isKyrgyz => this == Language.kyrgyz;
}

extension PageCountExt on PageCount {
  int get value {
    switch (this) {
      case PageCount.five:
        return 5;
      case PageCount.ten:
        return 10;
      case PageCount.fifteen:
        return 15;
      case PageCount.twenty:
        return 20;
    }
  }

  String label(Language lang) =>
      lang == Language.english ? '$value pages' : '$value барак';
}

/// Титул бетке жана документке тиешелүү жеке маалыматтар.
class AuthorInfo {
  final String student;
  final String teacher;
  final String group;
  final String university;
  final String faculty;
  final String department;

  const AuthorInfo({
    this.student = '',
    this.teacher = '',
    this.group = '',
    this.university = '',
    this.faculty = '',
    this.department = '',
  });

  Map<String, dynamic> toJson() => {
        'student': student,
        'teacher': teacher,
        'group': group,
        'university': university,
        'faculty': faculty,
        'department': department,
      };

  factory AuthorInfo.fromJson(Map<String, dynamic> j) => AuthorInfo(
        student: (j['student'] ?? '') as String,
        teacher: (j['teacher'] ?? '') as String,
        group: (j['group'] ?? '') as String,
        university: (j['university'] ?? '') as String,
        faculty: (j['faculty'] ?? '') as String,
        department: (j['department'] ?? '') as String,
      );
}

class SrsConfig {
  final Subject subject;
  final Language language;
  final PageCount pageCount;
  final String topic;
  final String? documentText;

  /// null — кадимки жазуу, башкасы — тандалган кол жазма.
  final HandwritingStyle? handwriting;

  /// «Менин кол жазмам» тандалганда — кимдин кол жазмасы (профилдин id'си).
  /// null — негизги кол жазма.
  final String? handProfile;

  /// Сүрөт/схема кошулсунбу?
  final bool withDiagrams;

  const SrsConfig({
    required this.subject,
    required this.language,
    required this.pageCount,
    required this.topic,
    this.documentText,
    this.withDiagrams = true,
    this.handwriting,
    this.handProfile,
  });

  String get subjectName => subject.nameIn(language);

  Map<String, dynamic> toJson() => {
        'subject': subject.name,
        'language': language.name,
        'pageCount': pageCount.name,
        'topic': topic,
        'withDiagrams': withDiagrams,
        'handwriting': handwriting?.id,
        if (handProfile != null) 'handProfile': handProfile,
      };

  factory SrsConfig.fromJson(Map<String, dynamic> j) => SrsConfig(
        subject: Subject.values.firstWhere(
          (e) => e.name == j['subject'],
          orElse: () => Subject.physics,
        ),
        language: Language.values.firstWhere(
          (e) => e.name == j['language'],
          orElse: () => Language.kyrgyz,
        ),
        pageCount: PageCount.values.firstWhere(
          (e) => e.name == j['pageCount'],
          orElse: () => PageCount.ten,
        ),
        topic: (j['topic'] ?? '') as String,
        withDiagrams: (j['withDiagrams'] ?? true) as bool,
        handwriting: HandwritingStyle.fromId(j['handwriting'] as String?),
        handProfile: j['handProfile'] as String?,
      );
}
