import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/language/language_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/view/CropScan/crop_scan_page.dart';

/// Does the farmer-facing UI actually fit the screens it will run on?
///
/// A layout that only looks right at the 800x600 a widget test defaults to is
/// not a layout. These pump the real screens at the sizes that matter — a
/// 320 dp budget phone, an ordinary 360 dp phone, a tablet — and at large
/// system text, and fail on any overflow.
///
/// This is not hypothetical coverage: writing it turned up a live overflow in
/// the drone-pairing card, on the home screen, in the state a fresh install
/// starts in.

class _FakeDroneService extends DroneService {
  @override
  Future<AssignedDroneEntity?> fetchStatus() async => null;
}

class _FakeMissionService extends MissionService {
  @override
  Future<List<MissionReportEntity>> fetchMissions() async => [];
}

/// Answers locally so no test waits on a socket.
class _FakeCropService extends CropCatalogService {
  @override
  Future<({List<CropCatalogItem> crops, CropCatalogItem weeds})> fetchCatalog({
    int? month,
  }) async {
    CropCatalogItem crop(String id, String name, String local, bool season) =>
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
        crop('soybean', 'Soybean', 'Soyabean / सोयाबीन', true),
        crop('rice', 'Rice', 'Dhan / धान', true),
        crop('maize', 'Maize', 'Makka / मक्का', true),
        crop('wheat', 'Wheat', 'Gehun / गेहूँ', false),
        crop('gram', 'Gram', 'Chana / चना', false),
        crop('mustard', 'Mustard', 'Sarson / सरसों', false),
      ],
      weeds: crop('weeds', 'Weeds', 'खरपतवार', true),
    );
  }
}

/// The sizes worth caring about, in logical pixels.
const _screens = <String, Size>{
  'small phone (320)': Size(320, 640),
  'phone (360)': Size(360, 800),
  'large phone (412)': Size(412, 915),
  'tablet (768)': Size(768, 1024),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Sets the surface, pumps, and fails on any layout exception.
  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        // Built from the view, not from a bare MediaQueryData(): that
        // constructor defaults `size` to zero, so everything lays out at 0x0,
        // nothing overflows, and the test passes while measuring nothing.
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );
    // Three pumps, not one. GlobalMaterialLocalizations resolves
    // asynchronously, so Localizations withholds its subtree for a frame; the
    // page's initState — and therefore its first load() — only runs after
    // that. A single pump leaves every screen showing its spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Widget wrapHome() => MultiBlocProvider(
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
  );

  Widget wrapCropScan({AppLanguage language = AppLanguage.english}) =>
      MultiBlocProvider(
        providers: [
          BlocProvider<CropCubit>(
            create: (_) => CropCubit(service: _FakeCropService()),
          ),
          BlocProvider<LanguageCubit>(create: (_) => LanguageCubit()),
        ],
        // Mirrors App's own configuration. Supplying only the app delegate
        // leaves MaterialApp without MaterialLocalizations for `hi`, which
        // throws — so this doubles as a check that the real wiring is right.
        child: MaterialApp(
          locale: language.locale,
          localizationsDelegates: [
            AppStringsDelegate(language),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLanguage.values.map((l) => l.locale),
          home: const CropScanPage(),
        ),
      );

  group('home page fits', () {
    for (final entry in _screens.entries) {
      testWidgets('on a ${entry.key}', (tester) async {
        await pumpAt(tester, entry.value, wrapHome());
        expect(
          tester.takeException(),
          isNull,
          reason: 'home page overflowed at ${entry.value.width} dp',
        );
      });
    }

    testWidgets('at 1.3x system text on a small phone', (tester) async {
      // The size a farmer who cannot read small print actually uses.
      await pumpAt(tester, const Size(320, 640), wrapHome(), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scan with Phone fits', () {
    for (final entry in _screens.entries) {
      testWidgets('on a ${entry.key}', (tester) async {
        await pumpAt(tester, entry.value, wrapCropScan());
        expect(
          tester.takeException(),
          isNull,
          reason: 'crop picker overflowed at ${entry.value.width} dp',
        );
        expect(find.text('Soybean'), findsOneWidget);
      });
    }

    testWidgets('at 1.4x system text', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 800),
        wrapCropScan(),
        textScale: 1.4,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wider screen gets more columns, not wider tiles', (
      tester,
    ) async {
      // The whole point of sizing by maximum tile width rather than a fixed
      // column count. On a tablet the old `crossAxisCount: 3` gave three tiles
      // ~240 dp wide; what a tablet should show is *more crops*, at the same
      // readable size.
      int columnsInFirstRow() {
        final tiles = find.byType(InkWell).evaluate().toList();
        final tops = <double, int>{};
        for (final element in tiles) {
          final box = element.renderObject as RenderBox?;
          if (box == null || !box.hasSize) continue;
          final dy = box.localToGlobal(Offset.zero).dy;
          // Round: tiles in a row share a top to within sub-pixel noise.
          tops[dy.roundToDouble()] = (tops[dy.roundToDouble()] ?? 0) + 1;
        }
        // The grid rows are the crowded ones; the intro card is a lone InkWell.
        return tops.values.isEmpty
            ? 0
            : tops.values.reduce((a, b) => a > b ? a : b);
      }

      double tileWidth() =>
          tester.getSize(find.ancestor(
            of: find.text('Soybean'),
            matching: find.byType(InkWell),
          ).first).width;

      await pumpAt(tester, const Size(320, 640), wrapCropScan());
      final narrowColumns = columnsInFirstRow();
      final narrowTile = tileWidth();

      await pumpAt(tester, const Size(768, 1024), wrapCropScan());
      final wideColumns = columnsInFirstRow();
      final wideTile = tileWidth();

      expect(
        wideColumns,
        greaterThan(narrowColumns),
        reason: 'a tablet should fit more crops per row, not stretch them',
      );
      // Tiles stay in the same size band rather than ballooning.
      expect(
        wideTile,
        lessThan(narrowTile * 2),
        reason: 'tiles stretched instead of the column count growing',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows crops only — no weeds tile', (tester) async {
      // Weed pressure is a measurement over a whole field; a close-up of one
      // plant cannot answer it, so that work lives on the drone.
      await pumpAt(tester, const Size(360, 800), wrapCropScan());
      expect(find.text('Weeds'), findsNothing);
      expect(find.text('Soybean'), findsOneWidget);
    });
  });

  group('language', () {
    testWidgets('Hindi renders the picker without overflowing', (tester) async {
      // Devanagari sets taller and often wider than the Latin equivalent, so
      // a layout that fits in English can still break in Hindi.
      await pumpAt(
        tester,
        const Size(320, 640),
        wrapCropScan(language: AppLanguage.hindi),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('फोन से जाँच करें'), findsOneWidget);
    });

    testWidgets('English is the default and the fallback', (tester) async {
      await pumpAt(tester, const Size(360, 800), wrapCropScan());
      expect(find.text('Scan with Phone'), findsOneWidget);
    });

    testWidgets('an unknown language code falls back to English', (
      tester,
    ) async {
      expect(AppLanguage.fromCode('fr'), AppLanguage.english);
      expect(AppLanguage.fromCode(null), AppLanguage.english);
      expect(AppLanguage.fromCode('hi'), AppLanguage.hindi);
    });

    testWidgets('every string has a Hindi rendering', (tester) async {
      // A half-translated screen is worse than an English one: it reads as
      // broken rather than as unsupported. This catches an entry added in
      // English and never given its pair.
      const en = AppStrings(AppLanguage.english);
      const hi = AppStrings(AppLanguage.hindi);

      final pairs = <String, (String, String)>{
        'scanTitle': (en.scanTitle, hi.scanTitle),
        'scanIntroTitle': (en.scanIntroTitle, hi.scanIntroTitle),
        'scanIntroBody': (en.scanIntroBody, hi.scanIntroBody),
        'takePhoto': (en.takePhoto, hi.takePhoto),
        'gallery': (en.gallery, hi.gallery),
        'photographThePlant': (en.photographThePlant, hi.photographThePlant),
        'framingHint': (en.framingHint, hi.framingHint),
        'scanResult': (en.scanResult, hi.scanResult),
        'knowMore': (en.knowMore, hi.knowMore),
        'knowMoreHint': (en.knowMoreHint, hi.knowMoreHint),
        'cropAdvisor': (en.cropAdvisor, hi.cropAdvisor),
        'askAQuestion': (en.askAQuestion, hi.askAQuestion),
        'treatment': (en.treatment, hi.treatment),
        'languageLabel': (en.languageLabel, hi.languageLabel),
        'chooseLanguage': (en.chooseLanguage, hi.chooseLanguage),
        'languageNote': (en.languageNote, hi.languageNote),
        'whatToDo': (en.whatToDo, hi.whatToDo),
        'whatToLookFor': (en.whatToLookFor, hi.whatToLookFor),
        'disclaimerShort': (en.disclaimerShort, hi.disclaimerShort),
      };

      pairs.forEach((name, value) {
        expect(
          value.$2,
          isNot(equals(value.$1)),
          reason: '"$name" is not translated — it returns the English string '
              'in Hindi',
        );
        expect(value.$2.trim(), isNotEmpty, reason: '"$name" is blank in Hindi');
      });
    });

    testWidgets('the advisor is told which language to answer in', (
      tester,
    ) async {
      // Passed explicitly rather than inferred from the farmer's typing:
      // somebody who sets the app to Hindi still types crop names in English.
      expect(AppLanguage.hindi.advisorName, contains('Hindi'));
      expect(AppLanguage.english.advisorName, 'English');
    });
  });
}
