import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

/// Offline stand-ins so the pages' `initState` loads resolve locally instead of
/// leaving pending network timers when the test tears down.
class _FakeDroneService extends DroneService {
  @override
  Future<AssignedDroneEntity?> fetchStatus() async => null;
}

class _FakeMissionService extends MissionService {
  @override
  Future<List<MissionReportEntity>> fetchMissions() async => [
    MissionReportEntity(
      id: 1,
      title: 'Block A survey',
      date: 'Aug 4, 2026',
      area: '4.2 ha',
      status: 'done',
    ),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DroneCubit>(
            create: (_) => DroneCubit(service: _FakeDroneService()),
          ),
          BlocProvider<MissionsCubit>(
            create: (_) => MissionsCubit(service: _FakeMissionService()),
          ),
          BlocProvider<BottomNavBarCubit>(create: (_) => BottomNavBarCubit()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('home page', () {
    testWidgets('leads with the survey flight and a quick-action grid', (
      tester,
    ) async {
      await pumpHome(tester);

      // The primary action is the whole job — fly, scan, report, spray — not
      // just planning a path, which is only its first step and is demoted to
      // the secondary button under it.
      expect(find.text('Start Survey Flight'), findsOneWidget);
      expect(find.text('Plan a Mission Path'), findsOneWidget);

      expect(find.text('QUICK ACTIONS'), findsOneWidget);
      for (final label in [
        'Capture & Spray',
        'Weed & Disease',
        'Plant Disease',
        'Crop Analysis',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label tile');
      }
    });

    testWidgets('offers the phone scan separately from the drone actions', (
      tester,
    ) async {
      await pumpHome(tester);

      // Everything else on this screen needs an aircraft. A farmer holding a
      // suspicious leaf should not have to work out which of six drone tiles
      // is the one that does not fly, so this card sits outside the grid.
      expect(find.text('Scan with Phone'), findsOneWidget);
      expect(
        find.textContaining('No drone needed'),
        findsOneWidget,
        reason: 'the card must say it needs no aircraft',
      );
      // Crops, and no weeds tile: a close-up of one plant cannot say what
      // share of a field is weedy, so weed work stays on the drone.
      expect(find.text('Soybean'), findsOneWidget);
      expect(find.text('Weeds'), findsNothing);
    });

    testWidgets('the phone-scan chips fit a narrow screen', (tester) async {
      // A 320 dp phone is still a real device. The card used to render five
      // fixed chips regardless of width, which crushed the labels.
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Scan with Phone'), findsOneWidget);
      // Fewer chips rather than squashed ones: the first is always present.
      expect(find.text('Soybean'), findsOneWidget);
    });

    testWidgets('the home page lays out on a tablet without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024 * 2, 1366 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Start Survey Flight'), findsOneWidget);
    });

    testWidgets('the whole page scrolls, not just the mission list', (
      tester,
    ) async {
      await pumpHome(tester);

      // The greeting sits at the very top. Under the old fixed Column it was
      // pinned there and only the mission list moved.
      final greeting = find.textContaining('Good ');
      final before = tester.getTopLeft(greeting).dy;

      // Dragged from a plain label rather than the viewport centre: the centre
      // now lands on the phone-scan card, whose ink well joins the gesture
      // arena and eats the drag slop, which would make the assertion about
      // scroll distance a measurement of gesture arbitration instead.
      await tester.dragFrom(
        tester.getCenter(find.text('QUICK ACTIONS')),
        const Offset(0, -80),
      );
      await tester.pump();

      expect(tester.getTopLeft(greeting).dy, closeTo(before - 80, 0.5));
    });

    testWidgets('reveals the mission history further down the page', (
      tester,
    ) async {
      await pumpHome(tester);

      // Further than it used to be: the phone-scan card and the fifth and
      // sixth quick actions sit between the banner and the mission list.
      await tester.dragFrom(
        tester.getCenter(find.text('QUICK ACTIONS')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Missions'), findsOneWidget);
      expect(find.text('Block A survey'), findsOneWidget);
    });

    testWidgets('uses the drone mark, not a stock aviation icon', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.byIcon(Icons.flight_takeoff_rounded), findsNothing);
      expect(find.byIcon(Icons.flight), findsNothing);
      // Nothing is paired, so the connect card stands in for the gauges and
      // carries the drone mark.
      expect(find.byType(DroneIcon), findsWidgets);
    });
  });

  group('AppIconButton', () {
    testWidgets('grows rather than clipping a label taller than its height', (
      tester,
    ) async {
      // 40px tall with 14px of vertical padding leaves 12px for an 18px line —
      // the case that used to swallow the text.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppIconButton(
                label: 'Connect Drone',
                startIcon: Icons.link_rounded,
                textStyle: AppTextStyle.textMdMedium,
                height: 40,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      // An overflow would already have failed the test; assert the button is
      // genuinely tall enough for padding + line box as well.
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AppIconButton)).height,
        greaterThanOrEqualTo(14 + 20 + 14),
      );
      expect(find.text('Connect Drone'), findsOneWidget);
    });

    testWidgets('still honours a height the content fits inside', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppIconButton(
                label: 'Sign Out',
                textStyle: AppTextStyle.textSmRegular,
                height: 50,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(AppIconButton)).height, 50);
    });
  });

  group('drone pairing card', () {
    testWidgets('renders the Connect Drone label without clipping it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: DronePairingCard())),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No drone paired'), findsOneWidget);
      expect(find.text('Connect Drone'), findsOneWidget);

      // The label's own line box has to fit inside the button that draws it.
      final button = tester.getRect(
        find.widgetWithText(AppIconButton, 'Connect Drone'),
      );
      final label = tester.getRect(find.text('Connect Drone'));
      expect(label.top, greaterThanOrEqualTo(button.top));
      expect(label.bottom, lessThanOrEqualTo(button.bottom));
    });

    testWidgets('uses the drone mark for an unpaired unit', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: DronePairingCard())),
        ),
      );

      expect(find.byIcon(Icons.flight_takeoff_rounded), findsNothing);
      expect(find.byType(DroneIcon), findsOneWidget);
    });
  });

  group('map location pin', () {
    Widget mapHost({LatLng? userLocation, double? accuracy}) => MaterialApp(
      home: Scaffold(
        body: MissionMapView(
          waypoints: const [
            WaypointModel(id: 1, position: LatLng(23.1918, 77.4202)),
            WaypointModel(id: 2, position: LatLng(23.1920, 77.4207)),
            WaypointModel(id: 3, position: LatLng(23.1912, 77.4224)),
          ],
          activeLayer: MapLayer.satellite,
          userLocation: userLocation,
          userAccuracyM: accuracy,
          onWaypointMoved: (_, __) {},
          onWaypointDragStart: (_) {},
          onWaypointSelected: (_) {},
          onMapTapped: (_) {},
        ),
      ),
    );

    testWidgets('draws no pin until a location has been taken', (tester) async {
      await tester.pumpWidget(mapHost());
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.location_on), findsNothing);
    });

    testWidgets('drops a pin at the located position', (tester) async {
      await tester.pumpWidget(
        mapHost(userLocation: const LatLng(23.1913, 77.4213), accuracy: 12),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Two glyphs: the white body behind the blue one, so the pin reads on
      // satellite imagery.
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    });
  });

  group('map FAB cluster', () {
    Widget cluster({bool busy = false, bool active = false}) => MaterialApp(
      home: Scaffold(
        body: MissionFabCluster(
          editMode: false,
          canUndo: false,
          canRedo: false,
          canDelete: false,
          gpsBusy: busy,
          gpsActive: active,
          onToggleEdit: () {},
          onAddWaypoint: () {},
          onUndo: () {},
          onRedo: () {},
          onDelete: () {},
          onCenter: () {},
          onGpsLocate: () {},
          onImport: () {},
        ),
      ),
    );

    testWidgets('offers a locate button that reports what it will do', (
      tester,
    ) async {
      await tester.pumpWidget(cluster());

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byIcon(Icons.location_searching_rounded),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Pin My Location');
    });

    testWidgets('spins and refuses a second press while locating', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MissionFabCluster(
              editMode: false,
              canUndo: false,
              canRedo: false,
              canDelete: false,
              gpsBusy: true,
              onToggleEdit: () {},
              onAddWaypoint: () {},
              onUndo: () {},
              onRedo: () {},
              onDelete: () {},
              onCenter: () {},
              onGpsLocate: () => presses++,
              onImport: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();
      expect(presses, 0);
    });

    testWidgets('marks the button as on once a pin is down', (tester) async {
      await tester.pumpWidget(cluster(active: true));

      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(find.byIcon(Icons.location_searching_rounded), findsNothing);
    });
  });
}
