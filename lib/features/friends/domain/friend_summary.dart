class FriendSummary {
  const FriendSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.friendSince,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final DateTime friendSince;
  final String? avatarUrl;

  factory FriendSummary.fromDatabase(Map<String, dynamic> row) {
    return FriendSummary(
      id: row['id'] as String,
      username: row['username'] as String? ?? '',
      displayName: row['display_name'] as String? ?? 'Amatsumara member',
      avatarUrl: row['avatar_url'] as String?,
      friendSince:
          DateTime.tryParse(row['friend_since'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

enum FriendSortField {
  username('Username'),
  displayName('Display name');

  const FriendSortField(this.label);

  final String label;
}

enum FriendSortDirection {
  ascending('A Ã¢â€ â€™ Z'),
  descending('Z Ã¢â€ â€™ A');

  const FriendSortDirection(this.label);

  final String label;
}

List<FriendSummary> sortFriends(
  Iterable<FriendSummary> friends, {
  required FriendSortField field,
  required FriendSortDirection direction,
}) {
  final sorted = friends.toList();
  sorted.sort((a, b) {
    final left = switch (field) {
      FriendSortField.username => a.username,
      FriendSortField.displayName => a.displayName,
    };
    final right = switch (field) {
      FriendSortField.username => b.username,
      FriendSortField.displayName => b.displayName,
    };
    final result = left.toLowerCase().compareTo(right.toLowerCase());
    return direction == FriendSortDirection.ascending ? result : -result;
  });
  return sorted;
}
