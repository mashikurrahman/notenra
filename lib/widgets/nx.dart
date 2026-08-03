import 'package:flutter/material.dart';

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
          ?trailing,
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
