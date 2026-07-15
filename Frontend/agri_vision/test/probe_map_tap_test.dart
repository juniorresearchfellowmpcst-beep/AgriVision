import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('bare FlutterMap onTap fires', (tester) async {
    LatLng? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(23.19, 77.42),
              initialZoom: 17,
              onTap: (p, latLng) => tapped = latLng,
            ),
            children: const [],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tapped, isNotNull);
  });
}
