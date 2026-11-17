import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../sim/alarms.dart';

/// The monitor's speaker. The base class is silent, for tests and for
/// platforms where audio is not available.
class SoundBoard {
  void qrs(int? spo2, int volume) {}
  void alarm(AlarmPriority priority, int volume) {}
  void stopAlarm() {}
  void key(int volume) {}
  void dispose() {}
}

/// Plays the generated tones in assets/sounds (see tool/make_sounds.py).
class AssetSoundBoard extends SoundBoard {
  final List<AudioPlayer> _qrs = [AudioPlayer(), AudioPlayer()];
  final AudioPlayer _alarm = AudioPlayer();
  final AudioPlayer _key = AudioPlayer();
  int _next = 0;

  static double _gain(int volume) => (volume / 5).clamp(0.0, 1.0).toDouble();

  void _play(AudioPlayer p, String file, int volume, {bool lowLatency = true}) {
    if (volume <= 0) return;
    unawaited(() async {
      try {
        await p.stop();
        await p.play(
          AssetSource('sounds/$file'),
          volume: _gain(volume),
          mode: lowLatency ? PlayerMode.lowLatency : PlayerMode.mediaPlayer,
        );
      } catch (_) {
        // A missed beep is not worth interrupting the display for.
      }
    }());
  }

  /// Pulse tone. The pitch follows SpO₂, dropping as saturation falls.
  @override
  void qrs(int? spo2, int volume) {
    final s = (spo2 ?? 100).clamp(80, 100);
    _next = (_next + 1) % _qrs.length;
    _play(_qrs[_next], 'qrs_$s.wav', volume);
  }

  @override
  void alarm(AlarmPriority priority, int volume) {
    final file = switch (priority) {
      AlarmPriority.high => 'alarm_high.wav',
      AlarmPriority.medium => 'alarm_med.wav',
      AlarmPriority.technical => 'alarm_low.wav',
    };
    _play(_alarm, file, volume, lowLatency: false);
  }

  @override
  void stopAlarm() {
    unawaited(() async {
      try {
        await _alarm.stop();
      } catch (_) {}
    }());
  }

  @override
  void key(int volume) => _play(_key, 'key.wav', volume);

  @override
  void dispose() {
    for (final p in [..._qrs, _alarm, _key]) {
      unawaited(p.dispose().catchError((_) {}));
    }
  }
}
