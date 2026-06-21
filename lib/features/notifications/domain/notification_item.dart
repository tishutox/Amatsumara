class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  final int id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
}

List<NotificationItem> filterNotificationItems(
  Iterable<NotificationItem> items, {
  DateTime? start,
  DateTime? end,
}) {
  if (start == null || end == null) return items.toList();
  return items
      .where(
        (item) =>
            !item.createdAt.isBefore(start) && item.createdAt.isBefore(end),
      )
      .toList();
}

String formatNotificationDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
}
