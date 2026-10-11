import 'package:flutter/material.dart';

import 'screens/intro_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SrsApp());
}

class SrsApp extends StatelessWidget {
  const SrsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'СРС Генератор',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const IntroScreen(),
    );
  }
}
