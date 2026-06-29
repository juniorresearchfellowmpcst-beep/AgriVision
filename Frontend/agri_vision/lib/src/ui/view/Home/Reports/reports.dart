import 'package:flutter/material.dart';

/// Reports tab — historical detection reports/analytics.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const Center(child: Text('Reports')),
    );
  }
}
