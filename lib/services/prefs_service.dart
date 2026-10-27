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
  static const _kUniversityKy = 'universityKy';
  static const _kFacultyKy = 'facultyKy';
  static const _kDepartmentKy = 'departmentKy';
  static const _kStudentFemale = 'studentFemale';
  static const _kTeacherFemale = 'teacherFemale';
  static const _kFullTitle = 'fullTitle';
  static const _kSubject = 'lastSubject';
  static const _kLanguage = 'lastLanguage';
  static const _kPages = 'lastPages';
  static const _kDiagrams = 'withDiagrams';
  static const _kTitlePage = 'withTitlePage';
  static const _kCustomSubjects = 'customSubjects';
  static const _kLastCustom = 'lastCustomSubject';

  static Future<List<String>> customSubjects() async =>
      (await SharedPreferences.getInstance())
          .getStringList(_kCustomSubjects) ??
      <String>[];

  static Future<void> setCustomSubjects(List<String> v) async =>
      (await SharedPreferences.getInstance())
          .setStringList(_kCustomSubjects, v);

  static Future<String> lastCustom() async =>
      (await SharedPreferences.getInstance()).getString(_kLastCustom) ?? '';

  static Future<void> setLastCustom(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kLastCustom, v);

  static Future<bool> withTitlePage() async =>
      (await SharedPreferences.getInstance()).getBool(_kTitlePage) ?? true;

  static Future<void> setWithTitlePage(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kTitlePage, v);

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
      universityKy: p.getString(_kUniversityKy) ?? '',
      facultyKy: p.getString(_kFacultyKy) ?? '',
      departmentKy: p.getString(_kDepartmentKy) ?? '',
      studentFemale: p.getBool(_kStudentFemale) ?? false,
      teacherFemale: p.getBool(_kTeacherFemale) ?? false,
      fullTitle: p.getBool(_kFullTitle) ?? false,
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
    await p.setString(_kUniversityKy, a.universityKy.trim());
    await p.setString(_kFacultyKy, a.facultyKy.trim());
    await p.setString(_kDepartmentKy, a.departmentKy.trim());
    await p.setBool(_kStudentFemale, a.studentFemale);
    await p.setBool(_kTeacherFemale, a.teacherFemale);
    await p.setBool(_kFullTitle, a.fullTitle);
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
