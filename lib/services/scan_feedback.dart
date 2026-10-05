import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';

/// Beep and vibration after a scan. Sounds play even in silent mode (the
/// in-app switch controls them) and mix with other audio instead of pausing it.
class ScanFeedback {
  ScanFeedback._();
  static final ScanFeedback instance = ScanFeedback._();

  AudioPlayer? _ok;
  AudioPlayer? _alert;
  Future<void>? _init;

  Future<void> _ensure() => _init ??= () async {
        final context = AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
          respectSilence: false,
        ).build();
        await AudioPlayer.global.setAudioContext(context);
        Future<AudioPlayer> make(String asset) async {
          final p = AudioPlayer();
          await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource(asset));
          return p;
        }

        _ok = await make('sounds/beep.wav');
        _alert = await make('sounds/alert.wav');
      }();

  Future<void> _play(AudioPlayer? Function() player) async {
    try {
      await _ensure();
      final p = player();
      if (p == null) return;
      await p.stop();
      await p.resume();
    } catch (_) {
      // Sound is a nicety; a failing audio session must not break scanning.
    }
  }

  void counted() {
    final s = AppSettings.instance;
    if (s.beep) _play(() => _ok);
    if (s.vibrate) HapticFeedback.mediumImpact();
  }

  /// Something needs the user's attention (unknown case size, invalid code).
  void attention() {
    final s = AppSettings.instance;
    if (s.beep) _play(() => _alert);
    if (s.vibrate) HapticFeedback.heavyImpact();
  }
}
