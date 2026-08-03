import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/clinical_models.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clinical_service.dart';
import '../status_ui.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';
import '../widgets/pressable.dart';
import 'add_patient_screen.dart';
import 'note_review_screen.dart';
import 'patient_visit_screen.dart';
import 'profile_screen.dart';

/// Today — the app's home.
///
/// Answers, in order, the only three questions a clinician has between
/// patients: *who's next*, *what needs me*, and *what's left*. Everything else
/// (the full day-by-day schedule, the whole note history) lives one tab away,
/// so this screen stays short enough to read at a glance in a corridor.
class TodayScreen extends StatelessWidget {
  /// Jumps the shell to another tab — used by the "See all" affordances.
  final void Function(int tabIndex) onOpenTab;

  const TodayScreen({super.key, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final svc = context.watch<ClinicalService>();

    final today = _todaysPatients(state, svc);
    final toSee = today.where((p) => !svc.patientRecorded(p.id)).toList();
    final recorded = today.length - toSee.length;
    final next = toSee.isEmpty ? null : toSee.first;

    // Notes the scribe has handed back (or that failed) — the doctor's desk.
    final awaiting = svc.reviewQueue
        .where((v) => needsClinician(v.status))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          _header(context, state, svc, recorded, today.length, awaiting.length),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await svc.refresh();
                await state.refreshPatients();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Nx.s4, 0, Nx.s4, Nx.s8),
                children: [
                  _banners(context, state, svc),
                  const SizedBox(height: Nx.s4),
                  _nextUp(context, svc, next, toSee.length),
                  if (awaiting.isNotEmpty) ...[
                    const SizedBox(height: Nx.s5),
                    SectionHeader(
                      label: 'Needs you',
                      icon: Icons.rate_review_outlined,
                      count: awaiting.length,
                      accent: Nx.accent,
                      trailing: awaiting.length > 3
                          ? _seeAll(() => onOpenTab(2))
                          : null,
                    ),
                    for (final v in awaiting.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: Nx.s2),
                        child: Pressable(child: _awaitingRow(context, v)),
                      ),
                  ],
                  const SizedBox(height: Nx.s5),
                  SectionHeader(
                    label: toSee.isEmpty ? 'Today' : 'Still to see',
                    icon: Icons.schedule,
                    count: toSee.length > 1 ? toSee.length - 1 : null,
                    trailing: _seeAll(() => onOpenTab(1), label: 'Schedule'),
                  ),
                  ..._rest(context, svc, toSee, recorded, today.length),
                  const SizedBox(height: Nx.s5),
                  _quickActions(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _header(BuildContext context, AppState state, ClinicalService svc,
      int recorded, int total, int awaiting) {
    final name = _doctorName(state);
    // Three tiles carry the whole day's shape; the old build buried this in a
    // 34px progress bar wedged into the greeting line.
    final stats = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s4),
      child: Row(
        children: [
          Expanded(
              child: _statTile('To see', '${total - recorded}', Icons.schedule)),
          const SizedBox(width: Nx.s2),
          Expanded(child: _statTile('Recorded', '$recorded', Icons.graphic_eq)),
          const SizedBox(width: Nx.s2),
          Expanded(
              child: _statTile(
                  'Needs you', '$awaiting', Icons.rate_review_outlined,
                  highlight: awaiting > 0)),
        ],
      ),
    );

    return NotenraHeader(
      padding: const EdgeInsets.fromLTRB(Nx.s5, Nx.s2, Nx.s4, Nx.s4),
      bottom: stats,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_greeting()},',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w500,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 23,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: Nx.s2),
          HeaderIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            busy: svc.loading,
            onTap: svc.loading
                ? null
                : () async {
                    await svc.refresh();
                    await state.refreshPatients();
                  },
          ),
          const SizedBox(width: Nx.s2),
          _avatarButton(context, name),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon,
      {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: highlight ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(Nx.rMd),
        border: Border.all(
          color: Colors.white.withValues(alpha: highlight ? 0.55 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _avatarButton(BuildContext context, String name) {
    final initial = name.replaceFirst('Dr. ', '').trim();
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        ),
        child: CircleAvatar(
          radius: 19,
          backgroundColor: Colors.white,
          child: Text(initial.isEmpty ? '?' : initial[0].toUpperCase(),
              style: const TextStyle(
                  color: Nx.primary, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
    );
  }

  // --- Next up hero -------------------------------------------------------

  /// The single most important thing on the screen: who to record next, with
  /// one full-width action. Deliberately larger than anything else here.
  Widget _nextUp(BuildContext context, ClinicalService svc, Patient? next,
      int remaining) {
    if (next == null) {
      return NxCard(
        elevated: true,
        color: Nx.accentSoft,
        borderColor: Nx.accent.withValues(alpha: 0.30),
        padding: const EdgeInsets.all(Nx.s5),
        child: Row(
          children: [
            const Icon(Icons.task_alt, color: Nx.accent, size: 30),
            const SizedBox(width: Nx.s4),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Day complete',
                      style: TextStyle(
                          color: Nx.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  SizedBox(height: 2),
                  Text('Every patient scheduled today has been recorded.',
                      style: TextStyle(color: Nx.secondary, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final visitType = _visitTypeOf(next, svc);
    final dt = DateTime.fromMillisecondsSinceEpoch(_encounterMillis(next, svc));
    final meta = [
      'MRN ${next.mrn}',
      if (visitType.isNotEmpty) visitType,
    ].join('  ·  ');

    return NxCard(
      elevated: true,
      padding: EdgeInsets.zero,
      onTap: () => _openPatient(context, next.id),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(Nx.s5, Nx.s4, Nx.s4, Nx.s4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Nx.primary.withValues(alpha: 0.10),
                  Nx.primary.withValues(alpha: 0.02),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                NxAvatar(name: next.name, radius: 24),
                const SizedBox(width: Nx.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text('NEXT UP', style: Nx.sectionLabel.copyWith(
                              color: Nx.primary, fontSize: 9.5)),
                          const SizedBox(width: Nx.s2),
                          StatusPill(
                            label: DateFormat('h:mm a').format(dt),
                            color: Nx.primary,
                            icon: Icons.schedule,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(next.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Nx.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Nx.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s3, Nx.s4, Nx.s4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    remaining == 1
                        ? 'Last patient of the day'
                        : '$remaining still to record today',
                    style: const TextStyle(color: Nx.muted, fontSize: 12),
                  ),
                ),
                const SizedBox(width: Nx.s3),
                // Recording is the app's one green action, matching the pulse
                // in the mark and the live banner.
                FilledButton.icon(
                  onPressed: () => _openPatient(context, next.id, record: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Nx.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Nx.s5, vertical: Nx.s3),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('Record'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Awaiting-review rows ----------------------------------------------

  Widget _awaitingRow(BuildContext context, Visit v) {
    final s = styleFor(v.status);
    return NxCard(
      accentEdge: s.color,
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s3),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NoteReviewScreen(visitId: v.id))),
      child: Row(
        children: [
          NxAvatar(name: v.patientName, radius: 16, color: s.color),
          const SizedBox(width: Nx.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v.patientName.isEmpty ? 'Patient' : v.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Nx.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(s.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.color, fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: Nx.s2),
          Icon(Icons.chevron_right, color: Nx.muted.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  // --- Remaining patients -------------------------------------------------

  List<Widget> _rest(BuildContext context, ClinicalService svc,
      List<Patient> toSee, int recorded, int total) {
    if (total == 0) {
      return [
        NxCard(
          padding: EdgeInsets.zero,
          child: NxEmptyState(
            icon: Icons.event_available_outlined,
            title: 'Nothing scheduled today',
            hint: 'Add a patient to start recording.',
            action: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddPatientScreen())),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add patient'),
            ),
          ),
        ),
      ];
    }

    // The first entry is already the hero card, so skip it here.
    final rest = toSee.skip(1).toList(growable: false);
    if (rest.isEmpty) {
      return [
        NxCard(
          color: Nx.surface,
          borderColor: Nx.border,
          padding: const EdgeInsets.symmetric(
              horizontal: Nx.s4, vertical: Nx.s4),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Nx.accent, size: 20),
              const SizedBox(width: Nx.s3),
              Expanded(
                child: Text(
                  toSee.isEmpty
                      ? 'All $total recorded — nothing left to capture.'
                      : 'No one else waiting after this patient.',
                  style: const TextStyle(color: Nx.secondary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      for (final p in rest)
        Padding(
          padding: const EdgeInsets.only(bottom: Nx.s2),
          child: Pressable(child: _upcomingRow(context, svc, p)),
        ),
    ];
  }

  Widget _upcomingRow(BuildContext context, ClinicalService svc, Patient p) {
    final dt = DateTime.fromMillisecondsSinceEpoch(_encounterMillis(p, svc));
    final visitType = _visitTypeOf(p, svc);
    return NxCard(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s3),
      onTap: () => _openPatient(context, p.id),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat('h:mm').format(dt),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Nx.ink,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Text(DateFormat('a').format(dt),
                    style: const TextStyle(fontSize: 10, color: Nx.muted)),
              ],
            ),
          ),
          NxAvatar(name: p.name, radius: 16),
          const SizedBox(width: Nx.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Nx.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    visitType.isEmpty ? 'MRN ${p.mrn}' : 'MRN ${p.mrn}  ·  $visitType',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Nx.muted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: Nx.s2),
          NxPillButton(
            label: 'Record',
            icon: Icons.mic,
            color: Nx.primary,
            tonal: true,
            onTap: () => _openPatient(context, p.id, record: true),
          ),
        ],
      ),
    );
  }

  // --- Quick actions ------------------------------------------------------

  Widget _quickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _action(
            context,
            icon: Icons.person_add_alt,
            label: 'Add patient',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddPatientScreen())),
          ),
        ),
        const SizedBox(width: Nx.s3),
        Expanded(
          child: _action(
            context,
            icon: Icons.calendar_month_outlined,
            label: 'Full schedule',
            onTap: () => onOpenTab(1),
          ),
        ),
      ],
    );
  }

  Widget _action(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Pressable(
      child: NxCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: Nx.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Nx.primary, size: 22),
            const SizedBox(height: Nx.s2),
            Text(label,
                style: const TextStyle(
                    color: Nx.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _seeAll(VoidCallback onTap, {String label = 'See all'}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Nx.s2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  // --- Banners ------------------------------------------------------------

  Widget _banners(BuildContext context, AppState state, ClinicalService svc) {
    final rec = state.recoveredRecording;
    return Column(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: svc.pendingSync,
          builder: (context, pending, _) => pending == 0
              ? const SizedBox.shrink()
              : NxBanner(
                  icon: Icons.sync,
                  color: Nx.primary,
                  message: 'Syncing $pending offline visit'
                      '${pending == 1 ? '' : 's'}…',
                ),
        ),
        if (svc.error != null && !svc.loading)
          NxBanner(
            icon: Icons.cloud_off,
            color: Nx.danger,
            message: svc.error!,
          ),
        if (rec != null)
          NxBanner(
            icon: Icons.warning_amber_rounded,
            color: Nx.warning,
            message:
                'Interrupted recording for ${state.patientNameById(rec.patientId)} recovered.',
            onDismiss: state.clearRecoveredRecording,
            action: NxPillButton(
              label: 'Resume',
              icon: Icons.play_arrow,
              color: Nx.warning,
              onTap: () {
                state.clearRecoveredRecording();
                _openPatient(context, rec.patientId, record: true);
              },
            ),
          ),
      ],
    );
  }

  // --- Helpers ------------------------------------------------------------

  void _openPatient(BuildContext context, int patientId,
      {bool record = false}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            PatientVisitScreen(patientId: patientId, autoStart: record)));
  }

  /// Today's patients, earliest first. Mirrors the schedule's notion of when an
  /// encounter is: the chosen visit date, else the latest visit, else last
  /// contact.
  List<Patient> _todaysPatients(AppState state, ClinicalService svc) {
    final now = DateTime.now();
    final list = state.visiblePatients
        .where((p) => _sameDay(
            DateTime.fromMillisecondsSinceEpoch(_encounterMillis(p, svc)), now))
        .toList();
    list.sort((a, b) =>
        _encounterMillis(a, svc).compareTo(_encounterMillis(b, svc)));
    return list;
  }

  int _encounterMillis(Patient p, ClinicalService svc) {
    if (p.visitDate != 0) return p.visitDate;
    final v = svc.latestVisitForPatient(p.id);
    if (v != null && v.visitDate != 0) return v.visitDate;
    if (v != null) return v.createdAt;
    return p.lastContactDate;
  }

  String _visitTypeOf(Patient p, ClinicalService svc) => p.visitType.isNotEmpty
      ? p.visitType
      : (svc.latestVisitForPatient(p.id)?.visitType ?? '');

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _doctorName(AppState state) =>
      (state.currentUser?.fullName.isNotEmpty ?? false)
          ? state.currentUser!.fullName
          : 'Doctor';
}
