import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/notifications/domain/notification_item.dart';

void main() {
  final items = [
    NotificationItem(
      id: 1,
      title: 'First',
      body: '',
      createdAt: DateTime(2026, 6, 20, 23, 59),
      isRead: false,
    ),
    NotificationItem(
      id: 2,
      title: 'Second',
      body: '',
      createdAt: DateTime(2026, 6, 21, 12),
      isRead: true,
    ),
  ];

  test('filters notifications with an exclusive end date', () {
    final result = filterNotificationItems(
      items,
      start: DateTime(2026, 6, 21),
      end: DateTime(2026, 6, 22),
    );

    expect(result.map((item) => item.id), [2]);
  });

  test('formats notification dates as dd/mm/yyyy', () {
    expect(formatNotificationDate(DateTime(2026, 6, 5)), '05/06/2026');
  });
}
