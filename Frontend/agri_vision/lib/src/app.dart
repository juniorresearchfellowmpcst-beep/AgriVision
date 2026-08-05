import 'package:agri_vision/splash_screen.dart';
import 'package:agri_vision/src/ui/cubit/app/app_cubit.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/alerts/alerts_cubit.dart';
import 'package:agri_vision/src/ui/cubit/capture/capture_cubit.dart';
import 'package:agri_vision/src/ui/cubit/credentials/credentials_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/spray/spray_cubit.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/cubit/profile/profile_cubit.dart';
import 'package:agri_vision/src/ui/cubit/reports/reports_cubit.dart';
import 'package:agri_vision/src/ui/cubit/settings/settings_cubit.dart';
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
    return MaterialApp(
      scaffoldMessengerKey: Toast.scaffoldKey,
      navigatorKey: AppRouter.navigationKey,
      theme: AppTheme.standard,
      title: "AgriVision",
      debugShowCheckedModeBanner: false,
      onGenerateRoute: AppRouter.onGenerateRoute,
      navigatorObservers: [AppRouter.routeObserver],
      home: SplashScreen(),
    );
  }
}
