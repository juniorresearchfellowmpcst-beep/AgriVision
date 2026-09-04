import 'package:agri_vision/splash_screen.dart';
import 'package:agri_vision/src/ui/cubit/app/app_cubit.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/alerts/alerts_cubit.dart';
import 'package:agri_vision/src/ui/cubit/capture/capture_cubit.dart';
import 'package:agri_vision/src/ui/cubit/credentials/credentials_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/livefeed/live_feed_cubit.dart';
import 'package:agri_vision/src/ui/cubit/spray/spray_cubit.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/cubit/profile/profile_cubit.dart';
import 'package:agri_vision/src/ui/cubit/reports/reports_cubit.dart';
import 'package:agri_vision/src/ui/cubit/settings/settings_cubit.dart';
import 'package:agri_vision/src/ui/cubit/system/system_cubit.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/cubit/language/language_cubit.dart';
import 'package:agri_vision/src/ui/cubit/theme/theme_cubit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src.dart';

class App extends StatelessWidget {
  const App({required AppRepository appRepository, super.key})
    : _appRepository = appRepository;

  final AppRepository _appRepository;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AppCubit>(
          create: (context) => AppCubit(repository: _appRepository),
        ),
        BlocProvider<BottomNavBarCubit>(
          create: (context) => BottomNavBarCubit(),
        ),
        BlocProvider<AuthCubit>(create: (context) => AuthCubit()),
        // Feature cubits are app-scoped so tab switches keep their data;
        // each page triggers load() lazily on first build.
        BlocProvider<DroneCubit>(create: (context) => DroneCubit()),
        BlocProvider<MissionsCubit>(create: (context) => MissionsCubit()),
        // The MAVLink link outlives any single screen: planning uploads the
        // mission, the live screen polls telemetry off the same connection.
        BlocProvider<MavlinkCubit>(create: (context) => MavlinkCubit()),
        BlocProvider<AlertsCubit>(create: (context) => AlertsCubit()),
        BlocProvider<ReportsCubit>(create: (context) => ReportsCubit()),
        BlocProvider<ProfileCubit>(create: (context) => ProfileCubit()),
        // Preferences are shared by Settings and Profile, so one instance
        // keeps both screens showing the same toggle values.
        BlocProvider<SettingsCubit>(create: (context) => SettingsCubit()),
        BlocProvider<CredentialsCubit>(create: (context) => CredentialsCubit()),
        // A capture session outlives the capture screen: the operator shoots,
        // walks over to the spray page to prescribe from the shot, and comes
        // back to shoot again — all of it one session.
        BlocProvider<CaptureCubit>(create: (context) => CaptureCubit()),
        BlocProvider<SprayCubit>(create: (context) => SprayCubit()),
        BlocProvider<FieldScanCubit>(create: (context) => FieldScanCubit()),
        // The live scan runs on the *server*, so this cubit is app-scoped to
        // match: leaving the feed page stops the polling, not the scanning,
        // and coming back adopts the analysis that kept running meanwhile.
        BlocProvider<LiveFeedCubit>(create: (context) => LiveFeedCubit()),
        // Server connection details. App-scoped because the Settings
        // screen and the drone-connect sheet both need them, and the
        // answer changes with the network rather than with navigation.
        BlocProvider<SystemCubit>(create: (context) => SystemCubit()),
        // A survey outlives every screen it is watched from: the scan runs on
        // the server, so leaving the page stops the polling, not the flight,
        // and coming back adopts the run that kept going meanwhile.
        BlocProvider<SurveyCubit>(create: (context) => SurveyCubit()),
        // The crop catalogue is read once and used by the picker, the detail
        // screen and the survey's crop chips.
        BlocProvider<CropCubit>(create: (context) => CropCubit()),
        // The language belongs to the device, not the account, so it is read
        // once at startup and lives above everything that renders text.
        BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()..load()),
        BlocProvider<LanguageCubit>(
          create: (context) => LanguageCubit()..load(),
        ),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => __AppViewState();
}

class __AppViewState extends State<_AppView> {
  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app on a language or theme change, which is what
    // makes either setting take effect immediately instead of on the next
    // launch.
    return BlocBuilder<LanguageCubit, LanguageState>(
      builder: (context, language) {
        return BlocConsumer<ThemeCubit, ThemeState>(
          listenWhen: (a, b) => a.mode != b.mode,
          // AppColors reads a global rather than an InheritedWidget, so
          // nothing marks the widgets that use it as needing to repaint --
          // and a `const` subtree never rebuilds at all. Without this, the
          // theme changed on some of the screen and not the rest.
          listener: (_, __) => repaintAfterThemeChange(),
          builder: (context, themeState) {
            // Written *before* this frame builds: the widgets below resolve
            // their colours during build, so a palette set afterwards would
            // paint one frame in the old theme.
            AppColors.setPalette(themeState.mode.palette);
            return MaterialApp(
              scaffoldMessengerKey: Toast.scaffoldKey,
              navigatorKey: AppRouter.navigationKey,
              theme: AppTheme.standard,
              darkTheme: AppTheme.dark,
              themeMode: themeState.mode.material,
              title: "AgriVision",
              debugShowCheckedModeBanner: false,
              onGenerateRoute: AppRouter.onGenerateRoute,
              navigatorObservers: [AppRouter.routeObserver],

              // Driven by the app's own setting rather than the device locale: a
              // farmer handed a phone that boots in English still has to be able
              // to choose Hindi and have it stick.
              locale: language.language.locale,
              supportedLocales: AppLanguage.values.map((l) => l.locale),
              localizationsDelegates: [
                AppStringsDelegate(language.language),
                // Material's own strings — the text-selection menu, date pickers —
                // so a translated screen does not sprout English context menus.
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: SplashScreen(),
            );
          },
        );
      },
    );
  }
}
