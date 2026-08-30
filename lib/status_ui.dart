import 'package:flutter/material.dart';

import 'api/clinical_models.dart';
import 'theme.dart';

/// How a visit's workflow state is presented — colour, short label, icon, and
/// the tint its card carries.
///
/// Every screen reads state from here, so "Ready for review" is the same green,
/// with the same wording and the same icon, on the dashboard, the schedule, the
/// notes list and the note itself.
class VisitStatusStyle {
  final String label;

  /// Longer form used where there's room to explain the state.
  final String detail;
  final Color color;
  final IconData icon;

  const VisitStatusStyle({
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
  });

  /// Background tint for a card in this state. Kept very light so a list of
  /// mixed states still reads as a calm list, not a colour chart.
  Color get tint => color.withValues(alpha: 0.07);
}

/// Presentation for a visit that has been recorded.
VisitStatusStyle styleFor(VisitStatus? status) => switch (status) {
      VisitStatus.recording => const VisitStatusStyle(
          label: 'Recorded',
          detail: 'Recording saved',
          color: Nx.accent,
          icon: Icons.graphic_eq,
        ),
      VisitStatus.pendingUpload => const VisitStatusStyle(
          label: 'Queued',
          detail: 'Securing & uploading',
          color: Nx.muted,
          icon: Icons.cloud_upload_outlined,
        ),
      VisitStatus.withScribe => const VisitStatusStyle(
          label: 'Processing',
          detail: 'AI generating note…',
          color: Nx.warning,
          icon: Icons.auto_awesome,
        ),
      VisitStatus.readyForReview => const VisitStatusStyle(
          label: 'Ready for you',
          detail: 'AI Note ready to review',
          color: Nx.accent,
          icon: Icons.rate_review_outlined,
        ),
      VisitStatus.changesRequested => const VisitStatusStyle(
          label: 'Revising',
          detail: 'Updating note',
          color: Nx.warning,
          icon: Icons.reply,
        ),
      VisitStatus.approved => const VisitStatusStyle(
          label: 'Approved',
          detail: 'Approved as final',
          color: Nx.accent,
          icon: Icons.verified_outlined,
        ),
      VisitStatus.syncedToEhr => const VisitStatusStyle(
          label: 'In EHR',
          detail: 'Filed to the EHR',
          color: Nx.primary,
          icon: Icons.cloud_done_outlined,
        ),
      VisitStatus.failed => const VisitStatusStyle(
          label: 'Needs attention',
          detail: 'Upload failed — retry',
          color: Nx.danger,
          icon: Icons.error_outline,
        ),
      null => const VisitStatusStyle(
          label: 'Recorded',
          detail: 'Recorded',
          color: Nx.accent,
          icon: Icons.check_circle_outline,
        ),
    };

/// Presentation for a patient who has not been recorded yet.
const upcomingStyle = VisitStatusStyle(
  label: 'Upcoming',
  detail: 'Not recorded yet',
  color: Nx.primary,
  icon: Icons.schedule,
);

/// True when the note is sitting on the clinician's desk — the states the app
/// nudges about, badges, and surfaces first.
bool needsClinician(VisitStatus? s) =>
    s == VisitStatus.readyForReview || s == VisitStatus.failed;
