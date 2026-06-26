import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/friends/domain/friend_summary.dart';

void main() {
  test('sorts friends by username ascending and descending', () {
    final friends = [
      FriendSummary(
        id: '1',
        username: 'zara',
        displayName: 'A',
        friendSince: DateTime(2026),
      ),
      FriendSummary(
        id: '2',
        username: 'ana',
        displayName: 'Z',
        friendSince: DateTime(2026),
      ),
    ];

    expect(
      sortFriends(
        friends,
        field: FriendSortField.username,
        direction: FriendSortDirection.ascending,
      ).map((friend) => friend.username),
      ['ana', 'zara'],
    );
    expect(
      sortFriends(
        friends,
        field: FriendSortField.username,
        direction: FriendSortDirection.descending,
      ).map((friend) => friend.username),
      ['zara', 'ana'],
    );
  });

  test('sorts friends by display name', () {
    final friends = [
      FriendSummary(
        id: '1',
        username: 'one',
        displayName: 'Mina',
        friendSince: DateTime(2026),
      ),
      FriendSummary(
        id: '2',
        username: 'two',
        displayName: 'Lena',
        friendSince: DateTime(2026),
      ),
    ];

    expect(
      sortFriends(
        friends,
        field: FriendSortField.displayName,
        direction: FriendSortDirection.ascending,
      ).map((friend) => friend.displayName),
      ['Lena', 'Mina'],
    );
  });
}
