import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// WebRTC call signaling over Supabase Realtime broadcast channels.
///
/// Design:
/// - Each user keeps a persistent subscription to their personal channel
///   (`lumii-call:<userId>`) to detect incoming `ring` events.
/// - Once a call is accepted, both peers join a deterministic session channel
///   (`lumii-call-session:<minId>:<maxId>`) and exchange offer/answer/ice/
///   hangup there (low-latency WebSocket broadcast).
class CallSignaling {
  CallSignaling({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _selfId => _client.auth.currentUser?.id;

  static String personalChannel(String userId) => 'lumii-call:$userId';

  static String sessionChannel(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return 'lumii-call-session:${ids[0]}:${ids[1]}';
  }

  /// Listens on a user's personal channel for incoming `ring` events.
  RealtimeChannel subscribeIncoming(
    String userId,
    void Function(Map<String, dynamic> payload) onRing,
  ) {
    final channel = _client.channel(personalChannel(userId));
    channel.onBroadcast(event: 'call', callback: onRing);
    channel.subscribe();
    return channel;
  }

  /// Announces a call to the peer's personal channel.
  Future<void> sendRing({
    required String peerUserId,
    required String callerName,
    String? callerAvatarUrl,
    bool isVideoCall = false,
  }) async {
    final channel = _client.channel(personalChannel(peerUserId));
    final payload = <String, dynamic>{
      'kind': 'ring',
      'from': _selfId,
      'name': callerName,
      'avatarUrl': callerAvatarUrl,
      'video': isVideoCall,
    };

    // Subscribe over WebSocket first so the ring is delivered reliably to the
    // peer's live subscription, falling back to REST only if that fails.
    final ready = Completer<void>();
    channel.subscribe((status, [error]) {
      if (!ready.isCompleted) {
        ready.complete();
      }
    });
    try {
      await ready.future.timeout(const Duration(seconds: 6));
      await channel.sendBroadcastMessage(event: 'call', payload: payload);
    } catch (_) {
      await channel.sendBroadcastMessage(event: 'call', payload: payload);
    } finally {
      await channel.unsubscribe();
    }
  }

  /// Joins the session channel used for the call exchange.
  CallSession joinSession(
    String sessionId,
    void Function(Map<String, dynamic> payload) onMessage,
  ) {
    final channel = _client.channel(sessionId);
    channel.onBroadcast(event: 'call', callback: onMessage);
    channel.subscribe();
    return CallSession._(channel);
  }
}

class CallSession {
  CallSession._(this._channel);

  final RealtimeChannel _channel;

  Future<void> send(Map<String, dynamic> payload) {
    return _channel.sendBroadcastMessage(event: 'call', payload: payload);
  }

  void dispose() {
    _channel.unsubscribe();
  }
}
