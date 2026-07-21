import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/constants/strorage_constants.dart';
import 'package:agri_vision/src/core/theme/theme.dart';

/// "Drone Runner" — the offline minigame, in the spirit of Chrome's dino run.
///
/// A little quadcopter skims over farmland: tap (or hold) to climb, let go to
/// descend, and weave through crop rows and birds. Speed ramps up with
/// distance; the best score is kept in [SharedPreferences] so it survives
/// restarts. Everything is drawn with a [CustomPainter] — no assets, no
/// packages, works fully offline.
class DroneRunnerPage extends StatelessWidget {
  const DroneRunnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── App bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.dark700,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Drone Runner', style: AppTextStyle.textLgBold),
                        Text(
                          'No connection needed — tap to jump',
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 18,
                    color: AppColors.dark100,
                  ),
                ],
              ),
            ),

            // ── Game canvas ────────────────────────────────────────────
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: DroneRunnerGame(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Game widget
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { ready, playing, dead }

class _Obstacle {
  _Obstacle({
    required this.x,
    required this.width,
    required this.height,
    required this.isBird,
    required this.top,
  });

  double x; // left edge, world units
  final double width;
  final double height;
  final bool isBird;
  final double top; // top edge, world units
}

class DroneRunnerGame extends StatefulWidget {
  const DroneRunnerGame({super.key});

  @override
  State<DroneRunnerGame> createState() => _DroneRunnerGameState();
}

class _DroneRunnerGameState extends State<DroneRunnerGame>
    with SingleTickerProviderStateMixin {
  // World: 160 x 100 units, scaled to the widget at paint time.
  static const double worldW = 160;
  static const double worldH = 100;
  static const double groundY = 86; // ground line
  static const double droneX = 30; // drone centre, fixed
  static const double cruiseY = 76; // hover altitude the drone returns to
  static const double gravity = 260; // units/s²
  static const double jumpVelocity = -105; // tap impulse (dino-style hop)
  static const double maxFall = 150;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final math.Random _random = math.Random();

  _Phase _phase = _Phase.ready;
  double _droneY = cruiseY; // centre of the drone
  double _velocity = 0;
  bool _jumping = false;
  double _speed = 45; // world units/s
  double _distance = 0; // total distance flown (for parallax)
  double _sinceSpawn = 999; // distance since the last obstacle spawned
  double _nextGap = 60; // distance until the next spawn
  double _time = 0; // wall-clock for animations
  double _score = 0;
  int _best = 0;
  final List<_Obstacle> _obstacles = [];

  @override
  void initState() {
    super.initState();
    _loadBest();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _best = prefs.getInt(StorageConstants.droneRunnerBestScore) ?? 0,
    );
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageConstants.droneRunnerBestScore, _best);
  }

  // ── Game loop ──────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    // Clamp dt so a paused app doesn't teleport the drone into a tree.
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    if (dt == 0) return;

    setState(() {
      _time += dt;
      if (_phase != _Phase.playing) return;

      // Physics: the drone cruises at a fixed altitude; a tap launches a hop
      // and gravity brings it straight back to cruise height (Chrome-dino
      // style — no continuous flapping needed).
      if (_jumping) {
        _velocity = (_velocity + gravity * dt).clamp(-999.0, maxFall);
        _droneY += _velocity * dt;
        if (_droneY >= cruiseY) {
          _droneY = cruiseY;
          _velocity = 0;
          _jumping = false;
        }
        if (_droneY < 6) {
          _droneY = 6;
          _velocity = 0;
        }
      }

      // Speed ramps with distance.
      _speed = math.min(110, _speed + 1.6 * dt);
      final step = _speed * dt;
      _distance += step;
      _sinceSpawn += step;
      _score += step * 0.12;

      // Move + cull obstacles (birds glide a little faster than the ground).
      for (final o in _obstacles) {
        o.x -= step + (o.isBird ? 14 * dt : 0);
      }
      _obstacles.removeWhere((o) => o.x + o.width < -10);

      // Spawn.
      if (_sinceSpawn >= _nextGap) {
        _spawnObstacle();
        _sinceSpawn = 0;
        _nextGap = 52 + _random.nextDouble() * 42;
      }

      // Collisions: drone hitbox, slightly forgiving.
      final droneRect = Rect.fromCenter(
        center: Offset(droneX, _droneY),
        width: 10,
        height: 5.4,
      );
      final hitObstacle = _obstacles.any(
        (o) => droneRect.overlaps(
          Rect.fromLTWH(o.x + 0.8, o.top + 0.8, o.width - 1.6, o.height - 1.6),
        ),
      );
      if (hitObstacle) _die();
    });
  }

  void _spawnObstacle() {
    final allowBirds = _score > 150;
    if (allowBirds && _random.nextDouble() < 0.3) {
      // Most birds glide in the cruise lane (jump over them); some fly at
      // hop height, punishing an unnecessary jump — so time your taps.
      final top = _random.nextDouble() < 0.7
          ? 70 + _random.nextDouble() * 3 // cruise lane
          : 60 + _random.nextDouble() * 5; // mid-air, hit only while jumping
      _obstacles.add(
        _Obstacle(x: worldW + 5, width: 8, height: 5, isBird: true, top: top),
      );
    } else {
      // A crop row / tree growing from the ground. Heights stay within what
      // a single hop (rise ≈ 21 units) can always clear.
      final height = 10 + _random.nextDouble() * 10;
      final width = 7 + _random.nextDouble() * 4;
      _obstacles.add(
        _Obstacle(
          x: worldW + 5,
          width: width,
          height: height,
          isBird: false,
          top: groundY - height,
        ),
      );
    }
  }

  void _die() {
    _phase = _Phase.dead;
    if (_score.floor() > _best) {
      _best = _score.floor();
      _saveBest();
    }
  }

  void _reset() {
    _obstacles.clear();
    _droneY = cruiseY;
    _velocity = 0;
    _jumping = false;
    _speed = 45;
    _distance = 0;
    _score = 0;
    _sinceSpawn = 999;
    _nextGap = 60;
  }

  void _jump() {
    // One hop at a time, like the dino: taps mid-air are ignored.
    if (_jumping) return;
    _jumping = true;
    _velocity = jumpVelocity;
  }

  void _handleTap() {
    setState(() {
      switch (_phase) {
        case _Phase.ready:
          _phase = _Phase.playing;
        case _Phase.playing:
          _jump();
        case _Phase.dead:
          _reset();
          _phase = _Phase.ready;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleTap(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: CustomPaint(
          size: Size.infinite,
          painter: _DroneRunnerPainter(
            phase: _phase,
            droneY: _droneY,
            velocity: _velocity,
            distance: _distance,
            time: _time,
            score: _score.floor(),
            best: _best,
            obstacles: _obstacles,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _DroneRunnerPainter extends CustomPainter {
  _DroneRunnerPainter({
    required this.phase,
    required this.droneY,
    required this.velocity,
    required this.distance,
    required this.time,
    required this.score,
    required this.best,
    required this.obstacles,
  });

  final _Phase phase;
  final double droneY;
  final double velocity;
  final double distance;
  final double time;
  final int score;
  final int best;
  final List<_Obstacle> obstacles;

  static const double worldW = _DroneRunnerGameState.worldW;
  static const double worldH = _DroneRunnerGameState.worldH;
  static const double groundY = _DroneRunnerGameState.groundY;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / worldW;
    final sy = size.height / worldH;

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF4EC), Color(0xFFF7FAF7)],
        ).createShader(Offset.zero & size),
    );

    _paintClouds(canvas, sx, sy);
    _paintGround(canvas, size, sx, sy);
    for (final o in obstacles) {
      if (o.isBird) {
        _paintBird(canvas, o, sx, sy);
      } else {
        _paintCrop(canvas, o, sx, sy);
      }
    }
    _paintDrone(canvas, sx, sy);
    _paintHud(canvas, size);
  }

  // ── Scenery ────────────────────────────────────────────────────────────

  void _paintClouds(Canvas canvas, double sx, double sy) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    // Three clouds on a slow parallax loop.
    for (var i = 0; i < 3; i++) {
      final loop = worldW + 50;
      final x = (worldW - ((distance * 0.25) + i * 65) % loop) + 20;
      final y = 14.0 + i * 9;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x * sx, y * sy),
          width: 22 * sx,
          height: 6 * sy,
        ),
        paint,
      );
    }
  }

  void _paintGround(Canvas canvas, Size size, double sx, double sy) {
    final ground = Paint()
      ..color = AppColors.dark700
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(0, groundY * sy),
      Offset(size.width, groundY * sy),
      ground,
    );

    // Soil ticks scrolling with the world.
    final tick = Paint()
      ..color = AppColors.dark100
      ..strokeWidth = 1;
    final offset = distance % 14;
    for (double x = -offset; x < worldW; x += 14) {
      final tx = x * sx;
      canvas.drawLine(
        Offset(tx, (groundY + 4) * sy),
        Offset(tx + 4 * sx, (groundY + 4) * sy),
        tick,
      );
      canvas.drawLine(
        Offset((x + 8) * sx, (groundY + 8) * sy),
        Offset((x + 10) * sx, (groundY + 8) * sy),
        tick,
      );
    }
  }

  void _paintCrop(Canvas canvas, _Obstacle o, double sx, double sy) {
    final green = Paint()..color = const Color(0xFF2E7D4F);
    final darkGreen = Paint()..color = const Color(0xFF1F4D38);
    final cx = (o.x + o.width / 2) * sx;
    final baseY = groundY * sy;
    final topY = o.top * sy;
    final halfW = (o.width / 2) * sx;

    // Stem.
    canvas.drawRect(
      Rect.fromLTRB(cx - 0.8 * sx, topY + (o.height * 0.3) * sy, cx + 0.8 * sx,
          baseY),
      darkGreen,
    );
    // Two stacked leaf triangles, like a stylised crop/tree.
    final lower = Path()
      ..moveTo(cx - halfW, baseY - (o.height * 0.25) * sy)
      ..lineTo(cx + halfW, baseY - (o.height * 0.25) * sy)
      ..lineTo(cx, topY + (o.height * 0.18) * sy)
      ..close();
    final upper = Path()
      ..moveTo(cx - halfW * 0.72, baseY - (o.height * 0.5) * sy)
      ..lineTo(cx + halfW * 0.72, baseY - (o.height * 0.5) * sy)
      ..lineTo(cx, topY)
      ..close();
    canvas.drawPath(lower, green);
    canvas.drawPath(upper, green);
  }

  void _paintBird(Canvas canvas, _Obstacle o, double sx, double sy) {
    final paint = Paint()
      ..color = AppColors.dark500
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cx = (o.x + o.width / 2) * sx;
    final cy = (o.top + o.height / 2) * sy;
    final flap = math.sin(time * 16) * 2.2;

    // Two wing strokes forming a gliding "V" that flaps.
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx - 4 * sx, cy - (flap + 1.5) * sy),
      paint,
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 4 * sx, cy - (flap + 1.5) * sy),
      paint,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      1.1 * sx,
      Paint()..color = AppColors.dark500,
    );
  }

  // ── The drone ──────────────────────────────────────────────────────────

  void _paintDrone(Canvas canvas, double sx, double sy) {
    // Idle bob on the start screen; a subtle hover wobble while cruising at
    // fixed altitude so the drone still looks alive between jumps.
    final bob = phase == _Phase.ready
        ? math.sin(time * 3) * 1.6
        : (phase == _Phase.playing && velocity == 0
              ? math.sin(time * 9) * 0.5
              : 0.0);
    final cx = _DroneRunnerGameState.droneX * sx;
    final cy = (droneY + bob) * sy;
    final tilt = phase == _Phase.playing
        ? (velocity / 420).clamp(-0.28, 0.34)
        : 0.0;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);

    final body = Paint()..color = AppColors.dark700;
    final accent = Paint()..color = const Color(0xFF2E7D4F);
    final rotor = Paint()
      ..color = AppColors.dark300.withValues(
        // Alternate the alpha to fake spinning blades.
        alpha: 0.35 + 0.4 * (math.sin(time * 40).abs()),
      );

    // Arms.
    canvas.drawLine(
      Offset(-6.4 * sx, -1.4 * sy),
      Offset(6.4 * sx, -1.4 * sy),
      Paint()
        ..color = AppColors.dark700
        ..strokeWidth = 1.6,
    );
    // Rotors.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-6.2 * sx, -2.6 * sy),
        width: 6.4 * sx,
        height: 1.5 * sy,
      ),
      rotor,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(6.2 * sx, -2.6 * sy),
        width: 6.4 * sx,
        height: 1.5 * sy,
      ),
      rotor,
    );
    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: 9 * sx,
          height: 3.6 * sy,
        ),
        Radius.circular(1.6 * sx),
      ),
      body,
    );
    // Camera gimbal.
    canvas.drawCircle(Offset(1.6 * sx, 2.2 * sy), 1.0 * sx, accent);

    canvas.restore();
  }

  // ── HUD + overlays ─────────────────────────────────────────────────────

  void _paintHud(Canvas canvas, Size size) {
    _text(
      canvas,
      'HI ${best.toString().padLeft(5, '0')}  ${score.toString().padLeft(5, '0')}',
      Offset(size.width - 12, 10),
      AppTextStyle.textSmSemibold.copyWith(color: AppColors.dark300),
      alignRight: true,
    );

    if (phase == _Phase.ready) {
      _centered(
        canvas,
        size,
        'TAP TO JUMP',
        'Hop over the crops and the birds',
      );
    } else if (phase == _Phase.dead) {
      _centered(
        canvas,
        size,
        'G A M E  O V E R',
        'Score $score · Best $best — tap to retry',
      );
    }
  }

  void _centered(Canvas canvas, Size size, String title, String subtitle) {
    _text(
      canvas,
      title,
      Offset(size.width / 2, size.height * 0.34),
      AppTextStyle.textXlBold.copyWith(color: AppColors.dark700),
      center: true,
    );
    _text(
      canvas,
      subtitle,
      Offset(size.width / 2, size.height * 0.34 + 26),
      AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
      center: true,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at,
    TextStyle style, {
    bool center = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    var offset = at;
    if (center) offset = at - Offset(painter.width / 2, 0);
    if (alignRight) offset = at - Offset(painter.width, 0);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _DroneRunnerPainter oldDelegate) => true;
}
