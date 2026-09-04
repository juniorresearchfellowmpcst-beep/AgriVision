import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';

/// The survey screen has to say what it can produce *before* the flight.
///
/// The rule under test is the one an operator cannot discover on their own:
/// detection needs a camera, not an aircraft. Someone whose flight controller
/// will not pair should still scan, and should not be told to go fix the drone
/// first. Equally, they must not be promised a spray plan that cannot exist
/// without position.
///
/// So: never gate the survey on the link, and never imply a map is coming
/// when it is not.

class _Survey extends SurveyService {
  _Survey(this.link);

  final Map<String, dynamic>? link;

  @override
  Future<SurveyCapabilities> fetchCapabilities() async =>
      SurveyCapabilities.fromJson({
        'camera_modes': [
          {
            'id': 'rgb',
            'name': 'IP camera',
            'detail': 'Live CNN detection from the video feed.',
            'available': true,
            'cameras': [
              {'id': 1, 'name': 'Nose camera', 'role': 'rgb'},
            ],
          },
        ],
        if (link != null) 'flight_link': link,
      });

  @override
  Future<({List<SurveyRun> runs, SurveyRun? active})> fetchRuns() async =>
      (runs: <SurveyRun>[], active: null);
}

class _Crops extends CropCatalogService {
  @override
  Future<({List<CropCatalogItem> crops, CropCatalogItem weeds})> fetchCatalog({
    int? month,
  }) async {
    CropCatalogItem item(String id, String name) => CropCatalogItem.fromJson({
      'id': id,
      'name': name,
      'local_name': name,
      'season': 'kharif',
      'disease_count': 3,
      'in_season': true,
    });
    return (
      crops: [item('soybean', 'Soybean')],
      weeds: item('weeds', 'Weeds'),
    );
  }
}

class _FieldScan extends FieldScanService {
  @override
  Future<({List<CropCatalogItem> crops, CropCatalogItem weeds})> fetchCatalog({
    int? month,
  }) async => _Crops().fetchCatalog(month: month);
}

Future<void> pumpSurvey(WidgetTester tester, Map<String, dynamic>? link) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<SurveyCubit>(create: (_) => SurveyCubit(service: _Survey(link))),
        BlocProvider<CropCubit>(create: (_) => CropCubit(service: _Crops())),
        BlocProvider<FieldScanCubit>(
          create: (_) => FieldScanCubit(service: _FieldScan()),
        ),
      ],
      child: const MaterialApp(home: SurveyPage()),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _linked = {
  'connected': true,
  'gps_fix': 3,
  'can_map': true,
  'detail': 'Flight link up with a GPS fix. Detections will be mapped and a '
      'spray plan can be built.',
};

const _noFix = {
  'connected': true,
  'gps_fix': 1,
  'can_map': false,
  'detail': 'Flight link up, waiting for a GPS fix. Detection works now; the '
      'spray map needs position.',
};

const _noLink = {
  'connected': false,
  'gps_fix': null,
  'can_map': false,
  'detail': 'No flight link. Detection still works from the camera alone — '
      'you will get a diagnosis, but no field map and no spray plan until the '
      'drone is connected.',
};

void main() {
  setUp(() => SharedPreferencesLike.noop());

  group('with no drone connected', () {
    testWidgets('the survey can still be started', (tester) async {
      await pumpSurvey(tester, _noLink);

      // The setup screen is a ListView and the button sits below the fold,
      // so it is not built until scrolled to.
      await tester.scrollUntilVisible(
        find.text('Start survey'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // Matched by predicate, not by type: `FilledButton.icon` builds a
      // private subclass and `byType` compares runtime types exactly.
      final finder = find.ancestor(
        of: find.text('Start survey'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(finder, findsWidgets);
      final button = tester.widget<ButtonStyleButton>(finder.first);
      expect(
        button.onPressed,
        isNotNull,
        reason: 'a camera is registered, so detection can run without a drone',
      );
    });

    testWidgets('it says detection still works', (tester) async {
      await pumpSurvey(tester, _noLink);

      expect(find.text('Camera only — detection still works'), findsOneWidget);
      expect(find.textContaining('no spray plan'), findsOneWidget);
    });

    testWidgets('it does not read as an error', (tester) async {
      // A normal way to use the app, not a fault to clear.
      await pumpSurvey(tester, _noLink);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('with the drone linked', () {
    testWidgets('a full survey is promised once there is a fix', (
      tester,
    ) async {
      await pumpSurvey(tester, _linked);

      expect(find.text('Drone linked — full survey'), findsOneWidget);
      expect(find.textContaining('spray plan can be built'), findsOneWidget);
    });

    testWidgets('waiting for GPS is called out separately', (tester) async {
      // Connected but unlocated is its own state: scanning works, the map
      // does not. Collapsing it into either neighbour misleads.
      await pumpSurvey(tester, _noFix);

      expect(find.text('Drone linked — waiting for GPS'), findsOneWidget);
      expect(find.textContaining('needs position'), findsOneWidget);
    });
  });

  testWidgets('a server that says nothing about the link still renders', (
    tester,
  ) async {
    // An older backend sends no flight_link at all. The screen must degrade to
    // the honest default rather than throwing or claiming a link.
    await pumpSurvey(tester, null);

    expect(find.text('Camera only — detection still works'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// SharedPreferences is not used by this screen; kept as a no-op so the setUp
/// reads the same as the other suites.
class SharedPreferencesLike {
  static void noop() {}
}
