import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';

/// Example of how the Home screen (or any top-level screen) should be
/// wrapped so [AppBottomNavBar] and [NavigationHandler] work together.
///
/// `SidebarCubit` is provided once, high enough in the tree (e.g. above
/// `MaterialApp` or directly above `NavigationHandler`) so it survives
/// across the `pushReplacementNamed` calls `NavigationHandler` performs —
/// otherwise a fresh Cubit would be created on every navigation and the
/// bottom bar would lose its selection.
///
/// Example wiring in your app root:
///
///   BlocProvider(
///     create: (_) => SidebarCubit(),
///     child: MaterialApp(
///       navigatorKey: AppRouter.navigationKey,
///       onGenerateRoute: AppRouter.onGenerateRoute,
///       builder: (context, child) => NavigationHandler(child: child!),
///       initialRoute: AppRouterNames.home,
///     ),
///   )
///
/// Then each screen (Home, Maps, Alerts, Reports, Settings) reuses the
/// same Scaffold + AppBottomNavBar pattern shown below.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Home content')),
    );
  }
}
