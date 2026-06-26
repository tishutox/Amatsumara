import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatDeviceIdentity {
  const ChatDeviceIdentity({
    required this.deviceId,
    required this.publicKey,
    required this.deviceName,
  });

  final String deviceId;
  final String publicKey;
  final String deviceName;
}

class ChatDeviceRecipient {
  const ChatDeviceRecipient({required this.deviceId, required this.publicKey});

  final String deviceId;
  final String publicKey;
}

class EncryptedChatPayload {
  const EncryptedChatPayload(this.value);

  final Map<String, dynamic> value;

  String get senderPublicKey => value['sender_public_key'] as String? ?? '';
}

class ChatCryptoService {
  const ChatCryptoService({String keyNamespace = 'default'})
    : _privateKeyPref = 'lumii.chat.$keyNamespace.x25519PrivateKey.v1',
      _publicKeyPref = 'lumii.chat.$keyNamespace.x25519PublicKey.v1',
      _deviceIdPref = 'lumii.chat.$keyNamespace.deviceId.v1';

  final String _privateKeyPref;
  final String _publicKeyPref;
  final String _deviceIdPref;
  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();

  Future<ChatDeviceIdentity> ensureDeviceIdentity() async {
    final publicKey = await ensurePublicKey();
    final deviceId = await ensureDeviceId();
    return ChatDeviceIdentity(
      deviceId: deviceId,
      publicKey: publicKey,
      deviceName: 'Lumii device ${deviceId.substring(0, 6)}',
    );
  }

  Future<String> ensureDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdPref);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final deviceId = base64UrlEncode(bytes).replaceAll('=', '');
    await prefs.setString(_deviceIdPref, deviceId);
    return deviceId;
  }

  Future<String> ensurePublicKey() async {
    final keyPair = await _ensureKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64UrlEncode(publicKey.bytes);
  }

  Future<EncryptedChatPayload> encryptFor({
    required String conversationId,
    required String recipientPublicKey,
    required String message,
  }) async {
    final ownPublicKey = await ensurePublicKey();
    final sharedSecret = await _sharedSecret(recipientPublicKey);
    final secretBytes = await sharedSecret.extractBytes();
    final messageKey = await _messageKey(secretBytes, conversationId);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(message),
      secretKey: messageKey,
      nonce: nonce,
    );

    return EncryptedChatPayload({
      'v': 1,
      'alg': 'X25519-A256GCM',
      'sender_public_key': ownPublicKey,
      'nonce': base64UrlEncode(box.nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }

  Future<EncryptedChatPayload> encryptForDevices({
    required String conversationId,
    required String senderDeviceId,
    required Iterable<ChatDeviceRecipient> recipients,
    required String message,
  }) async {
    final ownPublicKey = await ensurePublicKey();
    final envelopes = <String, Map<String, String>>{};
    for (final recipient in recipients) {
      final sharedSecret = await _sharedSecret(recipient.publicKey);
      final secretBytes = await sharedSecret.extractBytes();
      final messageKey = await _messageKey(
        secretBytes,
        '$conversationId:${recipient.deviceId}',
      );
      final nonce = _aes.newNonce();
      final box = await _aes.encrypt(
        utf8.encode(message),
        secretKey: messageKey,
        nonce: nonce,
      );
      envelopes[recipient.deviceId] = {
        'nonce': base64UrlEncode(box.nonce),
        'ciphertext': base64UrlEncode(box.cipherText),
        'mac': base64UrlEncode(box.mac.bytes),
      };
    }

    return EncryptedChatPayload({
      'v': 2,
      'alg': 'X25519-A256GCM-MD',
      'sender_device_id': senderDeviceId,
      'sender_public_key': ownPublicKey,
      'envelopes': envelopes,
    });
  }

  Future<String> decrypt({
    required String conversationId,
    required Map<String, dynamic> encryptedPayload,
    String? remotePublicKey,
  }) async {
    if (encryptedPayload['v'] == 2) {
      final deviceId = await ensureDeviceId();
      final envelopes = Map<String, dynamic>.from(
        encryptedPayload['envelopes'] as Map,
      );
      final envelopeValue = envelopes[deviceId];
      if (envelopeValue == null) {
        throw const FormatException(
          'This message was not encrypted for this device.',
        );
      }
      final envelope = Map<String, dynamic>.from(envelopeValue as Map);
      final senderPublicKey = encryptedPayload['sender_public_key'] as String?;
      if (senderPublicKey == null || senderPublicKey.isEmpty) {
        throw const FormatException('Missing sender key.');
      }
      final sharedSecret = await _sharedSecret(senderPublicKey);
      final secretBytes = await sharedSecret.extractBytes();
      final messageKey = await _messageKey(
        secretBytes,
        '$conversationId:$deviceId',
      );
      final clearBytes = await _aes.decrypt(
        SecretBox(
          base64Url.decode(envelope['ciphertext'] as String),
          nonce: base64Url.decode(envelope['nonce'] as String),
          mac: Mac(base64Url.decode(envelope['mac'] as String)),
        ),
        secretKey: messageKey,
      );
      return utf8.decode(clearBytes);
    }

    final publicKey =
        remotePublicKey ?? encryptedPayload['sender_public_key'] as String?;
    if (publicKey == null || publicKey.isEmpty) {
      throw const FormatException('Missing remote key.');
    }

    final sharedSecret = await _sharedSecret(publicKey);
    final secretBytes = await sharedSecret.extractBytes();
    final messageKey = await _messageKey(secretBytes, conversationId);
    final clearBytes = await _aes.decrypt(
      SecretBox(
        base64Url.decode(encryptedPayload['ciphertext'] as String),
        nonce: base64Url.decode(encryptedPayload['nonce'] as String),
        mac: Mac(base64Url.decode(encryptedPayload['mac'] as String)),
      ),
      secretKey: messageKey,
    );
    return utf8.decode(clearBytes);
  }

  Future<SimpleKeyPairData> _ensureKeyPair() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKey = prefs.getString(_privateKeyPref);
    final publicKey = prefs.getString(_publicKeyPref);
    if (privateKey != null &&
        privateKey.isNotEmpty &&
        publicKey != null &&
        publicKey.isNotEmpty) {
      return SimpleKeyPairData(
        base64Url.decode(privateKey),
        publicKey: SimplePublicKey(
          base64Url.decode(publicKey),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    }

    final keyPair = await _x25519.newKeyPair();
    final data = await keyPair.extract();
    final generatedPublicKey = await data.extractPublicKey();
    await prefs.setString(_privateKeyPref, base64UrlEncode(data.bytes));
    await prefs.setString(
      _publicKeyPref,
      base64UrlEncode(generatedPublicKey.bytes),
    );
    return data;
  }

  Future<SecretKey> _sharedSecret(String remotePublicKey) async {
    final keyPair = await _ensureKeyPair();
    return _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        base64Url.decode(remotePublicKey),
        type: KeyPairType.x25519,
      ),
    );
  }

  Future<SecretKey> _messageKey(
    List<int> sharedSecret,
    String conversationId,
  ) async {
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode('Lumii chat v1:$conversationId'),
      secretKey: SecretKey(sharedSecret),
    );
    return SecretKey(mac.bytes);
  }
}
