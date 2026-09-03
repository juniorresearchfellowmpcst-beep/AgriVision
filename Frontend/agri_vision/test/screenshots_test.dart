@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/language/language_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';
import 'package:agri_vision/src/ui/view/CropScan/crop_scan_page.dart';
import 'package:agri_vision/src/ui/widget/settings/language_sheet.dart';

/// Renders the real screens to PNG for the user manual.
///
///     flutter test test/screenshots_test.dart --update-goldens
///
/// These are **renders of the actual widgets**, not mock-ups drawn to look
/// like the app — every pixel comes from the same code that ships. Services
/// are faked so nothing waits on a socket, but the layout, colours, spacing
/// and copy are the app's own.
///
/// Two things make a widget test produce a *usable* picture rather than a wall
/// of black rectangles:
///
///   * **Real fonts.** `flutter test` ships a test font whose every glyph is a
///     filled box. Arial is loaded under the app's declared family so Latin
///     text is legible, and Nirmala under the Devanagari fallback so the Hindi
///     screens are too.
///   * **A device-sized surface.** Left at the default 800x600 the screens are
///     landscape and nothing looks like a phone.
///
/// Written as golden files because `--update-goldens` is the supported way to
/// get a real PNG out of a widget test; there is no expectation of pixel
/// stability, so these are excluded from the normal run by the `screenshots`
/// tag.
const _out = '../../../docs/manual/img';

/// A 9:19.5 phone, the shape most of the audience holds.
const _phone = Size(390, 844);

// ── fakes ────────────────────────────────────────────────────────────────────

class _Drone extends DroneService {
  @override
  Future<AssignedDroneEntity?> fetchStatus() async => null;
}

class _Missions extends MissionService {
  @override
  Future<List<MissionReportEntity>> fetchMissions() async => [
    MissionReportEntity(
      id: 1,
      title: 'Block A — north',
      date: '31 Aug 2026',
      area: '4.2 ha',
      status: 'done',
    ),
    MissionReportEntity(
      id: 2,
      title: 'Block B — canal side',
      date: '28 Aug 2026',
      area: '2.8 ha',
      status: 'partial',
    ),
  ];
}

class _Crops extends CropCatalogService {
  @override
  Future<({List<CropCatalogItem> crops, CropCatalogItem weeds})> fetchCatalog({
    int? month,
  }) async {
    CropCatalogItem c(String id, String name, String local, bool season) =>
        CropCatalogItem.fromJson({
          'id': id,
          'name': name,
          'local_name': local,
          'season': season ? 'kharif' : 'rabi',
          'disease_count': 5,
          'in_season': season,
        });
    return (
      crops: [
        c('soybean', 'Soybean', 'Soyabean / सोयाबीन', true),
        c('rice', 'Rice', 'Dhan / धान', true),
        c('maize', 'Maize', 'Makka / मक्का', true),
        c('cotton', 'Cotton', 'Kapas / कपास', true),
        c('pigeonpea', 'Pigeonpea', 'Arhar / अरहर', true),
        c('wheat', 'Wheat', 'Gehun / गेहूँ', false),
        c('gram', 'Gram', 'Chana / चना', false),
        c('mustard', 'Mustard', 'Sarson / सरसों', false),
      ],
      weeds: c('weeds', 'Weeds', 'खरपतवार', true),
    );
  }
}

/// Reports a rig carrying both camera kinds, so the setup screen shows every
/// mode enabled rather than three greyed-out rows.
class _Survey extends SurveyService {
  @override
  Future<SurveyCapabilities> fetchCapabilities() async =>
      SurveyCapabilities.fromJson({
        'camera_modes': [
          {
            'id': 'rgb',
            'name': 'IP camera',
            'detail': 'Live CNN disease and weed detection from the video '
                'feed as the aircraft flies.',
            'available': true,
            'cameras': [
              {'id': 1, 'name': 'Nose camera', 'role': 'rgb'},
            ],
          },
          {
            'id': 'multispectral',
            'name': 'Multispectral',
            'detail': 'Vegetation indices and a K-means zone map. More '
                'accurate about where the field is stressed, and silent '
                'about which disease it is.',
            'available': true,
            'cameras': [
              {'id': 2, 'name': 'Red band', 'role': 'multispectral'},
              {'id': 3, 'name': 'NIR band', 'role': 'multispectral'},
            ],
          },
          {
            'id': 'both',
            'name': 'Both',
            'detail': 'The CNN names the disease from the RGB feed while the '
                'bands map where the field is worst. The prescription is '
                'built from the bands.',
            'available': true,
            'cameras': [
              {'id': 1},
              {'id': 2},
              {'id': 3},
            ],
          },
        ],
        'advisor': {'available': true, 'model': 'gemini-flash-latest'},
        'spray_hardware': {'mechanism': 'servo', 'variable_rate': true},
      });

  @override
  Future<({List<SurveyRun> runs, SurveyRun? active})> fetchRuns() async =>
      (runs: <SurveyRun>[], active: null);
}

/// The crop list behind the survey screen's chips.
class _FieldScan extends FieldScanService {
  @override
  Future<List<CropOption>> fetchCrops() async => [
    for (final row in const [
      ('soybean', 'Soybean'),
      ('rice', 'Rice'),
      ('maize', 'Maize'),
      ('wheat', 'Wheat'),
      ('gram', 'Gram'),
      ('cotton', 'Cotton'),
    ])
      CropOption.fromJson({
        'id': row.$1,
        'name': row.$2,
        'local_name': '',
        'season': 'kharif',
        'disease_count': 5,
      }),
  ];

  @override
  Future<Map<String, String>> fetchEngines() async => const {
    'disease': 'model',
    'weed': 'heuristic',
  };
}

// ── harness ──────────────────────────────────────────────────────────────────

/// Loads system fonts so text renders as text.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
      any = true;
    }
    if (any) await loader.load();
  }

  const win = r'C:\Windows\Fonts';
  // The app declares IBM_Plex_Sans but ships no font file, so it already falls
  // back to the platform default. Arial stands in for that here.
  await load('IBM_Plex_Sans', ['$win\\arial.ttf', '$win\\arialbd.ttf']);
  await load('Roboto', ['$win\\arial.ttf', '$win\\arialbd.ttf']);
  // Devanagari, for the Hindi screens. Windows ships Nirmala as a .ttc
  // collection, which FontLoader cannot parse, so tool/extract_ttf.py pulls
  // font 0 out of it into a plain .ttf next to this test.
  await load('Nirmala UI', ['test/fonts/NirmalaUI.ttf']);
  await load('IBM_Plex_Sans', ['test/fonts/NirmalaUI.ttf']);
  await load('Roboto', ['test/fonts/NirmalaUI.ttf']);

  // Without this every Icon() renders as an empty square: the glyphs live in a
  // font the test environment does not load for you, and a manual full of
  // blank boxes where the buttons are would be worse than no pictures at all.
  //
  // The font lives under the SDK cache, but how deep the test runner's own
  // executable sits inside that cache varies by Flutter version — counting
  // `.parent`s guessed wrong and produced `artifacts\artifacts\...`. Walking up
  // until the directory is actually there is version-proof.
  String? materialIcons() {
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final candidate = File(
        '${dir.path}\\artifacts\\material_fonts\\materialicons-regular.otf',
      );
      if (candidate.existsSync()) return candidate.path;
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }

  final icons = materialIcons();
  await load('MaterialIcons', [if (icons != null) icons]);
}

void main() {
  // FontLoader needs the test binding before it can register anything.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = _phone,
    int pumps = 4,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(child);
    // Localizations delegates resolve asynchronously and each screen loads on
    // its first frame, so a single pump captures spinners.
    for (var i = 0; i < pumps; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_out/$name.png'),
    );
  }

  Widget app(Widget home, {AppLanguage language = AppLanguage.english}) =>
      MaterialApp(
        theme: AppTheme.standard,
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        localizationsDelegates: [
          AppStringsDelegate(language),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLanguage.values.map((l) => l.locale),
        home: home,
      );

  Widget withCubits(Widget home, {AppLanguage language = AppLanguage.english}) =>
      MultiBlocProvider(
        providers: [
          BlocProvider<DroneCubit>(create: (_) => DroneCubit(service: _Drone())),
          BlocProvider<MissionsCubit>(
            create: (_) => MissionsCubit(service: _Missions()),
          ),
          BlocProvider<BottomNavBarCubit>(create: (_) => BottomNavBarCubit()),
          BlocProvider<LanguageCubit>(create: (_) => LanguageCubit()),
          BlocProvider<CropCubit>(create: (_) => CropCubit(service: _Crops())),
          BlocProvider<SurveyCubit>(
            create: (_) => SurveyCubit(service: _Survey()),
          ),
          // The survey setup screen reads its crop chips from the shared
          // field-scan catalogue.
          BlocProvider<FieldScanCubit>(
            create: (_) => FieldScanCubit(service: _FieldScan()),
          ),
        ],
        child: app(home, language: language),
      );

  testWidgets('01 home, English', (tester) async {
    await shoot(tester, '01-home-en', withCubits(const HomePage()));
  });

  testWidgets('02 crop picker — pick a crop', (tester) async {
    await shoot(tester, '02-crop-picker', withCubits(const CropScanPage()));
  });

  testWidgets('03 crop screen — the camera', (tester) async {
    await shoot(
      tester,
      '03-crop-camera',
      withCubits(
        Builder(
          builder: (context) {
            // Drive the cubit the way tapping a tile would, so this is the
            // real screen rather than a stand-in for it.
            context.read<CropCubit>().openCrop('soybean');
            return const CropDetailPage(cropId: 'soybean');
          },
        ),
      ),
      pumps: 6,
    );
  });

  testWidgets('04 survey flight setup', (tester) async {
    await shoot(tester, '04-survey-setup', withCubits(const SurveyPage()));
  });
}
