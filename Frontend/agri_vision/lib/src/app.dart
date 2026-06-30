import 'package:agri_vision/splash_screen.dart';
import 'package:agri_vision/src/ui/cubit/app/app_cubit.dart';
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
        BlocProvider<SidebarCubit>(create: (context) => SidebarCubit()),
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
