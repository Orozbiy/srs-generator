import 'package:flutter/material.dart';

import '../models/srs_config.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import '../widgets/option_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  final _student = TextEditingController();
  final _teacher = TextEditingController();
  final _group = TextEditingController();
  final _university = TextEditingController();
  final _faculty = TextEditingController();
  final _department = TextEditingController();
  final _universityKy = TextEditingController();
  final _facultyKy = TextEditingController();
  final _departmentKy = TextEditingController();
  bool _studentFemale = false;
  bool _teacherFemale = false;
  bool _fullTitle = false;

  bool _obscure = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await PrefsService.apiKey();
    final a = await PrefsService.author();
    if (!mounted) return;
    setState(() {
      _key.text = key;
      _student.text = a.student;
      _teacher.text = a.teacher;
      _group.text = a.group;
      _university.text = a.university;
      _faculty.text = a.faculty;
      _department.text = a.department;
      _universityKy.text = a.universityKy;
      _facultyKy.text = a.facultyKy;
      _departmentKy.text = a.departmentKy;
      _studentFemale = a.studentFemale;
      _teacherFemale = a.teacherFemale;
      _fullTitle = a.fullTitle;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await PrefsService.setApiKey(_key.text);
    await PrefsService.setAuthor(AuthorInfo(
      student: _student.text,
      teacher: _teacher.text,
      group: _group.text,
      university: _university.text,
      faculty: _faculty.text,
      department: _department.text,
      universityKy: _universityKy.text,
      facultyKy: _facultyKy.text,
      departmentKy: _departmentKy.text,
      studentFemale: _studentFemale,
      teacherFemale: _teacherFemale,
      fullTitle: _fullTitle,
    ));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (final c in [
      _key,
      _student,
      _teacher,
      _group,
      _university,
      _faculty,
      _department,
      _universityKy,
      _facultyKy,
      _departmentKy
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Жөндөөлөр'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Сактоо'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    _card(
                      Icons.key_rounded,
                      'API ачкыч',
                      'Groq бекер ачкычы: console.groq.com/keys',
                      [
                        TextField(
                          controller: _key,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Groq API Key',
                            hintText: 'gsk_...',
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _card(
                      Icons.person_outline,
                      'Студент',
                      'Титул бетке жазылат',
                      [
                        TextField(
                          controller: _student,
                          decoration: const InputDecoration(
                            labelText: 'Аты-жөнү',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _group,
                                decoration: const InputDecoration(
                                  labelText: 'Топ / Группа',
                                  prefixIcon: Icon(Icons.groups_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _teacher,
                                decoration: const InputDecoration(
                                  labelText: 'Окутуучу',
                                  prefixIcon: Icon(Icons.school_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Студент кыз (Выполнила)'),
                          value: _studentFemale,
                          onChanged: (v) => setState(() => _studentFemale = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Окутуучу аял (Проверила)'),
                          value: _teacherFemale,
                          onChanged: (v) => setState(() => _teacherFemale = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _card(
                      Icons.account_balance_outlined,
                      'Окуу жай',
                      'СРС орусча болсо орусча, кыргызча болсо кыргызча аталыш чыгат',
                      [
                        const Text('Титул түрү',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: false,
                                label: Text('1. Кыска'),
                                icon: Icon(Icons.article_outlined)),
                            ButtonSegment(
                                value: true,
                                label: Text('2. Толук'),
                                icon: Icon(Icons.account_tree_outlined)),
                          ],
                          selected: {_fullTitle},
                          onSelectionChanged: (v) =>
                              setState(() => _fullTitle = v.first),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 14),
                          child: Text(
                            'Кыска: министрлик + университет. '
                            'Толук: + институт/факультет жана кафедра.',
                            style: TextStyle(
                                fontSize: 12.5, color: AppTheme.muted),
                          ),
                        ),
                        TextField(
                          controller: _university,
                          decoration: const InputDecoration(
                            labelText: 'Университет (орусча)',
                            hintText:
                                'Кыргызский национальный университет имени Ж. Баласагына',
                            prefixIcon: Icon(Icons.apartment_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _universityKy,
                          decoration: const InputDecoration(
                            labelText: 'Университет (кыргызча)',
                            hintText: 'Ж. Баласагын атындагы Кыргыз улуттук университети',
                            prefixIcon: Icon(Icons.apartment_outlined),
                          ),
                        ),
                        if (_fullTitle) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _faculty,
                            decoration: const InputDecoration(
                              labelText: 'Институт / Факультет (орусча)',
                              prefixIcon: Icon(Icons.hub_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _facultyKy,
                            decoration: const InputDecoration(
                              labelText: 'Институт / Факультет (кыргызча)',
                              prefixIcon: Icon(Icons.hub_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _department,
                            decoration: const InputDecoration(
                              labelText: 'Кафедра (орусча)',
                              prefixIcon: Icon(Icons.topic_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _departmentKy,
                            decoration: const InputDecoration(
                              labelText: 'Кафедра (кыргызча)',
                              prefixIcon: Icon(Icons.topic_outlined),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card(
      IconData icon, String title, String subtitle, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
        boxShadow: AppTheme.shadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(icon, title),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(subtitle,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.muted)),
          ),
          ...children,
        ],
      ),
    );
  }
}
