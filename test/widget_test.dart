import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders app shell and home content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LumiiQuestApp());
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Discover'), findsAtLeastNWidgets(1));
    expect(
      find.text('Discover for Tablet/Desktop Is In Progress'),
      findsOneWidget,
    );
  });

  testWidgets('applies the saved color mode to the full app theme', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'system_color_mode': 'hellaverse'});

    await tester.pumpWidget(const LumiiQuestApp());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(scaffoldContext);

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFFF90142));
    expect(theme.cardTheme.color, const Color(0xFF1B1B1F));
  });
}
