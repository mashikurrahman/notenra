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

enum _PatientSort { time, name }

/// Schedule — the day-by-day planning view.
///
/// Today's *work* (who's next, what needs reviewing) lives on the Today tab;
/// this screen is for looking across days, finding a patient, and moving
/// appointments. That split is why the day strip can now live inside the header
/// instead of fighting the patient list for vertical space.
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  /// The clinic day currently being viewed. Defaults to today; the doctor can
  /// tap any previous/future day.
  DateTime _selectedDay = DateTime.now();
  _PatientSort _sort = _PatientSort.time;

  /// Day-strip scroller — centred on "Today" when the screen first opens.
  final ScrollController _weekScroll = ScrollController();
  // Day chip = 52 wide + 4+4 margin; the strip starts 3 days before today.
  static const double _chipExtent = 60;
  static const int _todayIndex = 3;

  /// Bulk-reschedule selection. When [_selectMode] is on, un-recorded patient
  /// rows show a checkbox and can be moved to another date together.
  bool _selectMode = false;
  final Set<int> _selected = {};
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday());
  }

  @override
  void dispose() {
    _weekScroll.dispose();
    super.dispose();
  }

  void _centerToday() {
    if (!_weekScroll.hasClients) return;
    final vp = _weekScroll.position.viewportDimension;
    // Centre of Today's chip minus half the viewport = scroll so it sits middle.
    final target = (12 + _todayIndex * _chipExtent + 26) - vp / 2;
    _weekScroll.jumpTo(target.clamp(0.0, _weekScroll.position.maxScrollExtent));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _onSelectedDay(int millis) =>
      _sameDay(DateTime.fromMillisecondsSinceEpoch(millis), _selectedDay);

  /// The scheduled encounter time for a patient (epoch millis): the chosen
  /// visit date, else an appointment, else the latest visit, else last contact.
  int _encounterMillis(Patient p, ClinicalService svc) {
    if (p.visitDate != 0) return p.visitDate;
    final v = svc.latestVisitForPatient(p.id);
    if (v != null && v.visitDate != 0) return v.visitDate;
    if (v != null) return v.createdAt;
    return p.lastContactDate;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final svc = context.watch<ClinicalService>();
    var patients = state.visiblePatients;

    // Filter to the selected day. Searching bypasses the day filter so any
    // patient is always findable.
    final searching = state.searchQuery.trim().isNotEmpty;
    if (!searching) {
      patients = patients
          .where((p) => _onSelectedDay(_encounterMillis(p, svc)))
          .toList();
    }

    final sorted = [...patients];
    if (_sort == _PatientSort.name) {
      sorted
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      sorted.sort((a, b) =>
          _encounterMillis(a, svc).compareTo(_encounterMillis(b, svc)));
    }

    // Only un-recorded patients can be moved (recorded ones are already done,
    // and deleting their visit would discard the audio).
    final selectableIds =
        sorted.where((p) => !svc.patientRecorded(p.id)).map((p) => p.id).toSet();

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          _header(context, state, svc, searching),
          _statusBars(svc),
          _listHeader(selectableIds, searching),
          if (svc.loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await svc.refresh();
                await state.refreshPatients();
              },
              child: _encounterList(context, svc, sorted, searching),
            ),
          ),
          if (_selectMode) _moveBar(context, svc, state),
        ],
      ),
    );
  }

  // --- Header: title, search, and the day strip ---------------------------

  Widget _header(BuildContext context, AppState state, ClinicalService svc,
      bool searching) {
    final isToday = _sameDay(_selectedDay, DateTime.now());
    return NotenraHeader.titled(
      title: 'Schedule',
      subtitle: searching
          ? 'Searching all days'
          : isToday
              ? 'Today · ${DateFormat('EEEE, MMM d').format(_selectedDay)}'
              : DateFormat('EEEE, MMMM d').format(_selectedDay),
      showBack: false,
      leading: const SizedBox(width: Nx.s2),
      actions: [
        HeaderIconButton(
          icon: Icons.calendar_month,
          tooltip: 'Pick a date',
          onTap: _pickDay,
        ),
        HeaderIconButton(
          icon: Icons.person_add_alt,
          tooltip: 'Add patient',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AddPatientScreen())),
        ),
      ],
      bottom: Column(
        children: [
          _searchField(state),
          const SizedBox(height: Nx.s3),
          _weekStrip(),
        ],
      ),
    );
  }

  /// Search sits inside the header panel, so the list below starts at a clean
  /// edge rather than under a stack of floating controls.
  Widget _searchField(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s4),
      child: SizedBox(
        height: 44,
        child: TextField(
          onChanged: (v) => state.searchQuery = v,
          style: const TextStyle(fontSize: 14, color: Nx.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search patients, MRN…',
            prefixIcon: const Icon(Icons.search, color: Nx.muted, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Nx.rSm),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Nx.rSm),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Nx.rSm),
                borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget _weekStrip() {
    final start = DateTime.now().subtract(const Duration(days: 3));
    final base = DateTime(start.year, start.month, start.day);
    final days = List.generate(21, (i) => base.add(Duration(days: i)));
    return SizedBox(
      height: 62,
      child: SingleChildScrollView(
        controller: _weekScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Nx.s3),
        child: Row(children: [for (final d in days) _dayChip(d)]),
      ),
    );
  }

  /// Day chips read as part of the brand panel: translucent white on the
  /// gradient, inverting to solid white for the selected day.
  Widget _dayChip(DateTime day) {
    final isToday = _sameDay(day, DateTime.now());
    final selected = _sameDay(day, _selectedDay);
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Nx.rSm),
          border: Border.all(
            color: Colors.white.withValues(alpha: selected ? 1 : 0.18),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('EEE').format(day).toUpperCase(),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: selected
                        ? Nx.primary
                        : Colors.white.withValues(alpha: 0.75))),
            const SizedBox(height: 2),
            Text('${day.day}',
                style: TextStyle(
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: selected ? Nx.ink : Colors.white)),
            const SizedBox(height: 2),
            // Underline marks today; it turns green once today is selected.
            Container(
              width: isToday ? 14 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? Nx.accent : Colors.white,
                borderRadius: BorderRadius.circular(Nx.rPill),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Go to date',
    );
    if (picked != null) setState(() => _selectedDay = picked);
  }

  // --- Status bars --------------------------------------------------------

  Widget _statusBars(ClinicalService svc) {
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
              icon: Icons.cloud_off, color: Nx.danger, message: svc.error!),
      ],
    );
  }

  // --- List header: select mode, move, sort -------------------------------

  Widget _listHeader(Set<int> selectableIds, bool searching) {
    if (_selectMode) {
      final allSelected =
          selectableIds.isNotEmpty && _selected.containsAll(selectableIds);
      return Padding(
        padding: const EdgeInsets.fromLTRB(Nx.s5, Nx.s3, Nx.s2, 0),
        child: Row(
          children: [
            Text('${_selected.length} SELECTED',
                style: Nx.sectionLabel.copyWith(color: Nx.primary)),
            const Spacer(),
            TextButton(
              onPressed: selectableIds.isEmpty
                  ? null
                  : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(selectableIds);
                        }
                      }),
              style: _denseButton(Nx.primary),
              child: Text(allSelected ? 'Clear all' : 'Select all',
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
              style: _denseButton(Nx.muted),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Nx.s5, Nx.s3, Nx.s2, 0),
      child: Row(
        children: [
          Text(searching ? 'SEARCH RESULTS' : 'PATIENTS',
              style: Nx.sectionLabel),
          const Spacer(),
          if (selectableIds.isNotEmpty && !searching)
            TextButton.icon(
              onPressed: () => setState(() => _selectMode = true),
              style: _denseButton(Nx.primary),
              icon: const Icon(Icons.event_repeat, size: 15),
              label: const Text('Move',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          _sortMenu(),
        ],
      ),
    );
  }

  ButtonStyle _denseButton(Color color) => TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: Nx.s2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _sortMenu() {
    return PopupMenuButton<_PatientSort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (v) => setState(() => _sort = v),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => const [
        PopupMenuItem(value: _PatientSort.time, child: Text('By time')),
        PopupMenuItem(value: _PatientSort.name, child: Text('By name')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Nx.s2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 15, color: Nx.muted),
            const SizedBox(width: 4),
            Text(_sort == _PatientSort.time ? 'Time' : 'Name',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Nx.secondary)),
            const Icon(Icons.arrow_drop_down, size: 18, color: Nx.muted),
          ],
        ),
      ),
    );
  }

  // --- Bulk reschedule ("Move to date") ----------------------------------

  Widget _moveBar(BuildContext context, ClinicalService svc, AppState state) {
    final n = _selected.length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s3, Nx.s4, Nx.s3),
        decoration: BoxDecoration(
          color: Nx.card,
          border: const Border(top: BorderSide(color: Nx.border)),
          boxShadow: Nx.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                  n == 0
                      ? 'Select patients to move'
                      : n == 1
                          ? '1 patient · pick date & time'
                          : '$n patients · pick date',
                  style: TextStyle(
                      color: n == 0 ? Nx.muted : Nx.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: Nx.s4, vertical: Nx.s3),
                minimumSize: Size.zero,
              ),
              onPressed: (n == 0 || _moving)
                  ? null
                  : () => _moveSelected(context, svc, state),
              icon: _moving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.event_available, size: 18),
              label: Text(_moving ? 'Moving…' : 'Move to date'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveSelected(
      BuildContext context, ClinicalService svc, AppState state) async {
    final ids = _selected.toList();
    final single = ids.length == 1;
    final now = DateTime.now();
    final base = _selectedDay;
    var initial =
        DateTime(base.year, base.month, base.day).add(const Duration(days: 1));
    if (initial.isBefore(now)) initial = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: single ? 'Move to date' : 'Move ${ids.length} patients to',
    );
    if (picked == null) return;

    // A single patient also gets a specific time; bulk moves keep each visit's
    // original time (per the workflow — no per-patient time for a batch).
    String? overrideTime;
    if (single) {
      final v = svc.latestVisitForPatient(ids.first);
      final initialTime = (v != null && v.visitDate != 0)
          ? TimeOfDay.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(v.visitDate))
          : TimeOfDay.now();
      if (!context.mounted) return;
      final t = await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: 'Visit time',
      );
      if (t == null) return; // cancelled the time step → abort the move
      overrideTime =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    setState(() => _moving = true);
    var moved = 0;
    for (final pid in ids) {
      final v = svc.latestVisitForPatient(pid);
      if (v == null) continue;
      if (await svc.rescheduleVisit(v.id, picked, overrideTime: overrideTime)) {
        moved++;
      }
    }
    await svc.refresh();
    await state.refreshPatients();
    if (!context.mounted) return;
    setState(() {
      _moving = false;
      _selectMode = false;
      _selected.clear();
    });
    final whenLabel = overrideTime != null
        ? '${DateFormat('EEE, MMM d').format(picked)}, $overrideTime'
        : DateFormat('EEE, MMM d').format(picked);
    final msg = moved == 0
        ? (svc.error ?? 'Could not move the patients.')
        : 'Moved $moved patient${moved == 1 ? '' : 's'} to $whenLabel.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- The list, split into "To see" and "Recorded" -----------------------

  int _recordedMillis(Patient p, ClinicalService svc) =>
      svc.recordedVisitForPatient(p.id)?.createdAt ?? 0;

  Widget _encounterList(BuildContext context, ClinicalService svc,
      List<Patient> items, bool searching) {
    if (items.isEmpty) {
      return ListView(
          children: [const SizedBox(height: 60), _emptyState(searching)]);
    }

    final toSee = items.where((p) => !svc.patientRecorded(p.id)).toList();
    final done = items.where((p) => svc.patientRecorded(p.id)).toList()
      // Most-recently recorded first, so the just-finished visit sits on top.
      ..sort(
          (a, b) => _recordedMillis(b, svc).compareTo(_recordedMillis(a, svc)));

    final children = <Widget>[];

    if (toSee.isNotEmpty) {
      children.add(SectionHeader(
        label: 'To see',
        icon: Icons.schedule,
        count: toSee.length,
        padding: const EdgeInsets.fromLTRB(Nx.s1, 0, 0, Nx.s2),
      ));
      for (final p in toSee) {
        final selected = _selected.contains(p.id);
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: Nx.s2),
          child: Pressable(
            child: _encounterRow(context, p, svc,
                selecting: _selectMode,
                selected: selected,
                onToggle: () => setState(() {
                      if (selected) {
                        _selected.remove(p.id);
                      } else {
                        _selected.add(p.id);
                      }
                    })),
          ),
        ));
      }
    }

    if (done.isNotEmpty) {
      children.add(SectionHeader(
        label: 'Recorded',
        icon: Icons.check_circle_outline,
        count: done.length,
        accent: Nx.accent,
        padding: const EdgeInsets.fromLTRB(Nx.s1, Nx.s4, 0, Nx.s2),
      ));
      for (final p in done) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: Nx.s2),
          child: Pressable(child: _encounterRow(context, p, svc, done: true)),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s2, Nx.s4, Nx.s8),
      children: children,
    );
  }

  // --- A single encounter row --------------------------------------------

  Widget _encounterRow(BuildContext context, Patient p, ClinicalService svc,
      {bool done = false,
      bool selecting = false,
      bool selected = false,
      VoidCallback? onToggle}) {
    final recorded = svc.patientRecorded(p.id);
    final visit = recorded ? svc.recordedVisitForPatient(p.id) : null;
    final recCount = recorded ? svc.recordedCountForPatient(p.id) : 0;
    final s = recorded ? styleFor(visit?.status) : upcomingStyle;
    final dt = DateTime.fromMillisecondsSinceEpoch(_encounterMillis(p, svc));
    final visitType = _visitTypeOf(p, svc);

    return NxCard(
      accentEdge: s.color,
      color: selected
          ? Nx.primary.withValues(alpha: 0.08)
          : recorded
              ? s.tint
              : Nx.card,
      borderColor: selected
          ? Nx.primary
          : recorded
              ? s.color.withValues(alpha: 0.25)
              : Nx.border,
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: Nx.s3),
      onTap: selecting
          ? onToggle
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PatientVisitScreen(patientId: p.id))),
      child: Row(
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: Nx.s2),
              child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? Nx.primary : Nx.outline,
                  size: 22),
            ),
          SizedBox(
            width: 44,
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
          const SizedBox(width: Nx.s1),
          NxAvatar(name: p.name, radius: 16, done: done),
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
                        fontWeight: FontWeight.w700,
                        color: Nx.ink,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                    visitType.isEmpty
                        ? 'MRN ${p.mrn}'
                        : 'MRN ${p.mrn}  ·  $visitType',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Nx.muted, fontSize: 11.5)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(label: s.label, color: s.color, icon: s.icon),
                    if (recCount > 1)
                      StatusPill(
                          label: '$recCount recordings',
                          color: Nx.muted,
                          icon: Icons.graphic_eq),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Nx.s2),
          if (!selecting) _rowAction(context, p, visit, recorded),
        ],
      ),
    );
  }

  /// Primary action on a row — always the next step in the workflow:
  ///   not recorded           -> Record
  ///   scribe finished a note -> Review
  ///   approved / in EHR      -> View
  ///   otherwise recorded     -> Add (capture another recording)
  Widget _rowAction(
      BuildContext context, Patient p, Visit? visit, bool recorded) {
    switch (visit?.status) {
      case VisitStatus.readyForReview:
        return NxPillButton(
          label: 'Review',
          icon: Icons.rate_review_outlined,
          color: Nx.accent,
          onTap: () => _openReview(context, visit!.id),
        );
      case VisitStatus.approved:
      case VisitStatus.syncedToEhr:
        return NxPillButton(
          label: 'View',
          icon: Icons.visibility_outlined,
          color: Nx.primary,
          tonal: true,
          onTap: () => _openReview(context, visit!.id),
        );
      default:
        return NxPillButton(
          label: recorded ? 'Add' : 'Record',
          icon: Icons.mic,
          color: recorded ? Nx.primary : Nx.accent,
          tonal: recorded,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PatientVisitScreen(patientId: p.id, autoStart: true))),
        );
    }
  }

  void _openReview(BuildContext context, String visitId) =>
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NoteReviewScreen(visitId: visitId)));

  // --- Helpers ------------------------------------------------------------

  /// Visit type: chosen on add, else the latest visit's type. '' when unknown.
  String _visitTypeOf(Patient p, ClinicalService svc) => p.visitType.isNotEmpty
      ? p.visitType
      : (svc.latestVisitForPatient(p.id)?.visitType ?? '');

  Widget _emptyState(bool searching) {
    if (searching) {
      return const NxEmptyState(
        icon: Icons.search_off,
        title: 'No patients match that search',
        hint: 'Try a name or an MRN.',
      );
    }
    final isToday = _sameDay(_selectedDay, DateTime.now());
    return NxEmptyState(
      icon: Icons.event_available_outlined,
      title: isToday
          ? 'Nothing scheduled today'
          : 'Nothing on ${DateFormat('EEEE, MMM d').format(_selectedDay)}',
      hint: 'Add a patient to this day to get started.',
      action: FilledButton.icon(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AddPatientScreen())),
        icon: const Icon(Icons.person_add_alt, size: 18),
        label: const Text('Add patient'),
      ),
    );
  }
}
