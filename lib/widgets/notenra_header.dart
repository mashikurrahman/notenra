import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The Notenra app header: a brand-gradient panel with a softly curved bottom
/// edge, the pulse motif from the logo drifting through it, and a soft drop
/// shadow — so content below appears to float beneath it.
///
/// Replaces a flat [AppBar]. Put it as the first child of a body [Column]; the
/// gradient fills behind the status bar and content is kept clear of the notch.
///
/// Two ways to use it:
///  • `NotenraHeader(child: …)` for a fully custom header body.
///  • `NotenraHeader.titled(title: …, subtitle: …, actions: […])` for the
///    standard screen header, which every pushed screen uses so back button,
///    title and actions land in the same place everywhere.
///
/// [bottom] renders *inside* the gradient below the main row — the place for a
/// day strip, search field, or segmented control that belongs to the header
/// rather than to the scrolling content.
class NotenraHeader extends StatelessWidget {
  final Widget child;
  final Widget? bottom;
  final EdgeInsets padding;
  final double bottomRadius;

  const NotenraHeader({
    super.key,
    required this.child,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(Nx.s5, Nx.s2, Nx.s4, Nx.s5),
    this.bottomRadius = Nx.rXl,
  });

  /// Standard screen header: optional back button, title, subtitle, actions.
  factory NotenraHeader.titled({
    Key? key,
    required String title,
    String? subtitle,
    List<Widget> actions = const [],
    Widget? leading,
    bool showBack = true,
    Widget? bottom,
    double bottomRadius = Nx.rXl,
  }) {
    return NotenraHeader(
      key: key,
      bottom: bottom,
      bottomRadius: bottomRadius,
      padding: const EdgeInsets.fromLTRB(Nx.s3, Nx.s2, Nx.s4, Nx.s5),
      child: _TitledHeaderBody(
        title: title,
        subtitle: subtitle,
        actions: actions,
        leading: leading,
        showBack: showBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          gradient: Nx.headerGradient,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
          boxShadow: [
            BoxShadow(
              color: Nx.ink.withValues(alpha: 0.26),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
          child: Stack(
            children: [
              // The logo's pulse, drawn faintly across the panel.
              Positioned.fill(child: CustomPaint(painter: _PulsePainter())),
              // Soft light bloom in the top-right for depth.
              Positioned(
                top: -46,
                right: -34,
                child: Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(padding: padding, child: child),
                    if (bottom != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Nx.s4),
                        child: bottom!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitledHeaderBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final bool showBack;

  const _TitledHeaderBody({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.leading,
    required this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Row(
      children: [
        if (leading != null)
          Padding(
            padding: const EdgeInsets.only(right: Nx.s2),
            child: leading!,
          )
        else if (canPop)
          HeaderIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          )
        else
          const SizedBox(width: Nx.s2),
        const SizedBox(width: Nx.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.4,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Nx.s2), a],
      ],
    );
  }
}

/// A translucent circular icon button for header actions (back, refresh, …).
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool busy;

  const HeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white.withValues(alpha: onTap == null ? 0.08 : 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon,
                  color: Colors.white.withValues(alpha: onTap == null ? 0.5 : 1),
                  size: 20),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// A compact translucent stat shown in the header ("12 today", "3 to review").
class HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const HeaderStat({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(Nx.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Draws the logo's pulse — flat, dip, peak, dip, flat — repeating faintly
/// across the header so the brand mark echoes behind every screen.
class _PulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final midY = size.height * 0.66;
    final path = Path()..moveTo(0, midY);
    const seg = 150.0;
    double x = 0;
    while (x < size.width) {
      path.lineTo(x + seg * 0.40, midY);
      path.lineTo(x + seg * 0.48, midY + 11); // shallow dip in
      path.lineTo(x + seg * 0.58, midY - 24); // the peak
      path.lineTo(x + seg * 0.66, midY + 7); // dip out
      path.lineTo(x + seg, midY);
      x += seg;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
