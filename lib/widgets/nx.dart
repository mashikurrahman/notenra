import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Shared Notenra building blocks.
///
/// Every screen composes from these instead of hand-rolling its own card,
/// pill, or section label — that's what keeps the app looking like one product
/// after the restructure.

/// The all-caps label + optional count and trailing action that introduces
/// each block of content.
class SectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int? count;
  final Color? accent;
  final Widget? trailing;
  final EdgeInsets padding;

  const SectionHeader({
    super.key,
    required this.label,
    this.icon,
    this.count,
    this.accent,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(Nx.s1, Nx.s2, 0, Nx.s2),
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? Nx.primary;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 6),
          ],
          Text(label.toUpperCase(), style: Nx.sectionLabel),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Nx.rPill),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The standard white content card: soft shadow, hairline border, generous
/// radius. [accentEdge] paints a coloured spine down the left so a row's state
/// reads before any text does.
class NxCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? color;
  final Color? borderColor;
  final Color? accentEdge;
  final double radius;
  final bool elevated;

  const NxCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Nx.s4),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.accentEdge,
    this.radius = Nx.rLg,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (accentEdge != null) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accentEdge),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? Nx.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? Nx.border),
        boxShadow: elevated ? Nx.cardShadow : Nx.rowShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

/// A small tinted status pill. The one way state is labelled in Notenra.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 8 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Nx.rPill),
        border: solid
            ? null
            : Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: fg,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

/// Compact pill button used for the primary action on a list row.
class NxPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool tonal;

  const NxPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: tonal ? color.withValues(alpha: 0.12) : color,
        foregroundColor: tonal ? color : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Nx.rSm)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Full-width informational banner (offline, sync, recovered recording…).
class NxBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Widget? action;
  final VoidCallback? onDismiss;

  const NxBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.action,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Nx.s4, Nx.s2, Nx.s4, 0),
      padding: EdgeInsets.fromLTRB(Nx.s3, Nx.s2, onDismiss == null ? Nx.s3 : 4, Nx.s2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Nx.rMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: Nx.s2),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Nx.ink, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (action != null) ...[const SizedBox(width: Nx.s2), action!],
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Nx.muted),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

/// The one empty state in the app: muted icon, a headline, and a hint.
class NxEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  const NxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Nx.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Nx.surface,
                borderRadius: BorderRadius.circular(Nx.rLg),
              ),
              child: Icon(icon, size: 30, color: Nx.primary),
            ),
            const SizedBox(height: Nx.s4),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Nx.ink, fontWeight: FontWeight.w700, fontSize: 15)),
            if (hint != null) ...[
              const SizedBox(height: Nx.s1),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Nx.muted, fontSize: 12.5)),
            ],
            if (action != null) ...[
              const SizedBox(height: Nx.s5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular patient monogram with an optional state ring / check badge.
class NxAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final Color? color;
  final bool done;

  const NxAvatar({
    super.key,
    required this.name,
    this.radius = 18,
    this.color,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? (done ? Nx.accent : Nx.primary);
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: c.withValues(alpha: 0.12),
      child: Text(
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
        style: TextStyle(
            color: c, fontWeight: FontWeight.w800, fontSize: radius * 0.82),
      ),
    );
    if (!done) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            decoration:
                const BoxDecoration(color: Nx.card, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 15, color: Nx.accent),
          ),
        ),
      ],
    );
  }
}

/// A fluid shimmer animation wrapper used for placeholder loading states.
/// Completely neutral and free of PHI.
class NxShimmer extends StatefulWidget {
  final Widget child;
  const NxShimmer({super.key, required this.child});

  @override
  State<NxShimmer> createState() => _NxShimmerState();
}

class _NxShimmerState extends State<NxShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              stops: const [0.1, 0.5, 0.9],
              colors: [
                Nx.surface,
                Colors.white.withValues(alpha: 0.85),
                Nx.surface,
              ],
              transform: _SlidingGradientTransform(slidePercent: _ctrl.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}

/// Rounded skeleton box placeholder with subtle surface styling.
class NxSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsets margin;

  const NxSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = Nx.rSm,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Nx.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Structured skeleton placeholder for the Note Review screen.
class NxNoteSkeleton extends StatelessWidget {
  const NxNoteSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return NxShimmer(
      child: Padding(
        padding: const EdgeInsets.all(Nx.s4),
        child: Column(
          children: [
            NxCard(
              padding: const EdgeInsets.all(Nx.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const NxSkeletonBox(width: 24, height: 24, radius: 6),
                      const SizedBox(width: Nx.s3),
                      const NxSkeletonBox(width: 140, height: 18),
                      const Spacer(),
                      NxSkeletonBox(width: 48, height: 20, radius: Nx.rPill),
                    ],
                  ),
                  const SizedBox(height: Nx.s5),
                  const NxSkeletonBox(height: 1),
                  const SizedBox(height: Nx.s5),
                  // Subjective block
                  const NxSkeletonBox(width: 100, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: double.infinity, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: 220, height: 14),
                  const SizedBox(height: Nx.s5),
                  // Objective block
                  const NxSkeletonBox(width: 90, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: double.infinity, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: 260, height: 14),
                  const SizedBox(height: Nx.s5),
                  // Assessment & Plan block
                  const NxSkeletonBox(width: 130, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: double.infinity, height: 14),
                  const SizedBox(height: Nx.s2),
                  const NxSkeletonBox(width: 180, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 6-cell animated discrete digit PIN input with auto-advance, auto-paste,
/// smooth cursor highlight, and haptic feedback on entry.
class NxPinInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final int length;
  final bool autofocus;

  const NxPinInput({
    super.key,
    required this.controller,
    this.onSubmit,
    this.onChanged,
    this.length = 6,
    this.autofocus = true,
  });

  @override
  State<NxPinInput> createState() => _NxPinInputState();
}

class _NxPinInputState extends State<NxPinInput> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    if (mounted) setState(() {});
    widget.onChanged?.call(widget.controller.text);
    if (widget.controller.text.trim().length == widget.length) {
      HapticFeedback.mediumImpact();
      widget.onSubmit?.call();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hidden actual input to capture soft keyboard, paste, and accessibility events
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          // Visible 6-cell design
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (i) {
              final isFilled = i < text.length;
              final isFocused = _focusNode.hasFocus && i == text.length;
              final digit = isFilled ? text[i] : '';

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                  color: isFilled ? Nx.card : Nx.surface,
                  borderRadius: BorderRadius.circular(Nx.rSm),
                  border: Border.all(
                    color: isFocused
                        ? Nx.primary
                        : (isFilled
                            ? Nx.primary.withValues(alpha: 0.45)
                            : Nx.border),
                    width: isFocused ? 2.0 : 1.2,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: Nx.primary.withValues(alpha: 0.20),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Nx.ink,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
