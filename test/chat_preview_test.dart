import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';

void main() {
  test('hydrates chat previews from Supabase rows', () {
    final preview = ChatPreview.fromDatabase({
      'conversation_id': 'conversation-1',
      'friend_id': 'friend-1',
      'username': 'tishu',
      'display_name': 'Tishu',
      'avatar_url': null,
      'last_message_at': '2026-06-23T10:20:30.000Z',
    });

    expect(preview.conversationId, 'conversation-1');
    expect(preview.friendId, 'friend-1');
    expect(preview.username, 'tishu');
    expect(preview.displayName, 'Tishu');
    expect(preview.lastMessageAt, isNotNull);
  });
}
