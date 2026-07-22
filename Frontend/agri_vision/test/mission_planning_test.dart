import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

/// Offline stand-in for [DroneService] so the page's `initState` drone load
/// resolves instantly with dummy data instead of hitting the network (a real
/// request would leave a pending timeout timer when the test tears down).
class _FakeDroneService extends DroneService {
  @override
  Future<AssignedDroneEntity> fetchStatus() async =>
      AssignedDroneEntity.getDummyData();
}

void main() {
  Future<void> pumpMissionPage(WidgetTester tester) async {
    // MissionPlanningPage reads DroneCubit (initState + BlocBuilder) and
    // MissionsCubit (its mission actions). In the app these are provided
    // app-wide in app.dart, so the test mirrors that shell here.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DroneCubit>(
            create: (_) => DroneCubit(service: _FakeDroneService()),
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

  group('mission planning map', () {
    testWidgets('renders the default waypoints', (tester) async {
      await pumpMissionPage(tester);

      expect(find.text('1'), findsWidgets);
      expect(find.text('10'), findsWidgets);
      expect(find.text('11'), findsNothing);
    });

    testWidgets('taps are ignored in view mode (no accidental waypoints)', (
      tester,
    ) async {
      await pumpMissionPage(tester);

      // Without entering edit mode a map tap must not drop a waypoint.
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsNothing);
    });

    testWidgets('tapping empty map adds a waypoint at that spot', (
      tester,
    ) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      // Tap an empty corner of the map (away from markers, FABs, top bar).
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsWidgets);
    });

    testWidgets('tapping map with a selection deselects instead of adding', (
      tester,
    ) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      // Select waypoint 1, then tap empty map: should deselect, not add.
      await tester.tap(find.text('1').first);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsNothing);

      // A second tap (nothing selected now) adds waypoint 11.
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsWidgets);
    });

    testWidgets('undo removes the waypoint added by a map tap', (tester) async {
      await pumpMissionPage(tester);
      await enterEditMode(tester);

      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('11'), findsWidgets);

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsNothing);
    });
  });
}
