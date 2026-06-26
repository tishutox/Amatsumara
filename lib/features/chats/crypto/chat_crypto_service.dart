import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatCryptoService {
  const ChatCryptoService();

  static const _localDeviceKey = 'lumii.chat.localDeviceSecret.v1';

  Future<String> ensureLocalDeviceSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_localDeviceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final encoded = base64UrlEncode(bytes);
    await prefs.setString(_localDeviceKey, encoded);
    return encoded;
  }

  Future<String> encryptPreviewForLocalDevice(String plainText) async {
    final secret = await ensureLocalDeviceSecret();
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(base64Url.decode(secret));
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
    );
    return jsonEncode({
      'v': 1,
      'alg': 'A256GCM',
      'nonce': base64UrlEncode(box.nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }
}
