import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/clinical_service.dart';
import '../theme.dart';
import '../widgets/notenra_header.dart';
import '../widgets/nx.dart';
import '../widgets/pressable.dart';

/// Per-patient capture screen: record / pause / stop / manage audio.
///
/// The recorder is the hero and owns the screen. Patient context (DOB, visit
/// time, history) is one tap away in a sheet rather than a permanent card —
/// during a consultation the clinician needs the timer and the stop target, not
/// a demographics panel. The rest of the workflow (note, EHR) happens elsewhere.
class PatientVisitScreen extends StatefulWidget {
  final int patientId;
  final bool autoStart;
  const PatientVisitScreen(
      {super.key, required this.patientId, this.autoStart = false});

  @override
  State<PatientVisitScreen> createState() => _PatientVisitScreenState();
}

class _PatientVisitScreenState extends State<PatientVisitScreen>
    with SingleTickerProviderStateMixin {
  // Drives the flowing motion of the live waveform (only runs while recording).
  late final AnimationController _waveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      await state.openPatientVisit(widget.patientId);
      // Pre-warm mic permission so the auto-start (and the first manual tap)
      // begins capture in a single tap, without the OS dialog racing it.
      final granted = await state.ensureMicPermission();
      if (widget.autoStart && granted && !state.isRecording) {
        await _start();
      }
    });
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Starts recording — but first the clinician must confirm the patient has
  /// agreed to be recorded (the in-app consent gate, mirroring the web app).
  Future<void> _start() async {
    final state = context.read<AppState>();
    if (state.isRecording) return;
    final ok = await _confirmConsent();
    if (ok != true || !mounted) return;
    await state.startRecording(widget.patientId);
  }

  /// Patient-recording consent gate shown before the mic starts. The clinician
  /// confirms the patient was informed and agreed to be recorded; only then does
  /// capture begin. (The server-side consent record is sent silently at upload.)
  Future<bool?> _confirmConsent() {
    final patient = context.read<AppState>().selectedPatient;
    final who = patient?.name ?? 'this patient';
    bool checked = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Nx.accentSoft,
                  borderRadius: BorderRadius.circular(Nx.rSm),
                ),
                child: const Icon(Icons.mic, color: Nx.accent, size: 22),
              ),
              const SizedBox(width: Nx.s3),
              const Expanded(
                child: Text('Recording consent',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Nx.ink)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Before recording this encounter, confirm that $who has been '
                'informed that audio will be captured for clinical documentation '
                'and has agreed to be recorded.',
                style: const TextStyle(
                    fontSize: 14, height: 1.5, color: Nx.secondary),
              ),
              const SizedBox(height: Nx.s4),
              InkWell(
                onTap: () => setLocal(() => checked = !checked),
                borderRadius: BorderRadius.circular(Nx.rSm),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(Nx.s2, 4, Nx.s3, 4),
                  decoration: BoxDecoration(
                    color: checked ? Nx.accentSoft : Nx.surface,
                    borderRadius: BorderRadius.circular(Nx.rSm),
                    border: Border.all(
                        color: checked ? Nx.accent : Nx.border),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: checked,
                        activeColor: Nx.accent,
                        onChanged: (v) => setLocal(() => checked = v ?? false),
                      ),
                      const Expanded(
                        child: Text('Patient authorizes recording',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Nx.ink)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nx.accent),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Start recording'),
            ),
          ],
        ),
      ),
    );
  }

  /// A recording longer than this asks for confirmation before a whole-card tap
  /// ends it. The card is a deliberately huge target, so a stray tap during a
  /// long visit would otherwise split the encounter into two files. The explicit
  /// stop button is a deliberate press and never asks.
  static const _confirmStopAfter = Duration(minutes: 2);

  /// Stop triggered by tapping the card. Confirms first once the recording is
  /// long enough to be worth protecting; short ones stop immediately (cheap to
  /// redo, and the prompt would just be friction).
  Future<void> _stopFromCardTap(AppState state) async {
    if (state.recordingSeconds >= _confirmStopAfter.inSeconds) {
      final ok = await _confirmStop(state.recordingSeconds);
      if (ok != true || !mounted) return;
    }
    await _stopAndSubmit();
  }

  Future<bool?> _confirmStop(int seconds) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop recording?',
              style:
                  TextStyle(fontWeight: FontWeight.w800, color: Nx.ink)),
          content: Text(
            'This visit has been recording for ${_fmt(seconds * 1000)}. '
            'Stopping saves it and sends it to the scribe.',
            style:
                const TextStyle(fontSize: 14, height: 1.5, color: Nx.secondary),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep recording')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nx.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop'),
            ),
          ],
        ),
      );

  /// Stop recording. The recording is saved and shown immediately; securing it
  /// at rest and sending it to the scribe happen in the background (offline-safe)
  /// so a long recording never freezes the app on stop. No review screen — the
  /// scribe completes the note; it appears in the Notes tab when ready.
  Future<void> _stopAndSubmit() async {
    final state = context.read<AppState>();
    final saved = await state.stopAndSaveRecording();
    if (!mounted) return;
    final msg = saved == null
        ? 'Nothing was recorded.'
        : 'Recording saved — securing it and sending to the scribe.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final svc = context.watch<ClinicalService>();
    final patient = state.selectedPatient;
    final isThis = state.recordingPatientId == widget.patientId;
    final recording = isThis && state.isRecording;

    // Run the waveform animation only while actively recording (saves power).
    if (recording && !state.isPaused && !_waveCtrl.isAnimating) {
      _waveCtrl.repeat();
    } else if ((!recording || state.isPaused) && _waveCtrl.isAnimating) {
      _waveCtrl.stop();
    }

    final visitType = patient == null ? '' : _visitTypeOf(patient, svc);
    final subtitle = patient == null
        ? null
        : [
            'MRN ${patient.mrn}',
            if (visitType.isNotEmpty) visitType,
          ].join('  ·  ');

    return Scaffold(
      backgroundColor: Nx.canvas,
      body: Column(
        children: [
          NotenraHeader.titled(
            title: patient?.name ?? 'Visit',
            subtitle: subtitle,
            actions: [
              if (patient != null)
                HeaderIconButton(
                  icon: Icons.info_outline,
                  tooltip: 'Patient details',
                  onTap: () => _showPatientSheet(patient, svc),
                ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Nx.s4, Nx.s5, Nx.s4, Nx.s8),
              children: [
                _recorderCard(state, recording),
                const SizedBox(height: Nx.s6),
                _recordingsSection(state, svc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Patient context sheet ---------------------------------------------

  /// Full patient context on demand. Keeping it out of the main column is what
  /// lets the recorder sit high on the screen and stay thumb-reachable.
  void _showPatientSheet(Patient patient, ClinicalService svc) {
    final visit = svc.latestVisitForPatient(patient.id);
    final visitType = _visitTypeOf(patient, svc);
    final dobRaw = patient.dob.trim();
    final dob = (dobRaw.isEmpty || dobRaw == 'null')
        ? ''
        : (dobRaw.length >= 10 ? dobRaw.substring(0, 10) : dobRaw);
    final visitMillis =
        patient.visitDate != 0 ? patient.visitDate : (visit?.visitDate ?? 0);
    final visitWhen = visitMillis != 0
        ? DateFormat('MMM d, yyyy · h:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(visitMillis))
        : '';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Nx.s5, 0, Nx.s5, Nx.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NxAvatar(name: patient.name, radius: 22),
                  const SizedBox(width: Nx.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(patient.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Nx.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text('MRN ${patient.mrn}',
                            style: const TextStyle(
                                color: Nx.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (visitType.isNotEmpty)
                    StatusPill(label: visitType, color: Nx.primary),
                ],
              ),
              const SizedBox(height: Nx.s4),
              Wrap(
                spacing: Nx.s2,
                runSpacing: Nx.s2,
                children: [
                  if (dob.isNotEmpty)
                    _infoItem(Icons.cake_outlined, 'DOB',
                        patient.age > 0 ? '$dob  (${patient.age} yr)' : dob),
                  if (visitWhen.isNotEmpty)
                    _infoItem(Icons.event_outlined, 'Visit', visitWhen),
                  if (patient.gender.trim().isNotEmpty)
                    _infoItem(Icons.person_outline, 'Sex', patient.gender),
                ],
              ),
              if (patient.medicalHistory.trim().isNotEmpty) ...[
                const SizedBox(height: Nx.s5),
                const SectionHeader(label: 'History'),
                Text(patient.medicalHistory,
                    style: const TextStyle(
                        color: Nx.secondary, fontSize: 13.5, height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s3, vertical: 7),
      decoration: BoxDecoration(
        color: Nx.surface,
        borderRadius: BorderRadius.circular(Nx.rSm),
        border: Border.all(color: Nx.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Nx.primary),
          const SizedBox(width: 6),
          Text('$label ',
              style: const TextStyle(color: Nx.muted, fontSize: 11.5)),
          Text(value,
              style: const TextStyle(
                  color: Nx.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // --- The recorder -------------------------------------------------------

  Widget _recorderCard(AppState state, bool recording) {
    final paused = recording && state.isPaused;
    // Live capture is brand green — the same colour as the pulse in the mark and
    // the app-wide recording banner. Amber means paused. Red is only ever the
    // stop control, so "stop" is the one destructive-looking thing on screen.
    final live = paused ? Nx.warning : Nx.accent;

    // The WHOLE card is the primary control: tap anywhere to start, and tap
    // anywhere to stop — so mid-visit the clinician never has to aim for a
    // small button. The pause/stop buttons inside stay their own controls: a tap
    // on one wins the gesture arena, so it pauses instead of stopping.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: recording ? () => _stopFromCardTap(state) : _start,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(Nx.s6, Nx.s8, Nx.s6, Nx.s6),
        decoration: BoxDecoration(
          color: Nx.card,
          borderRadius: BorderRadius.circular(Nx.rXl),
          border: Border.all(
              color: recording ? live.withValues(alpha: 0.45) : Nx.border,
              width: recording ? 1.5 : 1),
          boxShadow: Nx.cardShadow,
        ),
        child: Column(
          children: [
            if (recording)
              StatusPill(
                label: paused ? 'PAUSED' : 'RECORDING',
                color: live,
                icon: paused ? Icons.pause : Icons.fiber_manual_record,
                solid: true,
              )
            else
              Text('Ready to record',
                  style: Nx.sectionLabel.copyWith(fontSize: 11.5)),
            const SizedBox(height: Nx.s4),
            Text(
              recording ? _fmt(state.recordingSeconds * 1000) : '00:00',
              style: TextStyle(
                fontSize: 56,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
                color: recording ? live : Nx.outline,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: Nx.s5),
            // The waveform holds its slot whether or not capture is running, so
            // starting a recording doesn't shove the controls down the screen.
            SizedBox(
              height: 82,
              child: recording
                  ? _waveform(state.recordingLevel, paused)
                  : _idleTrace(),
            ),
            const SizedBox(height: Nx.s6),
            if (!recording)
              _circleButton(
                color: Nx.accent,
                icon: Icons.mic,
                size: 44,
                onTap: _start,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circleButton(
                    color: Nx.warning,
                    icon: paused ? Icons.play_arrow : Icons.pause,
                    size: 32,
                    onTap: () => paused
                        ? state.resumeRecording()
                        : state.pauseRecording(),
                  ),
                  const SizedBox(width: Nx.s8),
                  _circleButton(
                    color: Nx.danger,
                    icon: Icons.stop,
                    size: 40,
                    onTap: _stopAndSubmit,
                  ),
                ],
              ),
            const SizedBox(height: Nx.s4),
            Text(
              recording
                  ? (paused
                      ? 'Tap anywhere to stop  ·  play to resume'
                      : 'Tap anywhere to stop  ·  pause below')
                  : 'Tap anywhere to start recording',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Nx.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Live, flowing waveform that mirrors around the centre line with a
  /// green→blue gradient across the bars — the brand pulse, animated. Bar
  /// heights respond to the microphone [level]; the motion comes from
  /// [_waveCtrl]. Dims when [paused].
  Widget _waveform(double level, bool paused) {
    const bars = 30;
    const maxH = 82.0;
    final amp = paused ? 0.12 : (0.28 + 0.72 * level.clamp(0.0, 1.0));
    return SizedBox(
      height: maxH,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _waveCtrl,
        builder: (context, _) {
          final phase = _waveCtrl.value * 2 * math.pi;
          // Scale the bar row down if it would be wider than the card, so it
          // never overflows on a narrow screen.
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(bars, (i) {
                // Centre-weighted arch so the wave is tallest in the middle.
                final arch = math.sin(math.pi * (i + 0.5) / bars);
                // Two offset sines give an organic, non-repeating ripple.
                final ripple = 0.5 +
                    0.5 *
                        (0.6 * math.sin(phase + i * 0.55) +
                            0.4 * math.sin(phase * 1.7 + i * 0.3));
                final h = (6.0 + arch * ripple * amp * maxH).clamp(5.0, maxH);
                final color =
                    Color.lerp(Nx.accent, Nx.primary, i / (bars - 1))!;
                return Container(
                  width: 5,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: paused ? color.withValues(alpha: 0.35) : color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  /// Flat baseline shown before capture starts — reserves the waveform's space
  /// and hints at what will appear there.
  Widget _idleTrace() {
    return Center(
      child: Container(
        height: 4,
        width: 180,
        decoration: BoxDecoration(
          color: Nx.border,
          borderRadius: BorderRadius.circular(Nx.rPill),
        ),
      ),
    );
  }

  Widget _circleButton(
      {required Color color,
      required IconData icon,
      required double size,
      required VoidCallback onTap}) {
    return Pressable(
      scale: 0.92,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: size + 4,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }

  // --- Recordings ---------------------------------------------------------

  Widget _recordingsSection(AppState state, ClinicalService svc) {
    // Total recordings the SERVER holds for this patient (a visit can hold
    // several). Local files are just the ones captured on THIS device.
    final serverCount = svc.recordedCountForPatient(widget.patientId);
    final localCount = state.recordings.length;
    // Recordings the server has that aren't stored on this device — e.g. made in
    // the web app or on another phone (or the local copy was purged).
    final remoteOnly = (serverCount - localCount).clamp(0, 9999);

    if (localCount == 0) {
      // No local copy on THIS device. If the patient is recorded on the server,
      // say so clearly (with the count) rather than the misleading "none yet".
      if (serverCount > 0) {
        return NxCard(
          padding: EdgeInsets.zero,
          child: NxEmptyState(
            icon: Icons.cloud_done_outlined,
            title: serverCount == 1
                ? 'Recording uploaded'
                : '$serverCount recordings uploaded',
            hint:
                'This visit is "${svc.patientStatusLabel(widget.patientId)}". '
                'The audio is safely on the server with the scribe — a local '
                'copy isn\'t kept on this device.',
          ),
        );
      }
      return const NxCard(
        padding: EdgeInsets.zero,
        child: NxEmptyState(
          icon: Icons.graphic_eq,
          title: 'No recordings yet',
          hint: 'Recordings you capture here will be listed below.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          label: 'Recordings',
          icon: Icons.graphic_eq,
          count: localCount,
          padding: const EdgeInsets.fromLTRB(Nx.s1, 0, 0, Nx.s2),
        ),
        for (final r in state.recordings)
          Padding(
            padding: const EdgeInsets.only(bottom: Nx.s2),
            child: _recordingRow(state, r),
          ),
        if (remoteOnly > 0) _remoteOnlyNote(remoteOnly),
      ],
    );
  }

  Widget _recordingRow(AppState state, Recording r) {
    final playing = state.playingPath == r.audioFilePath;
    final ts = DateFormat('MMM d, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(r.timestamp));
    return NxCard(
      padding: const EdgeInsets.symmetric(horizontal: Nx.s2, vertical: Nx.s2),
      child: Row(
        children: [
          // Every recording is playable — the clinician can replay it to confirm
          // what was captured, even after it's gone to the scribe.
          IconButton(
            onPressed: () => state.playRecording(r.audioFilePath),
            tooltip: playing ? 'Stop playback' : 'Play',
            icon: Icon(playing ? Icons.stop_circle : Icons.play_circle_fill,
                color: Nx.primary, size: 34),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Nx.ink,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (r.isUploaded) ...[
                      const Icon(Icons.cloud_done, size: 13, color: Nx.accent),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        r.isUploaded
                            ? 'Sent to scribe · ${_fmt(r.durationMs)}'
                            : '${_fmt(r.durationMs)} · $ts',
                        style: const TextStyle(color: Nx.muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete local copy',
            onPressed: () => state.deleteRecording(r.id),
            icon: const Icon(Icons.delete_outline, color: Nx.danger, size: 20),
          ),
        ],
      ),
    );
  }

  /// Note shown when the server holds more recordings for this visit than are
  /// stored on this device (e.g. captured in the web app or on another phone).
  /// They're safe with the scribe; playback of those lives in the web app.
  Widget _remoteOnlyNote(int count) {
    return NxCard(
      color: Nx.primary.withValues(alpha: 0.06),
      borderColor: Nx.primary.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(Nx.s3),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, size: 20, color: Nx.primary),
          const SizedBox(width: Nx.s3),
          Expanded(
            child: Text(
              count == 1
                  ? '1 more recording is on the server (made elsewhere) and is '
                      'with the scribe.'
                  : '$count more recordings are on the server (made elsewhere) '
                      'and are with the scribe.',
              style: const TextStyle(
                  color: Nx.secondary, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _visitTypeOf(Patient p, ClinicalService svc) => p.visitType.isNotEmpty
      ? p.visitType
      : (svc.latestVisitForPatient(p.id)?.visitType ?? '');
}
