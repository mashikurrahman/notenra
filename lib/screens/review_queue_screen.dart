import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/clinical_models.dart';
import '../services/clinical_service.dart';
import '../status_ui.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';
import '../widgets/pressable.dart';
import 'note_review_screen.dart';

/// Workflow stage a note sits in — the clinician's mental model of "whose turn
/// is it". The Notes tab is filtered by this.
enum _Bucket { review, inProgress, completed }

/// How the (filtered) notes are organised in the list.
enum _GroupBy { stage, date, patient, recent }

/// Notes — the clinician's note history and work queue.
///
/// Filter by workflow stage (To review / In progress / Done) and organise by
/// Date, Stage, Patient or Recent. The stage filter now lives in the header as a
/// segmented control rather than a chip rail floating over the list, so the
/// current filter is always visible while scrolling.
class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  /// null = all stages; otherwise a single stage is shown.
  _Bucket? _filter;
  // Default to a day-by-day view (Today / Yesterday / …) so notes read the same
  // date-first way as the patient schedule.
  _GroupBy _group = _GroupBy.date;

  // --- Workflow bucketing -------------------------------------------------

  _Bucket _bucketOf(VisitStatus s) {
    switch (s) {
      case VisitStatus.readyForReview:
      case VisitStatus.failed:
        return _Bucket.review;
      case VisitStatus.approved:
      case VisitStatus.syncedToEhr:
        return _Bucket.completed;
      default: // recording, pendingUpload, withScribe, changesRequested
        return _Bucket.inProgress;
    }
  }

  /// All real notes (excludes empty scheduled-visit shells, which the service
  /// already keeps out of the review queue).
  List<Visit> _allNotes(ClinicalService svc) =>
      [...svc.reviewQueue, ...svc.completed];

  List<Visit> _recentFirst(Iterable<Visit> v) =>
      [...v]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ClinicalService>();
    final all = _allNotes(svc);

    final byBucket = <_Bucket, List<Visit>>{
      for (final b in _Bucket.values)
        b: all.where((v) => _bucketOf(v.status) == b).toList(),
    };

    // Apply the stage filter.
    final filtered = _filter == null ? all : byBucket[_filter]!;
    final waiting = byBucket[_Bucket.review]!.length;

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: 'Notes',
            subtitle: waiting == 0
                ? 'Nothing waiting on you'
                : '$waiting note${waiting == 1 ? '' : 's'} waiting on you',
            showBack: false,
            leading: const SizedBox(width: Nx.s2),
            actions: [
              HeaderIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                busy: svc.loading,
                onTap: svc.loading ? null : svc.refresh,
              ),
            ],
            bottom: _stageFilter(byBucket),
          ),
          _connectivityBar(svc),
          if (svc.loading) const LinearProgressIndicator(minHeight: 2),
          _groupRow(filtered.length),
          Expanded(
            child: RefreshIndicator(
              onRefresh: svc.refresh,
              child: _list(context, filtered, all.isEmpty),
            ),
          ),
        ],
      ),
    );
  }

  // --- Stage filter (in-header segmented control) -------------------------

  Widget _stageFilter(Map<_Bucket, List<Visit>> byBucket) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s4),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Nx.rSm),
        ),
        child: Row(
          children: [
            _segment('All', null, null),
            _segment('To review', _Bucket.review,
                byBucket[_Bucket.review]!.length),
            _segment('Progress', _Bucket.inProgress,
                byBucket[_Bucket.inProgress]!.length),
            _segment(
                'Done', _Bucket.completed, byBucket[_Bucket.completed]!.length),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, _Bucket? bucket, int? count) {
    final selected = _filter == bucket;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = bucket),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(Nx.rSm - 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Nx.primary
                            : Colors.white.withValues(alpha: 0.9))),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 4),
                Text('$count',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Nx.primary.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.65))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Group-by row -------------------------------------------------------

  Widget _groupRow(int shown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Nx.s5, Nx.s3, Nx.s2, 0),
      child: Row(
        children: [
          Text('$shown NOTE${shown == 1 ? '' : 'S'}', style: Nx.sectionLabel),
          const Spacer(),
          PopupMenuButton<_GroupBy>(
            tooltip: 'Group by',
            initialValue: _group,
            onSelected: (v) => setState(() => _group = v),
            position: PopupMenuPosition.under,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _GroupBy.date, child: Text('By date')),
              PopupMenuItem(value: _GroupBy.stage, child: Text('By stage')),
              PopupMenuItem(value: _GroupBy.patient, child: Text('By patient')),
              PopupMenuItem(value: _GroupBy.recent, child: Text('Most recent')),
            ],
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Nx.s2, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.segment, size: 15, color: Nx.muted),
                  const SizedBox(width: 4),
                  Text(_groupLabel(_group),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Nx.secondary)),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Nx.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _groupLabel(_GroupBy g) => switch (g) {
        _GroupBy.date => 'Date',
        _GroupBy.stage => 'Stage',
        _GroupBy.patient => 'Patient',
        _GroupBy.recent => 'Recent',
      };

  // --- The list -----------------------------------------------------------

  Widget _list(BuildContext context, List<Visit> filtered, bool allEmpty) {
    if (allEmpty) {
      return ListView(children: const [
        SizedBox(height: 70),
        NxEmptyState(
          icon: Icons.fact_check_outlined,
          title: 'No notes yet',
          hint: 'Record a visit and the note will show up here for review.',
        ),
      ]);
    }
    if (filtered.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 70),
        NxEmptyState(
          icon: _bucketIcon(_filter!),
          title: 'Nothing here',
          hint: _emptyHintFor(_filter!),
        ),
      ]);
    }

    final children = <Widget>[];
    switch (_group) {
      case _GroupBy.stage:
        // Group by workflow stage, in priority order. When a single stage is
        // already selected, that's just one section.
        final buckets = _filter == null
            ? [_Bucket.review, _Bucket.inProgress, _Bucket.completed]
            : [_filter!];
        for (final b in buckets) {
          final items =
              _recentFirst(filtered.where((v) => _bucketOf(v.status) == b));
          if (items.isEmpty) continue;
          children.add(SectionHeader(
            label: _bucketLabel(b),
            icon: _bucketIcon(b),
            count: items.length,
            accent: _bucketColor(b),
          ));
          children.addAll(
              items.map((v) => Pressable(child: _noteCard(context, v))));
        }
      case _GroupBy.date:
        _addGrouped(
          context,
          children,
          filtered,
          keyOf: (v) {
            final d = DateTime.fromMillisecondsSinceEpoch(v.createdAt);
            return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
          },
          // Newest day first.
          compareKeys: (a, b) => (b as int).compareTo(a as int),
          labelOf: (k) =>
              _dayLabel(DateTime.fromMillisecondsSinceEpoch(k as int)),
          icon: Icons.calendar_today_outlined,
        );
      case _GroupBy.patient:
        _addGrouped(
          context,
          children,
          filtered,
          keyOf: (v) =>
              v.patientName.isEmpty ? 'Unknown patient' : v.patientName,
          compareKeys: (a, b) =>
              (a as String).toLowerCase().compareTo((b as String).toLowerCase()),
          labelOf: (k) => k as String,
          icon: Icons.person_outline,
        );
      case _GroupBy.recent:
        final items = _recentFirst(filtered);
        children.add(SectionHeader(
            label: 'All notes',
            icon: Icons.history,
            count: items.length,
            accent: Nx.muted));
        children.addAll(
            items.map((v) => Pressable(child: _noteCard(context, v))));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Nx.s4, 0, Nx.s4, Nx.s8),
      children: children,
    );
  }

  /// Generic grouping: bucket [items] by [keyOf], order groups by [compareKeys],
  /// render a header per group (via [labelOf]) then its notes newest-first.
  void _addGrouped(
    BuildContext context,
    List<Widget> children,
    List<Visit> items, {
    required Object Function(Visit) keyOf,
    required int Function(Object, Object) compareKeys,
    required String Function(Object) labelOf,
    required IconData icon,
  }) {
    final groups = <Object, List<Visit>>{};
    for (final v in items) {
      groups.putIfAbsent(keyOf(v), () => []).add(v);
    }
    final keys = groups.keys.toList()..sort(compareKeys);
    for (final k in keys) {
      final list = _recentFirst(groups[k]!);
      children.add(SectionHeader(
          label: labelOf(k), icon: icon, count: list.length, accent: Nx.muted));
      children
          .addAll(list.map((v) => Pressable(child: _noteCard(context, v))));
    }
  }

  Widget _noteCard(BuildContext context, Visit v) {
    final s = styleFor(v.status);
    final dt = DateTime.fromMillisecondsSinceEpoch(v.createdAt);
    final actionable = needsClinician(v.status);
    final bits = [
      DateFormat('MMM d, h:mm a').format(dt),
      if (v.durationMs > 0) _dur(v.durationMs),
      if (v.visitType.isNotEmpty) v.visitType,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: Nx.s2),
      child: NxCard(
        accentEdge: s.color,
        color: actionable ? s.tint : Nx.card,
        borderColor:
            actionable ? s.color.withValues(alpha: 0.40) : Nx.border,
        padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s3),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NoteReviewScreen(visitId: v.id))),
        child: Row(
          children: [
            NxAvatar(name: v.patientName, radius: 18, color: s.color),
            const SizedBox(width: Nx.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      v.patientName.isEmpty ? 'Unknown patient' : v.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Nx.ink,
                          fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(bits,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Nx.muted, fontSize: 11.5)),
                  const SizedBox(height: 6),
                  StatusPill(label: s.label, color: s.color, icon: s.icon),
                ],
              ),
            ),
            const SizedBox(width: Nx.s2),
            Icon(Icons.chevron_right,
                size: 20, color: Nx.muted.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  // --- Stage / date presentation -----------------------------------------

  Color _bucketColor(_Bucket b) => switch (b) {
        _Bucket.review => Nx.accent, // your turn
        _Bucket.inProgress => Nx.warning, // waiting on scribe
        _Bucket.completed => Nx.primary, // done and filed
      };

  String _bucketLabel(_Bucket b) => switch (b) {
        _Bucket.review => 'To review',
        _Bucket.inProgress => 'In progress',
        _Bucket.completed => 'Completed',
      };

  IconData _bucketIcon(_Bucket b) => switch (b) {
        _Bucket.review => Icons.rate_review_outlined,
        _Bucket.inProgress => Icons.hourglass_empty,
        _Bucket.completed => Icons.check_circle_outline,
      };

  String _emptyHintFor(_Bucket b) => switch (b) {
        _Bucket.review => 'No notes are waiting on you right now.',
        _Bucket.inProgress => 'Nothing is being written by a scribe right now.',
        _Bucket.completed => 'Approved notes will collect here.',
      };

  /// Friendly day header: Today / Yesterday / Tomorrow / weekday + date.
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff == -1) return 'Tomorrow';
    return DateFormat('EEEE, MMM d').format(d);
  }

  String _dur(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // --- Connectivity / sync banner ----------------------------------------

  Widget _connectivityBar(ClinicalService svc) {
    return ValueListenableBuilder<bool>(
      valueListenable: svc.online,
      builder: (context, online, _) {
        return ValueListenableBuilder<int>(
          valueListenable: svc.pendingSync,
          builder: (context, pending, child) {
            if (online && pending == 0) return const SizedBox.shrink();
            final offline = !online;
            final color = offline ? Nx.warning : Nx.primary;
            final text = offline
                ? (pending > 0
                    ? 'Offline · $pending change${pending == 1 ? '' : 's'} queued'
                    : 'Offline · changes will sync when reconnected')
                : 'Syncing $pending change${pending == 1 ? '' : 's'}…';
            return NxBanner(
              icon: offline ? Icons.cloud_off : Icons.cloud_sync,
              color: color,
              message: text,
            );
          },
        );
      },
    );
  }
}
