import 'package:shared_preferences/shared_preferences.dart';

import '../models/srs_config.dart';

/// Жөндөөлөрдү жана автордун маалыматын сактайт.
class PrefsService {
  static const _kApiKey = 'apiKey';
  static const _kStudent = 'student';
  static const _kTeacher = 'teacher';
  static const _kGroup = 'group';
  static const _kUniversity = 'university';
  static const _kFaculty = 'faculty';
  static const _kDepartment = 'department';
  static const _kSubject = 'lastSubject';
  static const _kLanguage = 'lastLanguage';
  static const _kPages = 'lastPages';
  static const _kDiagrams = 'withDiagrams';

  static Future<String> apiKey() async =>
      (await SharedPreferences.getInstance()).getString(_kApiKey) ?? '';

  static Future<void> setApiKey(String value) async =>
      (await SharedPreferences.getInstance()).setString(_kApiKey, value.trim());

  static Future<AuthorInfo> author() async {
    final p = await SharedPreferences.getInstance();
    return AuthorInfo(
      student: p.getString(_kStudent) ?? '',
      teacher: p.getString(_kTeacher) ?? '',
      group: p.getString(_kGroup) ?? '',
      university: p.getString(_kUniversity) ?? '',
      faculty: p.getString(_kFaculty) ?? '',
      department: p.getString(_kDepartment) ?? '',
    );
  }

  static Future<void> setAuthor(AuthorInfo a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kStudent, a.student.trim());
    await p.setString(_kTeacher, a.teacher.trim());
    await p.setString(_kGroup, a.group.trim());
    await p.setString(_kUniversity, a.university.trim());
    await p.setString(_kFaculty, a.faculty.trim());
    await p.setString(_kDepartment, a.department.trim());
  }

  static Future<(Subject, Language, PageCount, bool)> lastChoice() async {
    final p = await SharedPreferences.getInstance();
    Subject subject = Subject.values.firstWhere(
      (e) => e.name == p.getString(_kSubject),
      orElse: () => Subject.physics,
    );
    Language language = Language.values.firstWhere(
      (e) => e.name == p.getString(_kLanguage),
      orElse: () => Language.kyrgyz,
    );
    PageCount pages = PageCount.values.firstWhere(
      (e) => e.name == p.getString(_kPages),
      orElse: () => PageCount.ten,
    );
    return (subject, language, pages, p.getBool(_kDiagrams) ?? true);
  }

  static Future<void> setLastChoice(
      Subject s, Language l, PageCount pc, bool diagrams) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSubject, s.name);
    await p.setString(_kLanguage, l.name);
    await p.setString(_kPages, pc.name);
    await p.setBool(_kDiagrams, diagrams);
  }
}
