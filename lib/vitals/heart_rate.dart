import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:get_it/get_it.dart';
import 'package:heart_monitor/global_vitals.dart';
import 'package:heart_monitor/settings.dart';
import 'package:heart_monitor/widgets/alarms_widget.dart';
import 'package:provider/provider.dart';

class HeartRateDisplay extends StatefulWidget {
  const HeartRateDisplay({super.key});

  @override
  State<HeartRateDisplay> createState() => _HeartRateDisplayState();
}

class _HeartRateDisplayState extends State<HeartRateDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _wasHigh = false;
  int _previousBpm = 75;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SettingsService settings = GetIt.I<SettingsService>();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: (60000 / _previousBpm.clamp(30, 200)).round()),
      vsync: this,
    )..repeat();
  }

  void _updateBpmIfChanged(int bpm) {
    if (bpm != _previousBpm) {
      _controller.duration = Duration(milliseconds: (60000 / bpm.clamp(30, 200)).round());
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      _checkAndPlayAlert(bpm);
      _previousBpm = bpm;
    }
  }

  void _checkAndPlayAlert(int currentBpm) async {
    final isHigh = currentBpm > 100;
    if (isHigh && !_wasHigh && settings.alarmsEnabled) {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/heart_rate_warning.wav'));
    }
    _wasHigh = isHigh;
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalVitals>(
      builder: (context, vitals, child) {
        final currentBpm = vitals.bpm;
        final isHigh = currentBpm > 100;

        // Update BPM if changed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateBpmIfChanged(currentBpm);
        });

        return SizedBox(
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final flashing = _controller.value < 0.5;

              return Stack(
                children: [
                  // Top-left: HR label + heart icon
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Row(
                      children: [
                        Text('HR', style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 16)),
                        const SizedBox(width: 8),
                        Icon(flashing ? Icons.favorite : Icons.favorite_border, color: Colors.redAccent, size: 24),
                      ],
                    ),
                  ),

                  // Top-right: Pacing Off + alarms + bpm
                  Positioned(
                    top: 0,
                    right: 8,
                    child: Row(
                      children: [
                        const AlarmsStatusWidget(),
                        const SizedBox(width: 10),
                        Text(
                          'Pace Off',
                          style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 12, fontFamily: 'Arial'),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'bpm',
                          style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 12, fontFamily: 'Arial'),
                        ),
                      ],
                    ),
                  ),

                  // Center: BPM display
                  Center(
                    child: isHigh
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
                            decoration: BoxDecoration(
                              color: flashing ? Colors.red : Colors.transparent,
                              border: Border.all(color: Colors.red, width: 4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currentBpm.toString(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 80,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Nimbus',
                              ),
                            ),
                          )
                        : Text(
                            currentBpm.toString(),
                            style: const TextStyle(
                              color: Color.fromARGB(255, 42, 255, 74),
                              fontSize: 80,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Nimbus',
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
