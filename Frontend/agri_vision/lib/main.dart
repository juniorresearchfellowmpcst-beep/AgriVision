import 'package:flutter/material.dart';
import 'package:agri_vision/splash_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,

      home: Scaffold(body: SplashScreen()),
    );
  }
}
