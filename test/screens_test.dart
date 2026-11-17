// Renders the monitor in a handful of states and sizes so the layout can be
// looked at without a device. Skipped in a normal test run; to write the
// images to test/goldens/ use:
//
//   flutter test --update-goldens test/screens_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heart_monitor/app/settings.dart';
import 'package:heart_monitor/app/sounds.dart';
import 'package:heart_monitor/sim/patient_sim.dart';
import 'package:heart_monitor/sim/scenarios.dart';
import 'package:heart_monitor/ui/monitor_screen.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  await loader.load();
}

Future<void> _fonts() async {
  await _font('RobotoVariable', 'assets/fonts/Roboto-VariableFont_wdth,wght.ttf');
  await _font('Nimbus', 'assets/fonts/NimbusSanL-Bol.otf');
  await _font('Roboto', 'assets/fonts/Roboto-VariableFont_wdth,wght.ttf');
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  await _font('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

typedef Setup =
    Future<void> Function(WidgetTester t, PatientSim sim, MonitorSettings st, GlobalKey<MonitorScreenState> key);

Future<void> shot(
  WidgetTester tester,
  String name,
  Size size, {
  Setup? before,
  Setup? after,
  double seconds = 14,
  double tail = 0,
}) async {
  await _fonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sim = PatientSim(seed: 11, clock: () => DateTime(2026, 11, 16, 21, 42, 7));
  final st = MonitorSettings()..patientName = 'RIVERA, SAM';
  final key = GlobalKey<MonitorScreenState>();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: MonitorScreen(key: key, sim: sim, settings: st, sounds: SoundBoard(), showBoot: name == 'boot'),
      ),
    ),
  );
  if (before != null) await before(tester, sim, st, key);
  for (var i = 0; i < seconds * 50; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (after != null) {
    await after(tester, sim, st, key);
    for (var i = 0; i < tail * 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

const desktop = Size(1366, 768);
const tablet = Size(1180, 820);
const phone = Size(844, 390);

void main() {
  if (!autoUpdateGoldenFiles) {
    test('screenshots', () {}, skip: 'run with --update-goldens to render the screenshots');
    return;
  }
  Setup layout(ScreenLayout l, [String? rhythm]) => (t, sim, st, k) async {
    st.update(() => st.layout = l);
    if (rhythm != null) sim.setRhythm(rhythm);
  };
  Scenario sc(String id) => kScenarios.firstWhere((s) => s.id == id);

  testWidgets('full tablet', (t) => shot(t, 'full_tablet', tablet, seconds: 40));
  testWidgets('full desktop', (t) => shot(t, 'full_desktop', desktop, seconds: 40));
  testWidgets('full phone', (t) => shot(t, 'full_phone', phone, seconds: 40));
  testWidgets(
    'standard tablet',
    (t) => shot(t, 'standard_tablet', tablet, seconds: 40, before: layout(ScreenLayout.standard)),
  );
  testWidgets('big tablet', (t) => shot(t, 'big_tablet', tablet, seconds: 40, before: layout(ScreenLayout.big)));
  testWidgets(
    'trends tablet',
    (t) => shot(
      t,
      'trends_tablet',
      tablet,
      seconds: 150,
      before: (t, sim, st, k) async {
        st.update(() => st.layout = ScreenLayout.trends);
        sim.runScenario(sc('asthma'));
      },
    ),
  );
  testWidgets(
    'review tablet',
    (t) => shot(
      t,
      'review_tablet',
      tablet,
      seconds: 120,
      before: (t, sim, st, k) async {
        st.update(() => st.layout = ScreenLayout.review);
        sim.runScenario(sc('arrest'));
      },
    ),
  );
  testWidgets('boot', (t) => shot(t, 'boot', tablet, seconds: 1));
  testWidgets(
    'arrest full',
    (t) => shot(t, 'arrest_full', tablet, seconds: 142, before: (t, sim, st, k) async => sim.runScenario(sc('arrest'))),
  );
  testWidgets(
    'head injury',
    (t) => shot(t, 'head_full', tablet, seconds: 85, before: (t, sim, st, k) async => sim.runScenario(sc('head'))),
  );
  testWidgets(
    'sedated',
    (t) => shot(
      t,
      'sedated_full',
      tablet,
      seconds: 45,
      before: (t, sim, st, k) async {
        sim.bis.set(14);
        sim.nmt.set(0.6);
        sim.setRhythm('stemi_inf');
      },
    ),
  );
  testWidgets(
    'twelve',
    (t) => shot(
      t,
      'twelve',
      tablet,
      before: (t, sim, st, k) async => sim.setRhythm('stemi_ant'),
      seconds: 12,
      after: (t, sim, st, k) async {
        await t.tap(find.text('12-Lead ECG'));
      },
      tail: 6,
    ),
  );
  testWidgets(
    'strip',
    (t) => shot(
      t,
      'strip',
      tablet,
      before: (t, sim, st, k) async => sim.setRhythm('bigeminy'),
      seconds: 14,
      after: (t, sim, st, k) async {
        await t.tap(find.text('Record Strip'));
      },
      tail: 0.5,
    ),
  );
  testWidgets(
    'screen menu',
    (t) => shot(
      t,
      'screen_menu',
      tablet,
      seconds: 10,
      after: (t, sim, st, k) async {
        await t.tap(find.text('Change Screen'));
      },
      tail: 0.5,
    ),
  );
  testWidgets(
    'setup',
    (t) => shot(
      t,
      'setup',
      tablet,
      seconds: 10,
      after: (t, sim, st, k) async {
        await t.tap(find.text('Main Setup'));
      },
      tail: 0.5,
    ),
  );
  testWidgets(
    'panel',
    (t) => shot(
      t,
      'panel',
      tablet,
      seconds: 10,
      after: (t, sim, st, k) async {
        k.currentState!.togglePanel();
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.text('Vitals'));
      },
      tail: 0.5,
    ),
  );
}
