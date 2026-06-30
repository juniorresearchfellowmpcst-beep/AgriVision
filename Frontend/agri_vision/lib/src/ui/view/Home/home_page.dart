import 'package:flutter/material.dart';

/// Home tab — entry point for the home feature's presentation layer.
/// Replace the body with your dashboard widgets; wire it to a
/// HomeBloc/HomeCubit/HomeProvider that talks to the domain layer
/// (use cases) rather than calling data sources directly.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drone Detection')),
      body: const Center(child: Text('Home')),
    );
  }
}
