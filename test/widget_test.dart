import 'package:flutter_test/flutter_test.dart';
import 'package:friendship/app/app.dart';

void main() {
  testWidgets('renders app shell and home content', (WidgetTester tester) async {
    await tester.pumpWidget(const FriendshipApp());

    expect(find.text('Start'), findsAtLeastNWidgets(1));
    expect(find.text('Willkommen bei Friendship'), findsOneWidget);
  });
}
