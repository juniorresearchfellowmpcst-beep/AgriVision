import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _progressFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
          ),
        );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.7, curve: Curves.easeIn),
      ),
    );
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.85, curve: Curves.easeIn),
      ),
    );
    _progressFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive base unit: scales with the shorter side of the screen,
    // clamped so it looks right on phones, tablets, and desktop/web.
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortestSide / 390.0).clamp(
      0.8,
      1.6,
    ); // 390 = baseline phone width

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1110), Color(0xFF111A15), Color(0xFF13241B)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Cap content width on large screens (tablet/desktop/web).
              final maxContentWidth = constraints.maxWidth > 600
                  ? 480.0
                  : constraints.maxWidth;

              return Center(
                child: SizedBox(
                  width: maxContentWidth,
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return Opacity(
                            opacity: _logoFade.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: _LogoMark(scale: scale),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 28 * scale),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return ClipRect(
                            child: SlideTransition(
                              position: _titleSlide,
                              child: Opacity(
                                opacity: _titleFade.value,
                                child: _Title(scale: scale),
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 8 * scale),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return Opacity(
                            opacity: _taglineFade.value,
                            child: _Tagline(scale: scale),
                          );
                        },
                      ),
                      const Spacer(flex: 3),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return Opacity(
                            opacity: _progressFade.value,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 48 * scale),
                              child: Column(
                                children: [
                                  const _ThinLoadingBar(),
                                  SizedBox(height: 16 * scale),
                                  Text(
                                    'v1.0.0',
                                    style: TextStyle(
                                      fontSize: 11 * scale,
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Logo mark — gradient rounded square with drone glyph + glow.
/// Wrapped in RepaintBoundary since the CustomPaint inside doesn't
/// need to repaint alongside parent fades/scales.
class _LogoMark extends StatelessWidget {
  final double scale;
  const _LogoMark({required this.scale});

  @override
  Widget build(BuildContext context) {
    final size = 108.0 * scale;
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2BBE6E), Color(0xFF1C8C50)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2BBE6E).withValues(alpha: 0.35),
              blurRadius: 40 * scale,
              spreadRadius: -4,
              offset: Offset(0, 16 * scale),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: Size(size * 0.48, size * 0.48),
            painter: const _DroneGlyphPainter(),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final double scale;
  const _Title({required this.scale});

  @override
  Widget build(BuildContext context) {
    final fontSize = 30.0 * scale;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Agri',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Drone',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2BBE6E),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  final double scale;
  const _Tagline({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Precision farming, from above',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14 * scale,
        color: Colors.white.withValues(alpha: 0.5),
        letterSpacing: 0.2,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// Clean, minimal drone glyph — static, cheap to paint, scales with size.
class _DroneGlyphPainter extends CustomPainter {
  const _DroneGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = Colors.white;

    const dirs = [Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1)];
    final armLen = w * 0.36;

    for (final d in dirs) {
      final end = Offset(center.dx + d.dx * armLen, center.dy + d.dy * armLen);
      canvas.drawLine(center, end, stroke);
      canvas.drawCircle(
        end,
        w * 0.1,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045,
      );
    }

    final bodyRect = Rect.fromCenter(
      center: center,
      width: w * 0.34,
      height: w * 0.22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.06)),
      fill,
    );
  }

  // Static drawing — never needs to repaint.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Slim animated loading bar — isolated in its own AnimationController
/// so it doesn't tie its 1.1s loop to the splash's one-shot controller.
class _ThinLoadingBar extends StatefulWidget {
  const _ThinLoadingBar();

  @override
  State<_ThinLoadingBar> createState() => _ThinLoadingBarState();
}

class _ThinLoadingBarState extends State<_ThinLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Align(
                    alignment: Alignment(-1 + 2 * _controller.value, 0),
                    child: Container(
                      width: 50,
                      height: 3,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x002BBE6E),
                            Color(0xFF2BBE6E),
                            Color(0x002BBE6E),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder home screen — replace with your actual app entry point.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1110),
      body: Center(
        child: Text(
          'Welcome to AgriDrone',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }
}
