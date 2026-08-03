import 'package:flutter/material.dart';

import 'theme.dart';

/// The full Notenra lockup — mark plus wordmark.
///
/// Sized by [height]; the asset keeps its own 932:206 aspect. Pass
/// `reversed: true` on brand-gradient or dark surfaces to get the white cut.
class NotenraLogo extends StatelessWidget {
  final double height;
  final bool reversed;
  const NotenraLogo({super.key, this.height = 56, this.reversed = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      reversed
          ? 'assets/images/notenra_logo_white.png'
          : 'assets/images/notenra_logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          _Wordmark(height: height, reversed: reversed),
    );
  }
}

/// The Notenra mark on its own — the "N" with the green pulse running through
/// it. Used wherever the full lockup would be too wide (headers, avatars).
class NotenraMark extends StatelessWidget {
  final double size;
  final bool reversed;
  const NotenraMark({super.key, this.size = 32, this.reversed = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      reversed
          ? 'assets/images/notenra_mark_white.png'
          : 'assets/images/notenra_mark.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(reversed: reversed),
      ),
    );
  }
}

/// The mark on a rounded white tile — the app's compact brand chip, e.g. beside
/// a screen title inside the gradient header.
class NotenraBadge extends StatelessWidget {
  final double size;
  const NotenraBadge({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: Nx.rowShadow,
      ),
      alignment: Alignment.center,
      child: NotenraMark(size: size * 0.68),
    );
  }
}

/// Text fallback shown only if the logo asset is missing, so the UI still reads
/// as Notenra rather than collapsing to a broken-image box.
class _Wordmark extends StatelessWidget {
  final double height;
  final bool reversed;
  const _Wordmark({required this.height, required this.reversed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(height),
          painter: _MarkPainter(reversed: reversed),
        ),
        SizedBox(width: height * 0.14),
        Text(
          'Notenra',
          style: TextStyle(
            fontSize: height * 0.62,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1,
            color: reversed ? Colors.white : Nx.primary,
          ),
        ),
      ],
    );
  }
}

/// Vector fallback for the mark: the two "N" strokes with the pulse between
/// them. Deliberately simple — it only ever shows if the PNG fails to load.
class _MarkPainter extends CustomPainter {
  final bool reversed;
  _MarkPainter({required this.reversed});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.13;
    final blue = Paint()
      ..color = reversed ? Colors.white : Nx.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final green = Paint()
      ..color = reversed ? Colors.white : Nx.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.85
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final top = s * 0.14, bot = s * 0.86;
    final left = s * 0.18, right = s * 0.82, mid = s * 0.5;

    // The two halves of the "N": each stem plus its diagonal, which the pulse
    // then joins across the middle.
    canvas.drawPath(
      Path()
        ..moveTo(left, bot)
        ..lineTo(left, top)
        ..lineTo(mid - s * 0.06, mid - s * 0.06),
      blue,
    );
    canvas.drawPath(
      Path()
        ..moveTo(right, top)
        ..lineTo(right, bot)
        ..lineTo(mid + s * 0.06, mid + s * 0.06),
      blue,
    );

    // The pulse: flat in, dip, peak, dip, flat out.
    canvas.drawPath(
      Path()
        ..moveTo(left, mid)
        ..lineTo(s * 0.32, mid)
        ..lineTo(s * 0.39, mid + s * 0.10)
        ..lineTo(s * 0.50, mid - s * 0.16)
        ..lineTo(s * 0.58, mid + s * 0.04)
        ..lineTo(right, mid),
      green,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.reversed != reversed;
}
