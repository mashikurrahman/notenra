import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/clinical_service.dart';
import '../status_ui.dart';
import '../theme.dart';
import 'patient_list_screen.dart';
import 'review_queue_screen.dart';
import 'today_screen.dart';

/// Top-level shell: three tabs, ordered by how often a clinician needs them.
///
///   • Today    — the home dashboard. Who's next, what needs reviewing, what's
///                left of the day, plus the record action.
///   • Schedule — the full day-by-day patient list, for planning and moving
///                appointments rather than working through the current day.
///   • Notes    — every note grouped date-wise, badged with how many are
///                sitting on the doctor's desk.
///
/// Splitting "today" out of the schedule is the point of the hierarchy: the old
/// single list had to be a dashboard, a calendar, and a work queue at once, so
/// the next patient competed with a 21-day date strip for the same space.
///
/// Each child owns its own Scaffold; an [IndexedStack] keeps every tab's scroll
/// position and state alive when switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openTab(int i) {
    if (_index != i) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ClinicalService>();
    final toReview =
        svc.reviewQueue.where((v) => needsClinician(v.status)).length;

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: IndexedStack(
        index: _index,
        children: [
          TodayScreen(onOpenTab: _openTab),
          const PatientListScreen(),
          const ReviewQueueScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Nx.card,
          border: Border(top: BorderSide(color: Nx.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          onDestinationSelected: _openTab,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.today_outlined, color: Nx.muted),
              selectedIcon: Icon(Icons.today, color: Nx.primary),
              label: 'Today',
            ),
            const NavigationDestination(
              icon: Icon(Icons.event_note_outlined, color: Nx.muted),
              selectedIcon: Icon(Icons.event_note, color: Nx.primary),
              label: 'Schedule',
            ),
            NavigationDestination(
              icon: _notesIcon(Icons.fact_check_outlined, toReview, false),
              selectedIcon: _notesIcon(Icons.fact_check, toReview, true),
              label: 'Notes',
            ),
          ],
        ),
      ),
    );
  }

  /// Notes tab icon with a count badge when notes are waiting on the doctor.
  Widget _notesIcon(IconData icon, int count, bool selected) {
    final base = Icon(icon, color: selected ? Nx.primary : Nx.muted);
    if (count == 0) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -6,
          top: -5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              // Waiting notes are an invitation, not an alarm — brand green,
              // matching how the same state reads everywhere else.
              color: Nx.accent,
              borderRadius: BorderRadius.circular(Nx.rPill),
              border: Border.all(color: Nx.card, width: 1.5),
            ),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.1),
            ),
          ),
        ),
      ],
    );
  }
}
