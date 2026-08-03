import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logo.dart';
import '../theme.dart';

/// Branded startup animation.
///
/// The Notenra mark springs in over a soft brand wash while rings ripple
/// outward, then the wordmark rises beneath it and a pulse trace — the same
/// waveform that runs through the "N" — sweeps left to right in place of a
/// spinner. Purely cosmetic: it shows for a short minimum time, then [onDone]
/// fires so the app can cross-fade to the real UI.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  final Duration minDuration;
  const SplashScreen({
    super.key,
    required this.onDone,
    this.minDuration = const Duration(milliseconds: 1900),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Intro: fade + spring-scale the mark in once, then reveal the wordmark.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  // Pulse: continuous ripple, trace sweep, and a gentle "breathe".
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );
  late final Animation<double> _scale = Tween(begin: 0.74, end: 1.0).animate(
    CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
  );
  late final Animation<double> _wordmark = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minDuration, () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Nx.surface],
          ),
        ),
        child: SafeArea(
          // The mark + wordmark lockup is centred in the viewport, and the
          // pulse trace is pinned to the bottom instead of sharing a Column
          // with it — so the trace's height can never push the logo off
          // centre (the old 3:2 Spacer split sat the lockup noticeably high).
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_pulse, _intro]),
                        builder: (context, _) {
                          final breathe =
                              1.0 + 0.022 * math.sin(_pulse.value * 2 * math.pi);
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              _ring(_pulse.value),
                              _ring((_pulse.value + 0.5) % 1.0),
                              Opacity(
                                opacity: _fade.value.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: _scale.value * breathe,
                                  child: const NotenraMark(size: 108),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Nx.s6),
                    // Wordmark rises as the mark settles.
                    AnimatedBuilder(
                      animation: _wordmark,
                      builder: (context, child) => Opacity(
                        opacity: _wordmark.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - _wordmark.value)),
                          child: child,
                        ),
                      ),
                      child: Column(
                        children: [
                          const NotenraLogo(height: 40),
                          const SizedBox(height: Nx.s3),
                          Text(
                            'AMBIENT CLINICAL SCRIBE',
                            style: Nx.sectionLabel.copyWith(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Pulse trace sweeping across, in place of a spinner.
              Positioned(
                left: 0,
                right: 0,
                bottom: Nx.s8,
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulse, _fade]),
                    builder: (context, _) => Opacity(
                      opacity: _fade.value.clamp(0.0, 1.0),
                      child: CustomPaint(
                        size: const Size(190, 30),
                        painter: _TracePainter(_pulse.value),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One expanding, fading ring. [t] in 0..1 drives its radius and opacity.
  Widget _ring(double t) {
    final size = 100.0 + t * 118.0;
    final opacity = (1.0 - t) * 0.26 * _fade.value.clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Nx.primary.withValues(alpha: opacity),
          width: 2.5,
        ),
      ),
    );
  }
}

/// A pulse waveform with a bright green highlight travelling along it — the
/// loading indicator, drawn from the brand mark instead of a generic spinner.
class _TracePainter extends CustomPainter {
  final double t;
  _TracePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.5;
    final w = size.width;

    // Flat, dip, peak, dip, flat — the logo's pulse, stretched to fit.
    final path = Path()
      ..moveTo(0, midY)
      ..lineTo(w * 0.30, midY)
      ..lineTo(w * 0.38, midY + size.height * 0.30)
      ..lineTo(w * 0.50, midY - size.height * 0.46)
      ..lineTo(w * 0.60, midY + size.height * 0.20)
      ..lineTo(w * 0.70, midY)
      ..lineTo(w, midY);

    canvas.drawPath(
      path,
      Paint()
        ..color = Nx.primary.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Bright segment sweeping along the trace.
    final metric = path.computeMetrics().first;
    final len = metric.length;
    const window = 0.28;
    final start = ((t * (1 + window)) - window) * len;
    final highlight = metric.extractPath(
      start.clamp(0.0, len),
      (start + window * len).clamp(0.0, len),
    );
    canvas.drawPath(
      highlight,
      Paint()
        ..color = Nx.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) => oldDelegate.t != t;
}
