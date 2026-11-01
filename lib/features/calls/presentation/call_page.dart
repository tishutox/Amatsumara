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

enum _CallPhase { idle, calling, ringing, connecting, connected, ended, error }

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
  bool _speakerOn = false;
  bool _videoOn = false;
  bool _overlayShown = false;
  bool _isEnding = false;
  bool _remoteDescriptionSet = false;
  Timer? _ringTimeout;
  Future<void>? _cleanupFuture;
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
      await _fail('Call failed: $error');
    }
  }

  Future<void> _startOutgoing() async {
    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.calling;
      _statusMessage = 'Calling...';
    });
    final metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    final avatar = metadata['avatar_url'];
    _session = await _signaling.joinSession(_sessionId, _onMessage);
    await _signaling.sendRing(
      peerUserId: widget.friendId,
      callerName: _myDisplayName(),
      callerAvatarUrl: avatar is String ? avatar : null,
      isVideoCall: widget.isVideoCall,
    );
    if (_phase == _CallPhase.calling) {
      _ringTimeout = Timer(
        const Duration(seconds: 45),
        () => unawaited(_finish('No answer.')),
      );
    }
  }

  String _myDisplayName() {
    final value = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['display_name'];
    return value is String && value.isNotEmpty ? value : 'Lumii user';
  }

  void _onMessage(Map<String, dynamic> payload) {
    final type = payload['kind'] as String?;
    if (type == 'ready') {
      _ringTimeout?.cancel();
    }
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
      if (_pc != null) {
        return;
      }
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
      await _fail('Call setup failed: $error');
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
      await _fail('Call setup failed: $error');
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
      await _fail('Call setup failed: $error');
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
    try {
      await _addIceCandidate(pc, candidate);
    } catch (error) {
      await _fail('Could not establish the call connection: $error');
    }
  }

  Future<void> _addIceCandidate(
    RTCPeerConnection pc,
    Map<String, dynamic> candidate,
  ) async {
    await pc.addCandidate(
      RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ),
    );
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Helper.ensureAudioSession();
    }
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

    _pc!.onIceCandidate = (candidate) => unawaited(_sendIce(candidate));

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
        if (_phase == _CallPhase.connected || _phase == _CallPhase.connecting) {
          unawaited(_finish('Call ended.'));
        }
      }
    };

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideoCall
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    });
    _localStream = stream;
    _localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      if (track.kind == 'audio') {
        track.enabled = !_muted;
      } else if (track.kind == 'video') {
        track.enabled = _videoOn;
      }
      await _pc!.addTrack(track, stream);
    }
  }

  Future<void> _sendIce(RTCIceCandidate candidate) async {
    if (candidate.candidate == null || _isEnding) {
      return;
    }
    try {
      await _session?.send({
        'kind': 'ice',
        'from': _selfId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    } catch (error) {
      await _fail('Could not send call connection data: $error');
    }
  }

  Future<void> _accept() async {
    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.connecting;
      _statusMessage = 'Connecting...';
    });
    try {
      _session = await _signaling.joinSession(_sessionId, _onMessage);
      await _session!.send({'kind': 'ready', 'from': _selfId});
    } catch (error) {
      await _fail('Could not accept the call: $error');
    }
  }

  Future<void> _decline() async {
    CallSession? session;
    try {
      session = await _signaling.joinSession(_sessionId, _onMessage);
      await session.send({'kind': 'decline', 'from': _selfId});
    } catch (error) {
      await _fail('Could not decline the call: $error');
      return;
    } finally {
      session?.dispose();
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
    try {
      await _session?.send({'kind': 'hangup', 'from': _selfId});
    } catch (_) {
      // The original failure is more useful than a follow-up signaling error.
    }
    await _cleanup();
  }

  Future<void> _finish(String message) async {
    if (_isEnding) {
      return;
    }
    _isEnding = true;
    if (_phase == _CallPhase.calling) {
      try {
        await _signaling.sendCancel(peerUserId: widget.friendId);
      } catch (_) {
        // The local call still ends if the remote banner cannot be dismissed.
      }
    }
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

  Future<void> _cleanup() => _cleanupFuture ??= _performCleanup();

  Future<void> _performCleanup() async {
    _ringTimeout?.cancel();
    _ringTimeout = null;
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
    final newState = !_videoOn;
    if (localStream != null) {
      for (final track in localStream.getVideoTracks()) {
        track.enabled = newState;
      }
    }
    if (mounted) {
      setState(() => _videoOn = newState);
    }
  }

  Future<void> _chooseAudioOutput() async {
    if (_localStream == null) {
      return;
    }
    try {
      final devices = await Helper.audiooutputs;
      if (!mounted) {
        return;
      }
      if (devices.isEmpty) {
        _showCallMessage('No audio output devices were found.');
        return;
      }
      final deviceId = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final device in devices)
                ListTile(
                  leading: const AppIcon(AppIcons.headphones),
                  title: Text(
                    device.label.isEmpty ? 'Audio device' : device.label,
                  ),
                  onTap: () => Navigator.of(context).pop(device.deviceId),
                ),
            ],
          ),
        ),
      );
      if (deviceId == null || !mounted) {
        return;
      }
      final selected = await _remoteRenderer.audioOutput(deviceId);
      if (!selected) {
        throw StateError('The selected audio output could not be activated.');
      }
    } catch (error) {
      _showCallMessage('Could not change audio output: $error');
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      final speakerOn = !_speakerOn;
      await Helper.setSpeakerphoneOn(speakerOn);
      if (mounted) {
        setState(() => _speakerOn = speakerOn);
      }
    } catch (error) {
      _showCallMessage('Could not change speaker: $error');
    }
  }

  void _showCallMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    _isEnding = true;
    _ringTimeout?.cancel();
    unawaited(_disposeCall());
    super.dispose();
  }

  Future<void> _disposeCall() async {
    await _cleanup();
    await _remoteRenderer.dispose();
    await _localRenderer.dispose();
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
              child: widget.isVideoCall
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : _buildProfileHeader(primary),
            ),
            if (widget.isVideoCall && _videoOn)
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
            if (widget.isVideoCall &&
                _phase != _CallPhase.connected &&
                _phase != _CallPhase.ended)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.isVideoCall)
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
                      : widget.displayName
                            .trim()
                            .characters
                            .first
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
          speakerOn: _speakerOn,
          showSpeaker:
              !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS),
          onToggleVideo: _toggleVideo,
          onToggleMute: _toggleMute,
          onChooseAudioOutput: _chooseAudioOutput,
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
    required this.speakerOn,
    required this.showSpeaker,
    required this.onToggleVideo,
    required this.onToggleMute,
    required this.onChooseAudioOutput,
    required this.onToggleSpeaker,
    required this.onHangup,
  });

  final bool showVideo;
  final bool videoOn;
  final bool muted;
  final bool speakerOn;
  final bool showSpeaker;
  final VoidCallback onToggleVideo;
  final VoidCallback onToggleMute;
  final VoidCallback onChooseAudioOutput;
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
            tooltip: 'Choose audio output',
            icon: AppIcons.headphones,
            size: 46,
            onTap: onChooseAudioOutput,
          ),
          if (showSpeaker)
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
              border: active ? Border.all(color: activeColor, width: 2) : null,
            ),
            child: Center(child: iconWidget),
          ),
        ),
      ),
    );
  }
}
