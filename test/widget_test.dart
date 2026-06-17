import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/app/app.dart';

void main() {
  testWidgets('renders app shell and home content', (WidgetTester tester) async {
    await tester.pumpWidget(const LumiiQuestApp());
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Discover'), findsAtLeastNWidgets(1));
    expect(find.text('Discover for Tablet/Desktop Is In Progress'), findsOneWidget);
  });
}
