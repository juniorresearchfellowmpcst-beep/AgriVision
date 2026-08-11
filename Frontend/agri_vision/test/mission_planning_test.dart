import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

/// Offline stand-in for [DroneService] so the page's `initState` drone load
/// resolves instantly instead of hitting the network (a real request would
/// leave a pending timeout timer when the test tears down). It answers the
/// way the server does with nothing paired: no drone.
class _FakeDroneService extends DroneService {
  @override
  Future<AssignedDroneEntity?> fetchStatus() async => null;
}

/// Same idea for the MAVLink link the page reads in `initState`: no vehicle,
/// resolved locally, no socket.
class _FakeMavlinkService extends MavlinkService {
  @override
  Future<MavlinkStatusEntity> fetchStatus() async =>
      const MavlinkStatusEntity();
}

void main() {
  // A device that has never opened the mission map, unless a test says
  // otherwise — that is what decides whether the first-run hint appears.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpMissionPage(WidgetTester tester) async {
    // MissionPlanningPage reads DroneCubit (initState + BlocBuilder),
    // MavlinkCubit (link chip + launch) and MissionsCubit (its mission
    // actions). In the app these are provided app-wide in app.dart, so the
    // test mirrors that shell here.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DroneCubit>(
            create: (_) => DroneCubit(service: _FakeDroneService()),
          ),
          BlocProvider<MavlinkCubit>(
            create: (_) => MavlinkCubit(service: _FakeMavlinkService()),
          ),
          BlocProvider<MissionsCubit>(create: (_) => MissionsCubit()),
        ],
        child: const MaterialApp(home: MissionPlanningPage()),
      ),
    );
    // Let the map settle; tile images fail to load in tests, which is fine —
    // flutter_map handles tile errors and the gesture layer still works.
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The page opens in view mode so stray taps don't drop waypoints; the pencil
  // FAB unlocks the editing tools (add / undo / redo / delete). Tests that
  // exercise tap-to-add must switch it on first.
  Future<void> enterEditMode(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('drone status strip', () {
    testWidgets('offers to connect instead of showing gauges', (tester) async {
      await pumpMissionPage(tester);

      expect(find.text('No drone  '), findsOneWidget);
      expect(find.text('Tap to connect'), findsOneWidget);
      // Nothing is reporting, so no battery / tank / signal reading may
      // appear — not a value, not a zero.
      expect(find.byIcon(Icons.battery_5_bar), findsNothing);
      expect(find.byIcon(Icons.water_drop_outlined), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('dBm'), findsNothing);
    });

    testWidgets('tapping it opens the connect sheet', (tester) async {
      await pumpMissionPage(tester);

      await tester.tap(find.text('Tap to connect'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Connect Drone'), findsWidgets);
      expect(find.text('No drone paired to this account.'), findsOneWidget);
    });
  });

  group('mission planning map', () {
    testWidgets('opens with no survey block of its own', (tester) async {
      await pumpMissionPage(tester);

      // A canned demo polygon used to be seeded here; a pilot signing up now
      // gets a blank map over their own ground, plus a hint about drawing.
      expect(find.text('1'), findsNothing);
      expect(find.text('No survey block yet'), findsOneWidget);
      expect(find.textContaining('Tap the pencil'), findsOneWidget);
    });

    testWidgets('the drawing hint is a first run only, not a banner', (
      tester,
    ) async {
      await pumpMissionPage(tester);
      expect(find.text('No survey block yet'), findsOneWidget);

      // Showing it once spends it: a refresh, a tab switch or the next launch
      // all rebuild this page, and none of them may bring it back.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpMissionPage(tester);

      expect(find.text('No survey block yet'), findsNothing);
    });

    testWidgets('a pilot who has seen it never gets it again', (tester) async {
      SharedPreferences.setMockInitialValues({
        StorageConstants.missionHintSeen: true,
      });

      await pumpMissionPage(tester);

      expect(find.text('No survey block yet'), findsNothing);
      // The map itself is still blank — only the introduction is spent.
      expect(find.text('1'), findsNothing);
    });

    testWidgets('taps are ignored in view mode (no accidental waypoints)', (
      tester,
    ) async {
      await pumpMissionPage(tester);

      // Without entering edit mode a map tap must not drop a waypoint.
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1'), findsNothing);
    });

    testWidgets('tapping empty map adds a waypoint at that spot', (
      tester,
    ) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      // Tap an empty corner of the map (away from markers, FABs, top bar).
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1'), findsWidgets);
      // The hint has done its job and gets out of the way.
      expect(find.text('No survey block yet'), findsNothing);
    });

    testWidgets('tapping map with a selection deselects instead of adding', (
      tester,
    ) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      // Select waypoint 1, then tap empty map: should deselect, not add.
      await tester.tap(find.text('1').first);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(const Offset(120, 260));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2'), findsNothing);

      // A second tap (nothing selected now) adds waypoint 2.
      await tester.tapAt(const Offset(120, 260));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2'), findsWidgets);
    });

    testWidgets('undo removes the waypoint added by a map tap', (tester) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1'), findsNothing);
    });
  });

  group('mission setup stats', () {
    testWidgets('measures nothing until a block encloses something', (
      tester,
    ) async {
      await pumpMissionPage(tester);

      // These were fixed demo figures that read "4.2 ha · ~18 min" over an
      // empty map, contradicting the top bar's own "0.0 ha".
      expect(find.text('4.2 ha'), findsNothing);
      expect(find.text('~18 min'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('reports the area of the block actually drawn', (tester) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      // Three corners is the least that encloses an area.
      for (final spot in const [
        Offset(60, 180),
        Offset(240, 180),
        Offset(150, 320),
      ]) {
        await tester.tapAt(spot);
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('3'), findsWidgets);
      // Whatever the number is it must be measured, not canned.
      expect(find.text('4.2 ha'), findsNothing);
      expect(
        find.textContaining(RegExp(r'^\d+\.\d ha$')),
        findsWidgets,
        reason: 'area chip should show a real measurement',
      );
    });
  });
}
