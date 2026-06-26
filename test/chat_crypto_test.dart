import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/chats/crypto/chat_crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('encrypts messages so sender and recipient can read them', () async {
    SharedPreferences.setMockInitialValues({});
    const alice = ChatCryptoService(keyNamespace: 'alice');
    const bob = ChatCryptoService(keyNamespace: 'bob');
    const conversationId = 'conversation-1';

    final bobPublicKey = await bob.ensurePublicKey();
    final encrypted = await alice.encryptFor(
      conversationId: conversationId,
      recipientPublicKey: bobPublicKey,
      message: 'hi bob',
    );

    final bobText = await bob.decrypt(
      conversationId: conversationId,
      encryptedPayload: encrypted.value,
    );
    final aliceText = await alice.decrypt(
      conversationId: conversationId,
      encryptedPayload: encrypted.value,
      remotePublicKey: bobPublicKey,
    );

    expect(bobText, 'hi bob');
    expect(aliceText, 'hi bob');
    expect(encrypted.value['ciphertext'], isNot(contains('hi bob')));
  });
}
