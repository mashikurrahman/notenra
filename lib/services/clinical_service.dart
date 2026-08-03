import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../secure_store.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/clinical_models.dart';
import '../api/live_backend.dart';
import '../api/mock_backend.dart';
import '../api/token_store.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';
import 'sync_engine.dart';

/// Orchestrates the clinician note-review workflow over whichever backend is
/// active (demo vs live), with optimistic updates and an offline outbox.
///
/// The UI watches this; it never talks to a backend directly.
class ClinicalService extends ChangeNotifier {
  static const _secure = SecureStore();
  static const _modeKey = 'backend_mode'; // 'demo' | 'live'

  /// Default backend on a fresh install (no stored choice yet). Live so a
  /// distributed build connects to the real server out of the box — no per-device
  /// setup. Build a demo/testing APK with `--dart-define=LIVE_BY_DEFAULT=false`.
  static const _defaultLive =
      bool.fromEnvironment('LIVE_BY_DEFAULT', defaultValue: true);

  final ConnectivityService connectivity;
  final TokenStore tokens;

  late ApiBackend _backend;
  late SyncEngine _sync;
  late final ApiClient _client;

  bool _live = false;
  bool get isLive => _live;
  String get backendLabel => _backend.label;

  ValueListenable<bool> get online => connectivity.online;
  ValueListenable<int> get pendingSync => _sync.pending;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  List<Visit> _visits = [];
  List<Visit> get visits => _visits;

  /// Visit ids the clinician has recorded in THIS session. Recording is a local
  /// fact the doctor just performed — it must stay "recorded" no matter what the
  /// server returns next (the server list can briefly lag attaching the audio).
  /// Without this, a just-recorded patient would bounce back into "To see" /
  /// NEXT UP on the next refresh. Source of truth on a fresh launch is still the
  /// server (this set starts empty each session).
  final Set<String> _recordedVisitIds = {};

  /// Visits the clinician still needs to act on (review queue), newest first.
  /// Empty "scheduled" visits (created when a patient is added but not yet
  /// recorded) are excluded — there's nothing to review until audio exists.
  List<Visit> get reviewQueue => _visits
      .where((v) =>
          v.status == VisitStatus.readyForReview ||
          v.status == VisitStatus.withScribe ||
          v.status == VisitStatus.changesRequested ||
          v.status == VisitStatus.failed ||
          (v.status == VisitStatus.pendingUpload && v.localAudioPath != null))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Visit> get completed => _visits
      .where((v) =>
          v.status == VisitStatus.approved || v.status == VisitStatus.syncedToEhr)
      .toList();

  Timer? _poll;

  /// [backend] is a test-only override; production passes nothing and the
  /// backend is chosen by the live/demo mode.
  final ApiBackend? _backendOverride;

  ClinicalService(
      {required this.connectivity, required this.tokens, ApiBackend? backend})
      : _backendOverride = backend {
    _client = ApiClient(tokens);
  }

  Future<void> init() async {
    final mode = await _secure.read(key: _modeKey);
    // No stored choice yet -> use the build default (Live for distributed builds).
    _live = mode == null ? _defaultLive : mode == 'live';
    _buildBackend();
    await _wireSync();
    // Don't block app launch on the first network fetch. The UI opens to the
    // login screen and shows its own loading state; blocking here on a slow
    // GET /visits (up to the request timeout) made cold start feel very slow.
    // Kick it off in the background; login re-runs refresh once authenticated.
    unawaited(refresh());
    _startPolling();
  }

  void _buildBackend() {
    _backend = _backendOverride ?? (_live ? LiveBackend(_client) : MockBackend());
  }

  Future<void> _wireSync() async {
    _sync = SyncEngine(backend: _backend, connectivity: connectivity);
    // Coalesce post-upload refreshes: many ops finishing together trigger ONE
    // list fetch, not one full GET /visits per visit (which rate-limits us).
    _sync.onOpApplied = (_, type) {
      _scheduleRefresh();
      // A queued recording reached the scribe — tell the clinician (generic,
      // PHI-free). Fires for both live and offline-then-reconnected uploads.
      if (type == SyncOpType.uploadAudio) {
        NotificationService.instance.recordingUploaded();
      }
    };
    // When the outbox creates the real server visit for an offline recording,
    // re-key the local copy so the UI tracks the real visit (and stays recorded).
    _sync.onVisitRemapped = (localId, realId) {
      final local = visitById(localId);
      if (local != null) {
        _visits.removeWhere((v) => v.id == localId);
        _upsert(Visit(
          id: realId,
          patientId: local.patientId,
          patientName: local.patientName,
          status: local.status,
          durationMs: local.durationMs,
          createdAt: local.createdAt,
          localAudioPath: local.localAudioPath,
          note: local.note,
          visitType: local.visitType,
          visitDate: local.visitDate,
        ));
      }
      if (_recordedVisitIds.remove(localId)) _recordedVisitIds.add(realId);
      AppLog.log('REC', 'remapped local $localId -> $realId');
      notifyListeners();
    };
    // A permanently-failed audio upload must be visible, not silently "done".
    _sync.onOpFailed = (visitId, type) {
      if (type == SyncOpType.uploadAudio) {
        final v = visitById(visitId);
        if (v != null && v.status != VisitStatus.approved) {
          _upsert(v.copyWith(status: VisitStatus.failed));
          notifyListeners();
        }
      }
    };
    await _sync.init();
  }

  /// Switch between demo data and the live server.
  Future<void> setLive(bool live) async {
    if (live == _live) return;
    _live = live;
    await _secure.write(key: _modeKey, value: live ? 'live' : 'demo');
    _buildBackend();
    await _wireSync();
    await refresh();
    notifyListeners();
  }

  // Last-seen status per visit, so we can detect a transition INTO
  // "ready for review" and fire one notification for it. Seeded (without
  // notifying) on the first load after sign-in so pre-existing ready notes
  // don't all alert at once.
  final Map<String, VisitStatus> _lastStatus = {};
  bool _statusSeeded = false;

  /// Fire a (generic, PHI-free) notification when a visit newly becomes
  /// "ready for review" — the scribe just finished the note. Only transitions
  /// notify; the first populated load just seeds the snapshot.
  void _notifyOnReadyForReview() {
    final seenBefore = _statusSeeded;
    for (final v in _visits) {
      final prev = _lastStatus[v.id];
      if (seenBefore &&
          v.status == VisitStatus.readyForReview &&
          prev != VisitStatus.readyForReview) {
        NotificationService.instance.noteReady();
      }
      _lastStatus[v.id] = v.status;
    }
    _statusSeeded = true;
  }

  Future<void> refresh() async {
    // In live mode there's nothing to load until the clinician has signed in.
    // The startup refresh (and any pre-auth call) would otherwise hit a 401 and
    // surface a misleading "session expired" banner on the very first launch,
    // which only clears on a manual reload. Bail quietly until authenticated.
    if (_live && !tokens.hasToken) {
      // Drop the server-sourced rows, but NEVER the ones captured on this
      // device: a recording that hasn't uploaded yet (or that was made this
      // session) is local truth the server has never seen. Wiping the whole
      // list here made a just-recorded patient bounce back to "to record" the
      // moment an unauthenticated refresh ran. Sign-out clears everything
      // deliberately via clearForLogout().
      _visits = _visits
          .where((v) =>
              v.localAudioPath != null || _recordedVisitIds.contains(v.id))
          .toList();
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // One quick retry absorbs a transient blip before we show an error.
      final fresh = await _withRetry(() => _backend.myVisits());
      _visits = _mergeLocalAudio(fresh);
      _notifyOnReadyForReview();
      _error = null;
    } catch (e) {
      _error = _live ? _failureReason(e) : 'Failed to load demo data.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The server is the source of truth, but audio captured on THIS device is
  /// local-only until the upload completes. Carry that pending local audio (and
  /// the "recorded" state it implies) across a refresh so a just-recorded
  /// patient doesn't briefly bounce back into NEXT UP while the upload is still
  /// in flight or retrying — and so an offline recording the server hasn't seen
  /// yet doesn't disappear from the list on refresh.
  List<Visit> _mergeLocalAudio(List<Visit> fresh) {
    if (_visits.isEmpty) return fresh;
    final localById = {for (final v in _visits) v.id: v};
    final freshIds = {for (final v in fresh) v.id};
    final merged = <Visit>[
      for (final sv in fresh) _carryLocalState(sv, localById[sv.id]),
    ];
    // Re-append local recordings the server list doesn't include yet (captured
    // offline / queued, or recorded this session before the server caught up),
    // so they never vanish from the list on refresh.
    for (final l in _visits) {
      if (!freshIds.contains(l.id) &&
          (l.localAudioPath != null || _recordedVisitIds.contains(l.id))) {
        merged.add(l);
      }
    }
    return merged;
  }

  /// Merge device-only state from the cached copy [local] onto the fresh server
  /// visit [sv] (the list fetch carries neither the local audio path nor the
  /// authored note body):
  ///   • pending local audio — so a just-recorded patient doesn't bounce back
  ///     to NEXT UP while the upload is still in flight;
  ///   • the note body — so a poll-driven refresh doesn't wipe the note the
  ///     review screen just fetched, making it flicker back to "Loading…".
  Visit _carryLocalState(Visit sv, Visit? local) {
    if (local == null) return sv;
    var out = sv;
    if (local.localAudioPath != null &&
        out.localAudioPath == null &&
        !_isRecordedVisit(sv)) {
      out = out.copyWith(localAudioPath: local.localAudioPath);
    }
    // Keep an already-loaded note across the refresh — but only while the
    // status is unchanged. If it changed (e.g. the scribe revised the note and
    // it's ready again), drop the cached body so the review screen re-fetches
    // the latest instead of showing a stale version.
    if (out.note == null &&
        local.note != null &&
        local.status == sv.status) {
      out = out.copyWith(note: local.note);
    }
    return out;
  }

  /// Runs [op], retrying once after a short pause on a non-auth failure so a
  /// momentary network blip doesn't surface as an error.
  Future<T> _withRetry<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on ApiException catch (e) {
      // Don't amplify load: a 401 won't fix itself, and a 429 means we're
      // already sending too much — retrying immediately makes it worse.
      if (e.isUnauthorized || e.isRateLimited) rethrow;
      await Future.delayed(const Duration(milliseconds: 700));
      return await op();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 700));
      return await op();
    }
  }

  // Debounced single refresh — collapses bursts of refresh triggers into one
  // list fetch instead of hammering the server.
  Timer? _refreshDebounce;
  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 900), refresh);
  }

  /// Turns a load failure into a clear, specific message (so the doctor sees the
  /// real reason — timeout, no connection, session expired — not a vague guess).
  String _failureReason(Object e) {
    if (e is ApiException) {
      if (e.isUnauthorized) return 'Session expired — please sign in again.';
      return '${e.message} Showing last known data.';
    }
    return 'Couldn\'t reach the server. Showing last known data.';
  }

  /// Wipe in-memory PHI (visits, notes) on sign-out. The on-disk encrypted
  /// vault and the offline outbox are intentionally preserved.
  void clearForLogout() {
    _visits = [];
    _error = null;
    // Re-seed status tracking next session so we don't alert for another
    // clinician's pre-existing ready notes on their first load.
    _lastStatus.clear();
    _statusSeeded = false;
    notifyListeners();
  }

  Visit? visitById(String id) {
    for (final v in _visits) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Fetch the full authored note for a visit and merge it into the cache.
  ///
  /// The list fetch (`myVisits`) carries only the visit *status*, not the note
  /// body — pulling every note on every list refresh is what previously
  /// rate-limited the API. So the review screen calls this on open to populate
  /// `visit.note`. Returns true once a note is present (already cached or just
  /// fetched). No-op offline. Never throws — failures surface as a still-empty
  /// note so the screen can show a retry instead of spinning forever.
  Future<bool> ensureNote(String visitId) async {
    if (visitById(visitId)?.note != null) return true; // already loaded
    if (!connectivity.online.value) return false;
    try {
      final fresh = await _backend.getVisit(visitId);
      final current = visitById(visitId);
      // Preserve any local-only audio path we were carrying for this visit.
      final merged = current?.localAudioPath != null && fresh.localAudioPath == null
          ? fresh.copyWith(localAudioPath: current!.localAudioPath)
          : fresh;
      _upsert(merged);
      if (_isRecordedVisit(merged)) _recordedVisitIds.add(merged.id);
      notifyListeners();
      AppLog.log('NOTE', 'ensureNote $visitId -> note=${merged.note != null}');
      return merged.note != null;
    } catch (e) {
      AppLog.log('NOTE', 'ensureNote failed for $visitId: $e');
      return false;
    }
  }

  /// All visits belonging to a patient.
  Iterable<Visit> _visitsForPatient(int patientId) =>
      _visits.where((v) => v.patientId == patientId);

  /// The patient's most recent visit (by creation time), if any is known.
  Visit? latestVisitForPatient(int patientId) {
    Visit? best;
    for (final v in _visitsForPatient(patientId)) {
      if (best == null || v.createdAt >= best.createdAt) best = v;
    }
    return best;
  }

  /// A visit counts as "recorded" once audio has been captured for it, or the
  /// note workflow has moved past the empty scheduled shell.
  bool _isRecordedVisit(Visit v) {
    if (_recordedVisitIds.contains(v.id)) return true; // recorded this session
    if (v.localAudioPath != null) return true;
    switch (v.status) {
      case VisitStatus.withScribe:
      case VisitStatus.readyForReview:
      case VisitStatus.changesRequested:
      case VisitStatus.approved:
      case VisitStatus.syncedToEhr:
      case VisitStatus.failed:
        return true;
      case VisitStatus.recording:
      case VisitStatus.pendingUpload:
        return false; // no audio yet → still an empty/queued shell
    }
  }

  /// The patient's most relevant *recorded* visit (newest), ignoring any empty
  /// scheduled shell that may also exist. Null if nothing has been captured.
  Visit? recordedVisitForPatient(int patientId) {
    Visit? best;
    for (final v in _visitsForPatient(patientId)) {
      if (!_isRecordedVisit(v)) continue;
      if (best == null || v.createdAt >= best.createdAt) best = v;
    }
    return best;
  }

  /// Whether the patient has any captured/processed visit — robust to a separate
  /// empty "scheduled" visit also existing for the same patient (so a recorded
  /// patient never lingers in the "to record" / NEXT UP list).
  bool patientRecorded(int patientId) =>
      recordedVisitForPatient(patientId) != null;

  /// How many recordings the patient has across their recorded visits — drives
  /// the "N recordings" badge. A single visit can hold several recordings
  /// (server keeps them as a comma-separated list), so we sum each visit's
  /// recording count (min 1 for a recorded visit whose count isn't known yet).
  int recordedCountForPatient(int patientId) => _visitsForPatient(patientId)
      .where(_isRecordedVisit)
      .fold(0, (sum, v) => sum + (v.recordingCount > 0 ? v.recordingCount : 1));

  /// Short status label for a recorded patient (e.g. "With scribe", "Approved").
  String patientStatusLabel(int patientId) =>
      recordedVisitForPatient(patientId)?.status.label ?? '';

  /// Count of notes the scribe has finished and that await the clinician.
  int get readyForReviewCount =>
      _visits.where((v) => v.status == VisitStatus.readyForReview).length;

  /// Create a visit and (optimistically) attach the just-captured audio,
  /// queuing the upload so it survives offline.
  Future<Visit?> submitRecording({
    required int patientId,
    required String patientName,
    required String audioPath,
    required int durationMs,
    String? existingVisitId,
  }) async {
    try {
      AppLog.log('REC',
          'submit patient=$patientId dur=${durationMs}ms existing=${existingVisitId ?? '-'}');
      // Resolve the target visit so a re-recording attaches to the patient's
      // existing visit instead of spawning duplicate visit cards. A visit can
      // hold multiple recordings server-side (comma-separated audio list), so an
      // additional recording should APPEND to the patient's current visit:
      //   explicit id  >  an un-recorded *server* shell  >  the newest recorded
      //   visit (append)  >  a brand-new visit.
      final reuseId = (existingVisitId != null && existingVisitId.isNotEmpty)
          ? existingVisitId
          : (_openUnrecordedVisitId(patientId) ??
              recordedVisitForPatient(patientId)?.id);

      Visit visit;
      if (reuseId != null && !_isLocalId(reuseId)) {
        // Attach to the existing real server visit.
        AppLog.log('REC', 'reuse server visit $reuseId');
        visit = visitById(reuseId) ??
            Visit(
              id: reuseId,
              patientId: patientId,
              patientName: patientName,
              status: VisitStatus.pendingUpload,
              durationMs: durationMs,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              localAudioPath: audioPath,
            );
      } else {
        // No real visit to reuse — create one on the server NOW so the audio is
        // never uploaded to a placeholder id the web app can't see. If the
        // server is unreachable, fall back to a local shell; the outbox will
        // create the real visit before uploading (see SyncEngine._apply).
        try {
          visit = await _backend.createVisit(
              patientId: patientId, patientName: patientName);
          AppLog.log('REC', 'created server visit ${visit.id}');
        } catch (e) {
          final localId = (reuseId != null && _isLocalId(reuseId))
              ? reuseId
              : 'local_${DateTime.now().millisecondsSinceEpoch}';
          AppLog.log('REC', 'createVisit failed ($e) -> local shell $localId');
          visit = Visit(
            id: localId,
            patientId: patientId,
            patientName: patientName,
            status: VisitStatus.pendingUpload,
            durationMs: durationMs,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            localAudioPath: audioPath,
          );
        }
      }
      // Optimistically reflect that this recording is one more on the visit, so
      // the "N recordings" count is right immediately (a later refresh / the
      // post-upload getVisit reconciles it to the true server count).
      final priorCount = visitById(visit.id)?.recordingCount ?? 0;
      visit = visit.copyWith(
        status: VisitStatus.pendingUpload,
        durationMs: durationMs,
        localAudioPath: audioPath,
        recordingCount: priorCount + 1,
      );
      // Mark this visit recorded for the session so it can never bounce back to
      // "to record" on a later refresh, regardless of server/upload timing.
      _recordedVisitIds.add(visit.id);
      _upsert(visit);
      notifyListeners();

      // Upload through the offline-safe outbox. Only reflect "with scribe" when
      // the upload ACTUALLY succeeded — otherwise the visit stays "pending
      // upload" and the queue retries, so the doctor is never falsely told the
      // recording reached the scribe. patientId/name ride along so the outbox
      // can create the real visit if this is a local shell.
      AppLog.log('REC', 'enqueue upload visit=${visit.id}');
      final uploaded = await _sync.enqueue(SyncOp(
        id: 's_${DateTime.now().microsecondsSinceEpoch}',
        type: SyncOpType.uploadAudio,
        visitId: visit.id,
        payload: {
          'audioPath': audioPath,
          'patientId': patientId,
          'patientName': patientName,
        },
      ));
      AppLog.log('REC',
          'enqueue done uploaded=$uploaded status=${visitById(visit.id)?.status.name}');
      if (uploaded) {
        try {
          // Pull the real server state (audio now attached -> with scribe).
          final fresh = await _backend.getVisit(visit.id);
          visit = fresh.copyWith(localAudioPath: audioPath);
        } catch (_) {
          visit = visit.copyWith(status: VisitStatus.withScribe);
        }
        _upsert(visit);
        notifyListeners();
      }
      return visit;
    } catch (e) {
      _error = 'Could not submit recording.';
      notifyListeners();
      return null;
    }
  }

  /// Id of an existing visit for the patient that has NOT been recorded yet (a
  /// scheduled shell), so a recording attaches there instead of creating a
  /// duplicate. Null when the patient has no open visit on record.
  /// A synthesized offline placeholder id (no server row exists for it yet).
  static bool _isLocalId(String id) => id.startsWith('local_');

  String? _openUnrecordedVisitId(int patientId) {
    for (final v in _visitsForPatient(patientId)) {
      if (!_isRecordedVisit(v)) return v.id;
    }
    return null;
  }

  /// Doctor's own small inline edit to the note text.
  Future<void> saveNoteEdit(String visitId, String content) async {
    final v = visitById(visitId);
    if (v != null && v.note != null) {
      _upsert(v.copyWith(
          status: VisitStatus.readyForReview,
          note: v.note!.copyWith(
              content: content,
              updatedAt: DateTime.now().millisecondsSinceEpoch)));
      notifyListeners();
    }
    await _sync.enqueue(SyncOp(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      type: SyncOpType.editNote,
      visitId: visitId,
      payload: {'content': content},
    ));
  }

  /// Send comments back to the scribe requesting changes.
  Future<void> requestChanges(String visitId, String comment) async {
    final v = visitById(visitId);
    if (v != null) {
      final history = [
        ...?v.note?.feedback,
        NoteFeedback(comment, DateTime.now().millisecondsSinceEpoch),
      ];
      _upsert(v.copyWith(
          status: VisitStatus.changesRequested,
          note: v.note?.copyWith(feedback: history)));
      notifyListeners();
    }
    await _sync.enqueue(SyncOp(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      type: SyncOpType.requestChanges,
      visitId: visitId,
      payload: {'comment': comment},
    ));
  }

  Future<void> approve(String visitId) async {
    final v = visitById(visitId);
    if (v != null) {
      _upsert(v.copyWith(status: VisitStatus.approved));
      notifyListeners();
    }
    await _sync.enqueue(SyncOp(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      type: SyncOpType.approveNote,
      visitId: visitId,
    ));
  }

  /// Move a patient's un-recorded visit to [targetDay]. When [overrideTime] is
  /// given ('HH:mm') it sets a new time; otherwise the visit's original time is
  /// kept. Returns true on success; sets [error] on failure.
  Future<bool> rescheduleVisit(String visitId, DateTime targetDay,
      {String? overrideTime}) async {
    final v = visitById(visitId);
    if (v == null) return false;
    final old = v.visitDate != 0
        ? DateTime.fromMillisecondsSinceEpoch(v.visitDate)
        : null;
    try {
      final created = await _backend.rescheduleVisit(
        oldVisitId: visitId,
        patientId: v.patientId,
        patientName: v.patientName,
        visitDate: _ymd(targetDay),
        visitTime: overrideTime ?? (old != null ? _hm(old) : '09:00'),
        visitType: v.visitType.isNotEmpty ? v.visitType : 'Follow-up',
      );
      _visits.removeWhere((e) => e.id == visitId);
      _upsert(created);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e is ApiException ? e.message : 'Could not move the visit.';
      notifyListeners();
      return false;
    }
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _upsert(Visit v) {
    final i = _visits.indexWhere((e) => e.id == v.id);
    if (i >= 0) {
      _visits[i] = v;
    } else {
      _visits = [v, ..._visits];
    }
  }

  /// Poll for scribe-side updates while something is in-flight. Critically this
  /// does ONE list fetch per tick (not one full GET /visits per in-flight visit,
  /// which previously hammered the API into 429 rate-limiting and starved the
  /// audio upload of its request budget).
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!connectivity.online.value) return;
      if (_loading) return; // a refresh is already running
      final hasInFlight = _visits.any((v) =>
          v.status == VisitStatus.withScribe ||
          v.status == VisitStatus.changesRequested ||
          (v.status == VisitStatus.pendingUpload && v.localAudioPath != null));
      if (!hasInFlight) return;
      await refresh(); // single fetch updates every in-flight visit at once
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }
}
