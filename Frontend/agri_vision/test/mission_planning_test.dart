import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agri_vision/src/src.dart';

void main() {
  Future<void> pumpMissionPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MissionPlanningPage()));
    // Let the map settle; tile images fail to load in tests, which is fine —
    // flutter_map handles tile errors and the gesture layer still works.
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('mission planning map', () {
    testWidgets('renders the default waypoints', (tester) async {
      await pumpMissionPage(tester);

      expect(find.text('1'), findsWidgets);
      expect(find.text('10'), findsWidgets);
      expect(find.text('11'), findsNothing);
    });

    testWidgets('tapping empty map adds a waypoint at that spot', (
      tester,
    ) async {
      await pumpMissionPage(tester);

      // Tap an empty corner of the map (away from markers, FABs, top bar).
      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsWidgets);
    });

    testWidgets('tapping map with a selection deselects instead of adding', (
      tester,
    ) async {
      await pumpMissionPage(tester);

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

      await tester.tapAt(const Offset(60, 200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('11'), findsWidgets);

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('11'), findsNothing);
    });
  });
}
