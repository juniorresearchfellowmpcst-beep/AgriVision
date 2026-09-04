import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/networks/api_config.dart';
import '../../../core/theme/theme.dart';

/// Live video from the drone, rendered from the backend's MJPEG relay.
///
/// The drone's cameras speak RTSP, which a phone cannot decode without a heavy
/// native player, and which it often cannot even reach — the cameras are on
/// the aircraft's network and the handset may be on a different one. The
/// backend is on that network already (it holds the MAVLink link), so it
/// decodes once and re-serves the feed as `multipart/x-mixed-replace`: a
/// stream of JPEGs, which is the one video format every HTTP client can read
/// with no plugin at all.
///
/// What this widget is really responsible for is being **honest about the
/// link**. A drone flies out of range, a camera browns out, Wi-Fi drops — and
/// the worst possible behaviour is to leave the last good frame on screen
/// looking current. So a stalled feed says it has stalled, a reconnecting one
/// says so, and the picture is dimmed the moment it stops being live.
class MjpegView extends StatefulWidget {
  const MjpegView({
    super.key,
    required this.streamUrl,
    this.fallbackFrameUrl,
    this.fit = BoxFit.cover,
    this.onStateChanged,
    this.paused = false,
  });

  /// The relay endpoint, e.g.
  /// `http://10.0.0.4:5000/api/capture/cameras/3/stream?fps=12&width=960`.
  final String streamUrl;

  /// Single-JPEG endpoint used when the platform cannot stream at all.
  ///
  /// Flutter web has no usable streaming HTTP client, so there the widget
  /// polls this instead. It is a worse experience — one request per frame —
  /// but it is a picture rather than an error.
  final String? fallbackFrameUrl;

  final BoxFit fit;

  /// Called whenever the connection state changes, so a parent can show a
  /// chip in its app bar without owning the socket.
  final ValueChanged<MjpegConnectionState>? onStateChanged;

  /// Stop reading without tearing the widget down — used when the page is
  /// covered or the app is backgrounded. Bandwidth on a field link is worth
  /// more than an instant resume.
  final bool paused;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

enum MjpegConnectionState { connecting, live, reconnecting, paused, failed }

class _MjpegViewState extends State<MjpegView> with WidgetsBindingObserver {
  final Dio _dio = Dio(
    ApiConfig.options(
      // A live stream never "finishes", so a receive timeout would kill a
      // perfectly healthy feed. The stall detector below is what decides a
      // feed has died — it can tell "no frames" from "no response", which a
      // transport timeout cannot.
      receiveTimeout: Duration.zero,
    ),
  );

  /// The current frame, held outside setState so a 12 fps feed repaints one
  /// Image rather than rebuilding the page around it.
  final ValueNotifier<Uint8List?> _frame = ValueNotifier<Uint8List?>(null);

  CancelToken? _cancel;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _stallTimer;
  Timer? _pollTimer;

  MjpegConnectionState _state = MjpegConnectionState.connecting;
  String? _error;
  int _attempt = 0;
  bool _disposed = false;

  /// A feed that has produced nothing for this long is not live, whatever the
  /// socket thinks. Matches the backend's own stall timeout.
  static const _stallAfter = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.paused) _connect();
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _disconnect();
      _frame.value = null;
      if (!widget.paused) _connect();
    } else if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _disconnect();
        _setState(MjpegConnectionState.paused);
      } else {
        _connect();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app holding an open video stream drains the handset and
    // the field link for a picture nobody is looking at.
    if (state == AppLifecycleState.resumed) {
      if (!widget.paused && _subscription == null && _pollTimer == null) {
        _connect();
      }
    } else {
      _disconnect();
      _setState(MjpegConnectionState.paused);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    _frame.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  // ── connection ─────────────────────────────────────────────────────────

  void _setState(MjpegConnectionState next, {String? error}) {
    if (_disposed || (_state == next && error == _error)) return;
    setState(() {
      _state = next;
      _error = error;
    });
    widget.onStateChanged?.call(next);
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _disconnect();

    // Web's HTTP client cannot hand back a response body as it arrives, so
    // there is nothing to parse incrementally. Poll instead of pretending.
    if (kIsWeb) {
      if (widget.fallbackFrameUrl != null) {
        _startPolling();
      } else {
        _setState(
          MjpegConnectionState.failed,
          error: 'Live video is not supported in the browser build.',
        );
      }
      return;
    }

    _setState(
      _frame.value == null
          ? MjpegConnectionState.connecting
          : MjpegConnectionState.reconnecting,
    );

    final cancel = CancelToken();
    _cancel = cancel;

    try {
      final response = await _dio.get<ResponseBody>(
        widget.streamUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: await ApiConfig.authHeaders(),
        ),
        cancelToken: cancel,
      );

      if (_disposed || cancel.isCancelled) return;

      final status = response.statusCode ?? 0;
      if (status != 200) {
        // The backend answers a refusal as JSON — "camera is switched off",
        // "too many viewers" — and that message is the whole point of asking.
        _scheduleReconnect(await _readErrorMessage(response));
        return;
      }

      final parser = MjpegParser(
        MjpegParser.boundaryOf(response.headers.value('content-type')),
      );

      _subscription = response.data!.stream.listen(
        (chunk) {
          for (final jpeg in parser.consume(chunk)) {
            _onFrame(jpeg);
          }
        },
        onError: (Object error) =>
            _scheduleReconnect(_describe(error)),
        onDone: () => _scheduleReconnect('The feed ended.'),
        cancelOnError: true,
      );

      _armStallTimer();
    } catch (error) {
      if (_disposed || cancel.isCancelled) return;
      _scheduleReconnect(_describe(error));
    }
  }

  void _onFrame(Uint8List jpeg) {
    if (_disposed) return;
    _attempt = 0;
    _frame.value = jpeg;
    if (_state != MjpegConnectionState.live) {
      _setState(MjpegConnectionState.live);
    }
    _armStallTimer();
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      // Socket open, no pictures. Reconnecting is more likely to recover than
      // waiting, and either way the operator must stop seeing a stale frame
      // presented as the view from the aircraft.
      _scheduleReconnect('The camera stopped sending frames.');
    });
  }

  void _scheduleReconnect(String? reason) {
    if (_disposed || widget.paused) return;
    _disconnect();
    _setState(MjpegConnectionState.reconnecting, error: reason);

    // Back off, but never far: an operator watching a black rectangle needs
    // it back the instant the link returns.
    _attempt = (_attempt + 1).clamp(1, 5);
    final delay = Duration(milliseconds: 400 * (1 << (_attempt - 1)));
    Timer(delay, () {
      if (!_disposed && !widget.paused) _connect();
    });
  }

  void _disconnect() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _cancel?.cancel();
    _cancel = null;
  }

  // ── the browser fallback ───────────────────────────────────────────────

  void _startPolling() {
    _setState(MjpegConnectionState.connecting);
    Future<void> tick(_) async {
      if (_disposed || widget.paused) return;
      try {
        final response = await _dio.get<List<int>>(
          '${widget.fallbackFrameUrl}&t=${DateTime.now().millisecondsSinceEpoch}',
          options: Options(
            responseType: ResponseType.bytes,
            headers: await ApiConfig.authHeaders(),
          ),
        );
        if (response.statusCode == 200 && response.data != null) {
          _onFrame(Uint8List.fromList(response.data!));
        }
      } catch (_) {
        // A missed poll is not a broken feed; the next tick tries again.
      }
    }

    tick(null);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), tick);
  }

  Future<String?> _readErrorMessage(Response<ResponseBody> response) async {
    try {
      final bytes = <int>[];
      await for (final chunk in response.data!.stream.take(8)) {
        bytes.addAll(chunk);
      }
      final text = String.fromCharCodes(bytes);
      final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
      return match?.group(1) ?? 'The feed answered ${response.statusCode}.';
    } catch (_) {
      return 'The feed answered ${response.statusCode}.';
    }
  }

  String _describe(Object error) {
    if (error is DioException) return ApiConfig.friendlyDioError(error);
    return error.toString();
  }

  // ── painting ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<Uint8List?>(
            valueListenable: _frame,
            builder: (context, bytes, _) {
              if (bytes == null) return const SizedBox.expand();
              return Opacity(
                // The single most important pixel in this widget: a frame
                // that is no longer live must not look like one that is.
                opacity: _state == MjpegConnectionState.live ? 1.0 : 0.45,
                child: Image.memory(
                  bytes,
                  fit: widget.fit,
                  // Without this every frame clears the canvas first and the
                  // feed strobes.
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
              );
            },
          ),
          if (_state != MjpegConnectionState.live) _overlay(),
        ],
      ),
    );
  }

  Widget _overlay() {
    final (icon, label) = switch (_state) {
      MjpegConnectionState.connecting => (null, 'Connecting to the camera…'),
      MjpegConnectionState.reconnecting => (null, 'Signal lost — reconnecting…'),
      MjpegConnectionState.paused => (Icons.pause_circle_outline, 'Feed paused'),
      MjpegConnectionState.failed => (Icons.videocam_off_outlined, 'No feed'),
      MjpegConnectionState.live => (null, ''),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, color: AppColors.light100.withValues(alpha: 0.85), size: 40)
            else
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(AppColors.light100),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyle.textSmMedium.copyWith(color: AppColors.light100),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.light100.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pulls whole JPEGs out of a `multipart/x-mixed-replace` byte stream.
///
/// Chunks off the socket have nothing to do with frame boundaries: one chunk
/// can hold the tail of one frame, a whole second frame, and the first byte of
/// a third. So bytes accumulate here until a complete part is present.
///
/// Our relay sends `Content-Length` on every part, which makes this exact
/// rather than a guess. When it is missing — a third-party MJPEG camera the
/// operator pointed the app at directly — the parser falls back to scanning
/// for the next boundary, which is slower but correct.
@visibleForTesting
class MjpegParser {
  MjpegParser(String boundary)
    : _boundary = Uint8List.fromList('--$boundary'.codeUnits);

  /// The multipart separator the server named in its Content-Type header.
  ///
  /// Falls back to our relay's own boundary rather than failing: a stream
  /// that arrives with a malformed header is still very likely ours.
  static String boundaryOf(String? contentType) {
    final match = RegExp(
      r'boundary=([^;\s]+)',
      caseSensitive: false,
    ).firstMatch(contentType ?? '');
    return match?.group(1)?.replaceAll('"', '') ?? 'agrivisionframe';
  }

  final Uint8List _boundary;
  Uint8List _buffer = Uint8List(0);

  static final Uint8List _headerEnd = Uint8List.fromList('\r\n\r\n'.codeUnits);

  /// Frames completed by this chunk, in order. Usually zero or one.
  List<Uint8List> consume(Uint8List chunk) {
    _buffer = _append(_buffer, chunk);

    final frames = <Uint8List>[];
    while (true) {
      final frame = _next();
      if (frame == null) break;
      if (frame.isNotEmpty) frames.add(frame);
    }

    // A runaway buffer means we are not finding boundaries at all — a wrong
    // boundary string, or something that is not multipart. Drop it rather
    // than growing until the app is killed.
    if (_buffer.length > 8 * 1024 * 1024) _buffer = Uint8List(0);

    return frames;
  }

  /// One part, or null when the buffer does not hold a complete one yet.
  /// An empty result means a part that carried no image (a keep-alive).
  Uint8List? _next() {
    final start = _indexOf(_buffer, _boundary, 0);
    if (start < 0) return null;

    final headerEnd = _indexOf(_buffer, _headerEnd, start);
    if (headerEnd < 0) return null;

    final bodyStart = headerEnd + _headerEnd.length;
    final headers = String.fromCharCodes(
      _buffer.sublist(start, headerEnd),
    ).toLowerCase();

    if (!headers.contains('image/')) {
      // A keep-alive part. Consume it and look for the next boundary.
      final nextBoundary = _indexOf(_buffer, _boundary, bodyStart);
      if (nextBoundary < 0) {
        // Nothing after it yet — keep the boundary so the next chunk can
        // complete the part rather than losing its header.
        if (_buffer.length - bodyStart > 4096) {
          _buffer = _buffer.sublist(bodyStart);
        }
        return null;
      }
      _buffer = _buffer.sublist(nextBoundary);
      return Uint8List(0);
    }

    final length = _contentLength(headers);
    if (length != null) {
      if (_buffer.length < bodyStart + length) return null;
      final frame = _buffer.sublist(bodyStart, bodyStart + length);
      _buffer = _buffer.sublist(bodyStart + length);
      return frame;
    }

    // No Content-Length: the frame runs to the next boundary.
    final nextBoundary = _indexOf(_buffer, _boundary, bodyStart);
    if (nextBoundary < 0) return null;
    var end = nextBoundary;
    // Trim the CRLF the sender puts before the boundary.
    if (end >= 2 && _buffer[end - 2] == 13 && _buffer[end - 1] == 10) end -= 2;
    final frame = _buffer.sublist(bodyStart, end);
    _buffer = _buffer.sublist(nextBoundary);
    return frame;
  }

  static int? _contentLength(String headers) {
    final match = RegExp(r'content-length:\s*(\d+)').firstMatch(headers);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static Uint8List _append(Uint8List a, Uint8List b) {
    if (a.isEmpty) return b;
    final joined = Uint8List(a.length + b.length);
    joined.setRange(0, a.length, a);
    joined.setRange(a.length, joined.length, b);
    return joined;
  }

  static int _indexOf(Uint8List haystack, Uint8List needle, int from) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    final last = haystack.length - needle.length;
    final first = needle[0];
    outer:
    for (var i = from < 0 ? 0 : from; i <= last; i++) {
      if (haystack[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
