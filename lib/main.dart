import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:heart_monitor/global_vitals.dart';
import 'package:heart_monitor/monitor.dart';
import 'package:heart_monitor/settings.dart';
import 'package:provider/provider.dart';

final getIt = GetIt.instance;

void main() {
  setupServices();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  runApp(const MainApp());
}

void setupServices() {
  getIt.registerSingleton<SettingsService>(SettingsService());
  getIt.registerSingleton<GlobalVitals>(GlobalVitals());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: GetIt.I<GlobalVitals>()),
        ChangeNotifierProvider.value(value: GetIt.I<SettingsService>()),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: MonitorScreen())),
      ),
    );
  }
}
