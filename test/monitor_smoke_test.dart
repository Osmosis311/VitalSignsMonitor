import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heart_monitor/app/settings.dart';
import 'package:heart_monitor/app/sounds.dart';
import 'package:heart_monitor/sim/patient_sim.dart';
import 'package:heart_monitor/ui/central.dart';
import 'package:heart_monitor/ui/control_panel.dart';
import 'package:heart_monitor/ui/monitor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in const [Size(1366, 768), Size(844, 390), Size(667, 375), Size(820, 1180)]) {
    testWidgets('every key and window works at ${size.width.round()}x${size.height.round()}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sim = PatientSim(seed: 5)..setNibpAuto(0);
      final st = MonitorSettings();
      final key = GlobalKey<MonitorScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonitorScreen(key: key, sim: sim, settings: st, sounds: SoundBoard(), showBoot: true),
          ),
        ),
      );
      Future<void> run([double seconds = 1]) async {
        for (var i = 0; i < seconds * 25; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      // Keys that do not fit are reached through the More key.
      Future<void> press(String label) async {
        for (var i = 0; i < 4 && find.text(label).evaluate().isEmpty; i++) {
          await tester.tap(find.textContaining('More '));
          await run(0.2);
        }
        await tester.tap(find.text(label).first);
      }

      // The notice screen goes away on a touch.
      expect(find.textContaining('NOT A MEDICAL DEVICE'), findsOneWidget);
      await tester.tapAt(const Offset(200, 200));
      await run(8);
      expect(find.textContaining('NOT A MEDICAL DEVICE'), findsNothing);

      for (final label in ['Main Setup', 'Alarm Limits', 'Vitals Trend', 'NIBP Mode', 'Change Screen']) {
        await press(label);
        await run(0.3);
        expect(find.byIcon(Icons.close), findsOneWidget, reason: '$label should open a window');
        await press(label);
        await run(0.3);
        expect(find.byIcon(Icons.close), findsNothing, reason: '$label should close its window');
      }

      await press('Start NIBP');
      await run(2);
      expect(sim.nibpPhase, isNot(NibpPhase.idle));
      await press('Stop NIBP');
      await run(0.5);
      expect(sim.nibpPhase, NibpPhase.idle);

      await press('Freeze Waves');
      await run(1);
      expect(find.text('WAVES FROZEN'), findsOneWidget);
      await press('Unfreeze');
      await run(0.5);

      await press('12-Lead ECG');
      await run(1);
      expect(find.text('V4'), findsWidgets);
      await press('12-Lead ECG');
      await run(0.5);

      // Recorder strip, event mark, and every screen layout.
      await press('Record Strip');
      await run(0.5);
      expect(find.text('Recorder Strip'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await run(0.3);
      await press('Mark Event');
      await run(0.3);
      expect(sim.events.map((e) => e.text), containsAll(['Strip recorded', 'Event marked']));
      for (final l in ScreenLayout.values) {
        st.update(() => st.layout = l);
        await run(1.5);
        expect(tester.takeException(), isNull, reason: 'layout ${l.name}');
      }
      st.update(() => st.layout = ScreenLayout.full);
      await run(0.5);

      // Central station: bed counts, and opening a bed from its sector.
      await press('Central Station');
      await run(1);
      expect(find.text('CENTRAL STATION'), findsOneWidget);
      for (final n in ['4', '8', '6']) {
        await tester.tap(find.text(n));
        await run(0.5);
        expect(st.centralBeds, int.parse(n));
        expect(find.byType(BedSector), findsNWidgets(int.parse(n)));
        expect(tester.takeException(), isNull, reason: '$n beds');
      }
      await tester.tap(find.text('OKAFOR, N'));
      await run(1);
      expect(find.text('CENTRAL STATION'), findsNothing);
      expect(find.textContaining('OKAFOR, N'), findsOneWidget, reason: 'the bedside screen is now that patient');
      await press('Central Station');
      await run(0.5);
      await tester.tap(find.byType(BedSector).first);
      await run(0.5);
      expect(find.textContaining('OKAFOR, N'), findsNothing);

      await press('Pause Alarms');
      await run(0.5);
      expect(sim.alarmsPaused, isTrue);
      await press('Resume Alarms');
      await run(0.5);
      expect(sim.alarmsPaused, isFalse);

      await press('Standby');
      await run(0.5);
      expect(find.text('STANDBY'), findsOneWidget);
      final t0 = sim.t;
      await run(1);
      expect(sim.t, t0, reason: 'the patient is paused in standby');
      await tester.tapAt(const Offset(200, 200));
      await run(0.5);

      // Hidden panel: long-press the clock.
      await tester.longPress(find.textContaining(RegExp(r'\d{4}   \d\d:\d\d:\d\d')));
      await run(0.5);
      expect(find.text('Control panel'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Atrial fibrillation'),
        60,
        scrollable: find
            .descendant(
              of: find.byType(ControlPanel),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Atrial fibrillation'));
      await run(0.2);
      await tester.tap(find.text('Atrial fibrillation'));
      await run(12);
      expect(sim.rhythm.id, 'afib');
      for (final tab in ['Vitals', 'Scenarios', 'Events']) {
        await tester.tap(find.text(tab));
        await run(0.3);
      }
      await tester.tap(find.text('Shock'));
      await run(6);
      expect(sim.rhythm.id, 'nsr');
      await tester.tap(find.byTooltip('Close'));
      await run(0.5);
      expect(find.text('Control panel'), findsNothing);

      await press('Silence');
      await run(0.5);
      expect(tester.takeException(), isNull);
    });
  }
}
