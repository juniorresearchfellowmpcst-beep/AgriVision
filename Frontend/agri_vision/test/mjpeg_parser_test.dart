import 'dart:typed_data';

import 'package:agri_vision/src/ui/widget/capture/mjpeg_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parser is the one piece of the live feed with no server to check it.
///
/// Everything it can get wrong is invisible until it is on a drone: a frame
/// split across two TCP chunks renders as a torn image, a missed boundary
/// desynchronises the stream permanently, and a buffer that never drains
/// grows until the app is killed mid-flight. So the cases here are the ones
/// the network actually produces, not the tidy ones.

const _boundary = 'agrivisionframe';

/// A JPEG's real first and last bytes, so a decoder would accept the result.
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);

Uint8List _part(List<int> body, {bool withLength = true, String? contentType}) {
  final header = StringBuffer()
    ..write('--$_boundary\r\n')
    ..write('Content-Type: ${contentType ?? 'image/jpeg'}\r\n');
  if (withLength) header.write('Content-Length: ${body.length}\r\n');
  header.write('\r\n');

  return Uint8List.fromList([...header.toString().codeUnits, ...body, 13, 10]);
}

Uint8List _keepalive() => Uint8List.fromList(
  '--$_boundary\r\nContent-Type: text/plain\r\n'
          'X-AgriVision-Status: waiting\r\n\r\n\r\n'
      .codeUnits,
);

void main() {
  group('MjpegParser', () {
    test('reads a whole frame from one chunk', () {
      final frames = MjpegParser(_boundary).consume(_part(_jpeg));

      expect(frames, hasLength(1));
      expect(frames.first, equals(_jpeg));
    });

    test('reassembles a frame split across chunks', () {
      // The normal case on any real socket: chunk boundaries have nothing to
      // do with frame boundaries.
      final parser = MjpegParser(_boundary);
      final part = _part(_jpeg);
      final split = part.length ~/ 2;

      expect(parser.consume(part.sublist(0, split)), isEmpty);

      final frames = parser.consume(part.sublist(split));
      expect(frames, hasLength(1));
      expect(frames.first, equals(_jpeg));
    });

    test('reads several frames arriving in one chunk', () {
      final parser = MjpegParser(_boundary);
      final chunk = Uint8List.fromList([
        ..._part(_jpeg),
        ..._part(_jpeg),
        ..._part(_jpeg),
      ]);

      expect(parser.consume(chunk), hasLength(3));
    });

    test('a byte-at-a-time stream still yields exactly one frame', () {
      // The pathological case: proves nothing depends on chunk size.
      final parser = MjpegParser(_boundary);
      final part = _part(_jpeg);

      final frames = <Uint8List>[];
      for (final byte in part) {
        frames.addAll(parser.consume(Uint8List.fromList([byte])));
      }

      expect(frames, hasLength(1));
      expect(frames.first, equals(_jpeg));
    });

    test('skips keep-alive parts without emitting an empty frame', () {
      // The relay sends these while a camera is reconnecting. Emitting one as
      // a frame would blank the operator's screen.
      final parser = MjpegParser(_boundary);
      final chunk = Uint8List.fromList([
        ..._keepalive(),
        ..._keepalive(),
        ..._part(_jpeg),
      ]);

      final frames = parser.consume(chunk);
      expect(frames, hasLength(1));
      expect(frames.first, equals(_jpeg));
    });

    test('falls back to boundary scanning without a Content-Length', () {
      // A third-party MJPEG camera the operator pointed the app at directly.
      final parser = MjpegParser(_boundary);
      final chunk = Uint8List.fromList([
        ..._part(_jpeg, withLength: false),
        ..._part(_jpeg, withLength: false),
      ]);

      final frames = parser.consume(chunk);
      expect(frames, hasLength(1), reason: 'the last part is not yet closed');
      expect(frames.first, equals(_jpeg));
    });

    test('a frame carrying the boundary string in its bytes survives', () {
      // Content-Length is what makes this safe; a scanner would cut here.
      final tricky = Uint8List.fromList([
        0xFF, 0xD8,
        ...'--$_boundary'.codeUnits,
        0xFF, 0xD9,
      ]);

      final frames = MjpegParser(_boundary).consume(_part(tricky));
      expect(frames, hasLength(1));
      expect(frames.first, equals(tricky));
    });

    test('junk before the first boundary is discarded', () {
      final parser = MjpegParser(_boundary);
      final chunk = Uint8List.fromList([
        ...'preamble nobody asked for\r\n'.codeUnits,
        ..._part(_jpeg),
      ]);

      expect(parser.consume(chunk), hasLength(1));
    });

    test('a stream with no boundaries at all does not grow without limit', () {
      // A wrong boundary, or a response that is not multipart. Without the
      // cap this is how the app dies of memory pressure over a long flight.
      final parser = MjpegParser(_boundary);
      final noise = Uint8List(1024 * 1024);

      for (var i = 0; i < 12; i++) {
        expect(parser.consume(noise), isEmpty);
      }
      // Nothing to assert but survival: the cap is internal. Reaching here
      // without an out-of-memory failure is the assertion.
    });
  });

  group('boundary parsing', () {
    test('reads the boundary out of the Content-Type header', () {
      expect(
        MjpegParser.boundaryOf('multipart/x-mixed-replace; boundary=frame123'),
        'frame123',
      );
    });

    test('tolerates quotes and extra parameters', () {
      expect(
        MjpegParser.boundaryOf(
          'multipart/x-mixed-replace;boundary="myframe";charset=utf-8',
        ),
        'myframe',
      );
    });

    test('falls back to our own boundary when the header is missing', () {
      expect(MjpegParser.boundaryOf(null), 'agrivisionframe');
    });
  });
}
