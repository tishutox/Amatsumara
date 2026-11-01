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

    await channel.httpSend(event: 'call', payload: payload);
  }

  Future<void> sendCancel({required String peerUserId}) async {
    final channel = _client.channel(personalChannel(peerUserId));
    await channel.httpSend(
      event: 'call',
      payload: {'kind': 'cancel', 'from': _selfId},
    );
  }

  /// Joins the session channel used for the call exchange.
  Future<CallSession> joinSession(
    String sessionId,
    void Function(Map<String, dynamic> payload) onMessage,
  ) async {
    final channel = _client.channel(
      sessionId,
      opts: const RealtimeChannelConfig(ack: true),
    );
    channel.onBroadcast(event: 'call', callback: onMessage);
    final ready = Completer<void>();
    channel.subscribe((status, error) {
      if (ready.isCompleted) {
        return;
      }
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          ready.complete();
          return;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.timedOut:
          ready.completeError(
            StateError('Could not join call signaling channel: $error'),
          );
          return;
      }
    });

    try {
      await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException('Timed out joining call signaling channel.'),
      );
      return CallSession._(channel);
    } catch (_) {
      await channel.unsubscribe();
      rethrow;
    }
  }
}

class CallSession {
  CallSession._(this._channel);

  final RealtimeChannel _channel;

  Future<void> send(Map<String, dynamic> payload) async {
    final response = await _channel.sendBroadcastMessage(
      event: 'call',
      payload: payload,
    );
    if (response != ChannelResponse.ok) {
      throw StateError('Call signaling message was not delivered: $response');
    }
  }

  void dispose() {
    unawaited(_channel.unsubscribe());
  }
}
