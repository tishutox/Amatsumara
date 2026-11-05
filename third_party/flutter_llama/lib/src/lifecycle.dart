/// Model lifecycle (sdd-flutter-llama-agent 2.4): unload in the background, after an idle timeout, and on memory
/// pressure; the next call reloads the model.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum MemoryPressureAction { unload, ignore }

class LlamaLifecycle {
  LlamaLifecycle({bool? unloadOnBackground, Duration? idleTimeout, bool idleTimeoutOff = false, this.onMemoryPressure = MemoryPressureAction.unload})
      : unloadOnBackground = unloadOnBackground ?? _mobile,
        idleTimeout = idleTimeoutOff ? null : (idleTimeout ?? (_mobile ? const Duration(minutes: 5) : null));

  static bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Default: true on Android / iOS, false on desktop.
  bool unloadOnBackground;

  /// Default: 5 minutes on Android / iOS, off (null) on desktop.
  Duration? idleTimeout;
  MemoryPressureAction onMemoryPressure;
}

/// Watches the app and the idle clock, and calls [unload] when the policy says so.
class LifecycleWatcher with WidgetsBindingObserver {
  LifecycleWatcher(this.policy, {required this.unload, required this.isBusy});
  final LlamaLifecycle policy;
  final Future<void> Function(String why) unload;
  final bool Function() isBusy;
  Timer? _idle;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    _attached = true;
  }

  void detach() {
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    _idle?.cancel();
  }

  /// Restarts the idle clock (after every call).
  void touch() {
    _idle?.cancel();
    final t = policy.idleTimeout;
    if (t == null) return;
    _idle = Timer(t, () {
      if (isBusy()) {
        touch();
      } else {
        unload('idle');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (policy.unloadOnBackground && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) unload('background');
  }

  @override
  void didHaveMemoryPressure() {
    if (policy.onMemoryPressure == MemoryPressureAction.unload) unload('memory');
  }
}
