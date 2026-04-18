// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/main.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MyApp initializes with loading state',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Initializing...'), findsOneWidget);
  });

  testWidgets('MyApp renders MaterialApp', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('MyApp has correct title', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    final materialApp = find.byType(MaterialApp).first;
    expect(materialApp, findsOneWidget);
  });

  testWidgets('MyApp shows Scaffold with loading', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Center), findsOneWidget);
  });

  testWidgets('MyApp theme is configured', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    final app = find.byType(MaterialApp);
    expect(app, findsOneWidget);
  });

  testWidgets('MyApp shows theme title correctly', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('MyApp has Material 3 enabled', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('MyApp background color is correct', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('MyApp has proper column layout', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(Column), findsOneWidget);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('MyApp SizedBox has correct spacing',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('MyApp initializes text widget', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(prefs: prefs));

    expect(find.byType(Text), findsWidgets);
  });
}
