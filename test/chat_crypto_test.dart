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

  test('encrypts one message for multiple devices', () async {
    SharedPreferences.setMockInitialValues({});
    const aliceLaptop = ChatCryptoService(keyNamespace: 'alice_laptop');
    const alicePhone = ChatCryptoService(keyNamespace: 'alice_phone');
    const bobPhone = ChatCryptoService(keyNamespace: 'bob_phone');
    const stranger = ChatCryptoService(keyNamespace: 'stranger');
    const conversationId = 'conversation-2';

    final aliceLaptopIdentity = await aliceLaptop.ensureDeviceIdentity();
    final alicePhoneIdentity = await alicePhone.ensureDeviceIdentity();
    final bobPhoneIdentity = await bobPhone.ensureDeviceIdentity();
    await stranger.ensureDeviceIdentity();

    final encrypted = await aliceLaptop.encryptForDevices(
      conversationId: conversationId,
      senderDeviceId: aliceLaptopIdentity.deviceId,
      recipients: [
        ChatDeviceRecipient(
          deviceId: aliceLaptopIdentity.deviceId,
          publicKey: aliceLaptopIdentity.publicKey,
        ),
        ChatDeviceRecipient(
          deviceId: alicePhoneIdentity.deviceId,
          publicKey: alicePhoneIdentity.publicKey,
        ),
        ChatDeviceRecipient(
          deviceId: bobPhoneIdentity.deviceId,
          publicKey: bobPhoneIdentity.publicKey,
        ),
      ],
      message: 'hi all devices',
    );

    expect(
      await aliceLaptop.decrypt(
        conversationId: conversationId,
        encryptedPayload: encrypted.value,
      ),
      'hi all devices',
    );
    expect(
      await alicePhone.decrypt(
        conversationId: conversationId,
        encryptedPayload: encrypted.value,
      ),
      'hi all devices',
    );
    expect(
      await bobPhone.decrypt(
        conversationId: conversationId,
        encryptedPayload: encrypted.value,
      ),
      'hi all devices',
    );
    await expectLater(
      stranger.decrypt(
        conversationId: conversationId,
        encryptedPayload: encrypted.value,
      ),
      throwsFormatException,
    );
  });
}
