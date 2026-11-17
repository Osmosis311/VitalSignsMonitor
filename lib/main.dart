import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/settings.dart';
import 'app/sounds.dart';
import 'sim/patient_sim.dart';
import 'ui/monitor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  try {
    await WakelockPlus.enable();
  } catch (_) {
    // Keeping the screen awake is a nicety, not a requirement.
  }
  final settings = MonitorSettings();
  await settings.load();
  runApp(MainApp(settings: settings));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.settings});
  final MonitorSettings settings;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final PatientSim _sim = PatientSim();
  final SoundBoard _sounds = AssetSoundBoard();

  @override
  void dispose() {
    _sounds.dispose();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Heart Monitor Simulator',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: MonitorScreen(sim: _sim, settings: widget.settings, sounds: _sounds),
      ),
    );
  }
}
