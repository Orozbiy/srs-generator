import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srs_generator/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Башкы бет ачылат', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SrsApp());
    await tester.pumpAndSettle();

    expect(find.text('СРС Генератор'), findsWidgets);
    expect(find.text('Физика'), findsOneWidget);
    expect(find.text('Информатика'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Менин СРСтерим'), findsOneWidget);
    expect(find.text('СРС Жасоо'), findsOneWidget);
  });

  testWidgets('Тема бош болсо эскертүү чыгат', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SrsApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('СРС Жасоо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('СРС Жасоо'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Тема киргизиңиз'), findsOneWidget);
  });
}
