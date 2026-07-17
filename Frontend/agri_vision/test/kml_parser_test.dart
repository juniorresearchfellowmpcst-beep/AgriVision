import 'package:agri_vision/src/core/utils/kml_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Field Block A</name>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              77.42020,23.19180,0 77.42074,23.19200,0
              77.42193,23.19200,0 77.42247,23.19180,0
              77.42020,23.19180,0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <Point><coordinates>77.4213,23.1913</coordinates></Point>
    </Placemark>
  </Document>
</kml>
''';

void main() {
  test('parses polygon + point, dropping the closing duplicate vertex', () {
    final pts = KmlParser.parse(_sample);
    expect(pts, hasLength(5)); // 4 unique polygon vertices + 1 point
    expect(pts.first.latitude, 23.19180);
    expect(pts.first.longitude, 77.42020);
    expect(pts.last.latitude, 23.1913);
  });

  test('returns empty list for a KML without coordinates', () {
    expect(KmlParser.parse('<kml></kml>'), isEmpty);
  });

  test('ignores malformed tuples and out-of-range values', () {
    const kml = '''
      <coordinates>
        garbage 200.0,95.0,0 77.1,23.1,0
      </coordinates>''';
    final pts = KmlParser.parse(kml);
    expect(pts, hasLength(1));
    expect(pts.single.longitude, 77.1);
  });

  test('thins dense tracks down to maxPoints', () {
    final tuples = [
      for (var i = 0; i < 500; i++) '77.${1000 + i},23.${1000 + i},0',
    ].join(' ');
    final pts = KmlParser.parse('<coordinates>$tuples</coordinates>');
    expect(pts, hasLength(KmlParser.maxPoints));
  });
}
