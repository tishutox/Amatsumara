import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lumii_quest/features/calls/data/call_signaling.dart';
import 'package:lumii_quest/features/chats/data/chat_repository.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _CallPhase {
  idle,
  calling,
  ringing,
  connecting,
  connected,
  ended,
  error,
}

class CallPage extends StatefulWidget {
  const CallPage({
    required this.friendId,
    required this.displayName,
    this.incoming = false,
    this.avatarUrl,
    this.isVideoCall = false,
    super.key,
  });

  final String friendId;
  final String displayName;
  final bool incoming;
  final String? avatarUrl;
  final bool isVideoCall;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _signaling = CallSignaling();
  final _repository = ChatRepository();

  String? _avatarUrl;
  _CallPhase _phase = _CallPhase.idle;
  String _statusMessage = '';

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  CallSession? _session;
  bool _muted = false;
  bool _headphonesOff = false;
  bool _speakerOn = false;
  bool _videoOn = false;
  bool _overlayShown = false;
  bool _remoteDescriptionSet = false;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];

  static const _overlayChannel = MethodChannel('lumii/call_overlay');

  String get _selfId => Supabase.instance.client.auth.currentUser?.id ?? '';
  String get _sessionId =>
      CallSignaling.sessionChannel(_selfId, widget.friendId);

  @override
  void initState() {
    super.initState();
    _videoOn = widget.isVideoCall;
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
      _avatarUrl = widget.avatarUrl;
      if (_avatarUrl == null || _avatarUrl!.isEmpty) {
        final profile = await _repository.fetchFriendProfile(widget.friendId);
        if (mounted && profile != null) {
          _avatarUrl = profile['avatar_url'] as String?;
        }
      }
      if (!mounted) return;
      if (widget.incoming) {
        setState(() {
          _phase = _CallPhase.ringing;
          _statusMessage = 'Incoming call';
        });
      } else {
        await _startOutgoing();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _CallPhase.error;
          _statusMessage = 'Call failed: $error';
        });
      }
    }
  }

  Future<void> _startOutgoing() async {
    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.calling;
      _statusMessage = 'Calling...';
    });
    _session = _signaling.joinSession(_sessionId, _onMessage);
    await _signaling.sendRing(
      peerUserId: widget.friendId,
      callerName: _myDisplayName(),
      isVideoCall: widget.isVideoCall,
    );
  }

  String _myDisplayName() {
    final value =
        Supabase.instance.client.auth.currentUser?.userMetadata?['display_name'];
    return value is String && value.isNotEmpty ? value : 'Lumii user';
  }

  void _onMessage(Map<String, dynamic> payload) {
    final type = payload['kind'] as String?;
    switch (type) {
      case 'ready':
        unawaited(_onReady());
      case 'offer':
        unawaited(_onOffer(payload));
      case 'answer':
        unawaited(_onAnswer(payload));
      case 'ice':
        unawaited(_onIce(payload));
      case 'hangup':
        unawaited(_finish('Call ended.'));
      case 'decline':
        unawaited(_finish('Call declined.'));
    }
  }

  Future<void> _onReady() async {
    try {
      await _setupPeerConnection();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _session!.send({
        'kind': 'offer',
        'from': _selfId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      if (mounted) {
        setState(() {
          _phase = _CallPhase.connecting;
          _statusMessage = 'Connecting...';
        });
      }
    } catch (error) {
      _fail('Call setup failed: $error');
    }
  }

  Future<void> _onOffer(Map<String, dynamic> payload) async {
    try {
      if (_pc == null) {
        await _setupPeerConnection();
      }
      final sdp = payload['sdp'] as Map<String, dynamic>;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _session!.send({
        'kind': 'answer',
        'from': _selfId,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      if (mounted) {
        setState(() {
          _phase = _CallPhase.connecting;
          _statusMessage = 'Connecting...';
        });
      }
    } catch (error) {
      _fail('Call setup failed: $error');
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> payload) async {
    try {
      final sdp = payload['sdp'] as Map<String, dynamic>;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();
    } catch (error) {
      _fail('Call setup failed: $error');
    }
  }

  Future<void> _onIce(Map<String, dynamic> payload) async {
    final candidate = payload['candidate'] as Map<String, dynamic>?;
    if (candidate == null) {
      return;
    }
    final pc = _pc;
    if (pc == null || !_remoteDescriptionSet) {
      // Queue the candidate until the remote description has been set.
      _pendingIceCandidates.add(candidate);
      return;
    }
    await _addIceCandidate(pc, candidate);
  }

  Future<void> _addIceCandidate(
    RTCPeerConnection pc,
    Map<String, dynamic> candidate,
  ) async {
    try {
      await pc.addCandidate(
        RTCIceCandidate(
          candidate['candidate'] as String?,
          candidate['sdpMid'] as String?,
          candidate['sdpMLineIndex'] as int?,
        ),
      );
    } catch (_) {
      // ICE failures are non-fatal and can be ignored.
    }
  }

  Future<void> _flushPendingIce() async {
    final pc = _pc;
    if (pc == null || _pendingIceCandidates.isEmpty) {
      return;
    }
    final pending = List.of(_pendingIceCandidates);
    _pendingIceCandidates.clear();
    for (final candidate in pending) {
      await _addIceCandidate(pc, candidate);
    }
  }

  Future<void> _setupPeerConnection() async {
    _remoteDescriptionSet = false;
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {
          'urls': [
            'turn:openrelay.metered.ca:80',
            'turn:openrelay.metered.ca:443',
            'turn:openrelay.metered.ca:443?transport=tcp',
          ],
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
    });

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) {
        return;
      }
      _session?.send({
        'kind': 'ice',
        'from': _selfId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted) {
          setState(() {
            _phase = _CallPhase.connected;
            _statusMessage = 'Connected';
          });
        }
        unawaited(_showCallOverlay());
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_phase == _CallPhase.connected ||
            _phase == _CallPhase.connecting) {
          unawaited(_finish('Call ended.'));
        }
      }
    };

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall,
    });
    for (final track in stream.getTracks()) {
      if (track.kind == 'audio') {
        track.enabled = !_muted;
      }
      await _pc!.addTrack(track, stream);
    }
    _localStream = stream;
    _localRenderer.srcObject = stream;
  }

  Future<void> _accept() async {
    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.connecting;
      _statusMessage = 'Connecting...';
    });
    _session = _signaling.joinSession(_sessionId, _onMessage);
    await _session!.send({'kind': 'ready', 'from': _selfId});
  }

  Future<void> _decline() async {
    final session = _signaling.joinSession(_sessionId, _onMessage);
    try {
      await session.send({'kind': 'decline', 'from': _selfId});
    } finally {
      session.dispose();
    }
    await _finish('Call declined.');
  }

  Future<void> _hangup() async {
    try {
      await _session?.send({'kind': 'hangup', 'from': _selfId});
    } catch (_) {
      // Ignore signaling errors on hangup.
    }
    await _finish('Call ended.');
  }

  Future<void> _fail(String message) async {
    if (mounted) {
      setState(() {
        _phase = _CallPhase.error;
        _statusMessage = message;
      });
    }
    await _cleanup();
  }

  Future<void> _finish(String message) async {
    await _cleanup();
    if (mounted) {
      setState(() {
        _phase = _CallPhase.ended;
        _statusMessage = message;
      });
    }
    // Give the user a moment to see the state, then leave the call screen.
    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _cleanup() async {
    await _hideCallOverlay();

    final session = _session;
    _session = null;
    session?.dispose();

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await track.stop();
      }
      await localStream.dispose();
    }

    final pc = _pc;
    _pc = null;
    await pc?.close();

    _remoteRenderer.srcObject = null;
    _localRenderer.srcObject = null;
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final tracks = _localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      tracks.first.enabled = !_muted;
    }
  }

  Future<void> _toggleVideo() async {
    final localStream = _localStream;
    if (localStream == null) {
      return;
    }
    final newState = !_videoOn;
    for (final track in localStream.getVideoTracks()) {
      track.enabled = newState;
    }
    setState(() => _videoOn = newState);
  }

  Future<void> _toggleHeadphones() async {
    setState(() => _headphonesOff = !_headphonesOff);
    _remoteRenderer.muted = _headphonesOff;
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {
      // Speakerphone is Android-only; other platforms are a no-op.
    }
  }

  Future<void> _showCallOverlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_overlayShown) {
      return;
    }
    try {
      final granted =
          await _overlayChannel.invokeMethod<bool>('isOverlayGranted') ?? false;
      if (!granted) {
        await _overlayChannel.invokeMethod('requestOverlayPermission');
        return;
      }
      await _overlayChannel.invokeMethod('show', {
        'avatarUrl': _avatarUrl ?? '',
        'name': widget.displayName,
      });
      _overlayShown = true;
    } catch (_) {
      // The overlay is best-effort; ignore failures on unsupported devices.
    }
  }

  Future<void> _hideCallOverlay() async {
    if (!_overlayShown) {
      return;
    }
    _overlayShown = false;
    try {
      await _overlayChannel.invokeMethod('hide');
    } catch (_) {
      // Ignore.
    }
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    unawaited(_remoteRenderer.dispose());
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final background = const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _videoOn
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : _buildProfileHeader(primary),
            ),
            if (_videoOn)
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 120,
                    height: 160,
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),
              ),
            if (!_videoOn)
              Opacity(
                opacity: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: RTCVideoView(_remoteRenderer, mirror: false),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: _buildControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Color primary) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 64,
          backgroundColor: primary.withValues(alpha: 0.14),
          backgroundImage: (_avatarUrl == null || _avatarUrl!.isEmpty)
              ? null
              : NetworkImage(_avatarUrl!),
          child: (_avatarUrl == null || _avatarUrl!.isEmpty)
              ? Text(
                  widget.displayName.trim().isEmpty
                      ? '?'
                      : widget.displayName.trim().characters.first
                            .toUpperCase(),
                  style: TextStyle(fontSize: 44, color: primary),
                )
              : null,
        ),
        const SizedBox(height: 20),
        Text(
          widget.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildControls() {
    switch (_phase) {
      case _CallPhase.ringing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CircleControl(
              tooltip: 'Decline',
              icon: AppIcons.phone,
              rotateIcon: true,
              backgroundColor: const Color(0xFFE53935),
              onTap: _decline,
            ),
            const SizedBox(width: 48),
            _CircleControl(
              tooltip: 'Accept',
              icon: AppIcons.phone,
              backgroundColor: const Color(0xFF43A047),
              onTap: _accept,
            ),
          ],
        );
      default:
        return _CallControlsBar(
          showVideo: widget.isVideoCall,
          videoOn: _videoOn,
          muted: _muted,
          headphonesOff: _headphonesOff,
          speakerOn: _speakerOn,
          onToggleVideo: _toggleVideo,
          onToggleMute: _toggleMute,
          onToggleHeadphones: _toggleHeadphones,
          onToggleSpeaker: _toggleSpeaker,
          onHangup: _hangup,
        );
    }
  }
}

class _CallControlsBar extends StatelessWidget {
  const _CallControlsBar({
    required this.showVideo,
    required this.videoOn,
    required this.muted,
    required this.headphonesOff,
    required this.speakerOn,
    required this.onToggleVideo,
    required this.onToggleMute,
    required this.onToggleHeadphones,
    required this.onToggleSpeaker,
    required this.onHangup,
  });

  final bool showVideo;
  final bool videoOn;
  final bool muted;
  final bool headphonesOff;
  final bool speakerOn;
  final VoidCallback onToggleVideo;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (showVideo)
            _CircleControl(
              tooltip: videoOn ? 'Turn video off' : 'Turn video on',
              icon: videoOn ? AppIcons.video : AppIcons.videoOff,
              active: !videoOn,
              size: 46,
              onTap: onToggleVideo,
            ),
          _CircleControl(
            tooltip: muted ? 'Unmute' : 'Mute',
            icon: muted ? AppIcons.micOff : AppIcons.mic,
            active: muted,
            size: 46,
            onTap: onToggleMute,
          ),
          _CircleControl(
            tooltip: headphonesOff ? 'Headphones on' : 'Headphones off',
            icon: headphonesOff
                ? AppIcons.headphoneOff
                : AppIcons.headphones,
            active: headphonesOff,
            size: 46,
            onTap: onToggleHeadphones,
          ),
          _CircleControl(
            tooltip: speakerOn ? 'Speaker off' : 'Speaker on',
            icon: speakerOn ? AppIcons.volumeOff : AppIcons.volume2,
            active: speakerOn,
            size: 46,
            onTap: onToggleSpeaker,
          ),
          _CircleControl(
            tooltip: 'End call',
            icon: AppIcons.phone,
            rotateIcon: true,
            backgroundColor: const Color(0xFFE53935),
            size: 46,
            onTap: onHangup,
          ),
        ],
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.tooltip,
    required this.icon,
    this.active = false,
    this.backgroundColor = Colors.transparent,
    this.size = 60,
    this.rotateIcon = false,
    this.onTap,
  });

  final String tooltip;
  final String icon;
  final bool active;
  final Color backgroundColor;
  final double size;
  final bool rotateIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.error;
    final effectiveIconColor = active
        ? activeColor
        : (backgroundColor == Colors.transparent ? Colors.black : Colors.white);

    final iconWidget = rotateIcon
        ? Transform.rotate(
            angle: math.pi * 3 / 4,
            child: AppIcon(icon, color: effectiveIconColor, size: size * 0.42),
          )
        : AppIcon(icon, color: effectiveIconColor, size: size * 0.42);

    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: active
                  ? Border.all(color: activeColor, width: 2)
                  : null,
            ),
            child: Center(child: iconWidget),
          ),
        ),
      ),
    );
  }
}
