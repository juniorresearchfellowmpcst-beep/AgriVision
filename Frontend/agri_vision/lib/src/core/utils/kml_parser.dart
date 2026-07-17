import 'package:latlong2/latlong.dart';

/// Minimal KML reader for mission-boundary import.
///
/// Pulls every `<coordinates>` block out of the document (Polygon,
/// LineString and Point placemarks as exported by Google Earth / My Maps),
/// so a full XML dependency is not needed. KML stores each tuple as
/// `lon,lat[,alt]` separated by whitespace.
class KmlParser {
  const KmlParser._();

  /// Markers get unusable past this count, so dense tracks are thinned
  /// evenly down to it.
  static const int maxPoints = 100;

  static final RegExp _coordinatesBlock = RegExp(
    r'<coordinates[^>]*>(.*?)</coordinates>',
    dotAll: true,
    caseSensitive: false,
  );

  /// Returns the coordinates found in [kml] in document order,
  /// or an empty list if the file contains none.
  static List<LatLng> parse(String kml) {
    final points = <LatLng>[];
    for (final block in _coordinatesBlock.allMatches(kml)) {
      final blockPoints = <LatLng>[];
      for (final tuple in block.group(1)!.trim().split(RegExp(r'\s+'))) {
        final parts = tuple.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lon == null || lat == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
        blockPoints.add(LatLng(lat, lon));
      }

      // KML polygons close the ring by repeating the first vertex; the
      // mission polygon closes itself, so drop the duplicate.
      if (blockPoints.length > 1 && blockPoints.first == blockPoints.last) {
        blockPoints.removeLast();
      }
      points.addAll(blockPoints);
    }

    return _thin(points, maxPoints);
  }

  static List<LatLng> _thin(List<LatLng> points, int max) {
    if (points.length <= max) return points;
    final step = points.length / max;
    return [for (var i = 0; i < max; i++) points[(i * step).floor()]];
  }
}
