import 'package:flutter/material.dart';

/// Alerts tab — list/stream of drone detection alerts.
class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: const Center(child: Text('Alerts')),
    );
  }
}
