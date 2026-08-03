import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../secure_store.dart';
import '../api/backend.dart';
import 'connectivity_service.dart';

/// Mutations that must survive offline and replay on reconnect, in order.
enum SyncOpType {
  uploadAudio,
  editNote,
  requestChanges,
  approveNote,
}

class SyncOp {
  final String id;
  final SyncOpType type;
  final String visitId;
  final Map<String, dynamic> payload;
  int attempts;

  SyncOp({
    required this.id,
    required this.type,
    required this.visitId,
    this.payload = const {},
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'visitId': visitId,
        'payload': payload,
        'attempts': attempts,
      };

  factory SyncOp.fromJson(Map<String, dynamic> m) => SyncOp(
        id: m['id'].toString(),
        type: SyncOpType.values
            .firstWhere((t) => t.name == m['type'], orElse: () => SyncOpType.requestChanges),
        visitId: m['visitId'].toString(),
        payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        attempts: (m['attempts'] is num) ? (m['attempts'] as num).toInt() : 0,
      );
}

/// Offline-first outbox. Mutations are appended to an encrypted queue and
/// replayed against the [ApiBackend] in FIFO order whenever connectivity
/// returns. Reads stay best-effort; only writes are queued.
class SyncEngine {
  final ApiBackend backend;
  final ConnectivityService connectivity;

  /// Notified after the operation of [type] on [visitId] is applied
  /// server-side, so the service layer can refresh that visit (and, for an
  /// upload, tell the clinician it reached the scribe). [payload] carries the
  /// op's data — notably `audioPath`, so the caller can mark exactly which
  /// local recording the server has now accepted.
  void Function(String visitId, SyncOpType type, Map<String, dynamic> payload)?
      onOpApplied;

  /// Notified when an op is permanently given up on (4xx or out of retries), so
  /// the service layer can surface the failure (e.g. mark the visit failed)
  /// instead of pretending it succeeded.
  void Function(String visitId, SyncOpType type)? onOpFailed;

  /// Notified when a locally-created (offline) visit is replaced by the real
  /// server visit created at flush time, so the UI can re-key its local copy.
  void Function(String localId, String realId)? onVisitRemapped;

  static const _secure = SecureStore();
  static const _queueKey = 'sync_outbox';
  static const _maxAttempts = 8;

  final List<SyncOp> _queue = [];
  bool _flushing = false;

  /// Pending operation count (surfaced in the UI as a sync badge).
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  /// True while an audio upload for [audioPath] is still waiting in the queue.
  /// Lets a recovery scan tell "never uploaded" apart from "already queued",
  /// so it can't enqueue a second copy of a file that is about to go up.
  bool hasPendingUpload(String audioPath) => _queue.any((o) =>
      o.type == SyncOpType.uploadAudio && o.payload['audioPath'] == audioPath);

  SyncEngine({required this.backend, required this.connectivity});

  Future<void> init() async {
    await _restore();
    connectivity.onReconnected = flush;
    // Always try to drain the queue at startup — there may be ops left from a
    // previous session, and the connectivity flag can't be trusted (see below).
    flush();
  }

  /// Queue a mutation and try to apply it immediately.
  ///
  /// Returns true if the op reached the server before returning (so the caller
  /// can show real success rather than an optimistic guess).
  ///
  /// We do NOT gate this on [ConnectivityService.online]: that flag is only a
  /// hint and is wrong on some platforms — notably the iOS Simulator, where
  /// `connectivity_plus` reports "none" while the network works perfectly. So
  /// we always attempt; if the network really is down the attempt fails quickly
  /// and the op stays queued for the next flush (reconnect event or backoff).
  Future<bool> enqueue(SyncOp op) async {
    _queue.add(op);
    await _persist();
    await flush();
    // Applied iff it's no longer waiting in the queue.
    return !_queue.any((o) => o.id == op.id);
  }

  /// Replay the queue in order. Stops at the first network failure (keeping
  /// FIFO order) and schedules a backed-off retry. A recording is only ever
  /// dropped on a permanent (4xx) error or a repeated non-network server error
  /// — never just because the device was offline.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        try {
          await _apply(op);
          _queue.removeAt(0);
          await _persist();
          AppLog.log('SYNC', 'op ${op.type.name} visit=${op.visitId} OK');
          onOpApplied?.call(op.visitId, op.type, op.payload);
        } catch (e) {
          op.attempts++;
          AppLog.log('SYNC',
              'op ${op.type.name} visit=${op.visitId} FAIL #${op.attempts}: $e');
          final permanent = _isPermanent(e);
          // A persistent *server* error (e.g. repeated 5xx) shouldn't block the
          // queue forever; give up after the cap. Pure network/offline errors
          // are retried indefinitely so offline recordings are never lost.
          final exhausted = !_isNetwork(e) && op.attempts >= _maxAttempts;
          if (permanent || exhausted) {
            _queue.removeAt(0);
            await _persist();
            onOpFailed?.call(op.visitId, op.type);
            continue; // let the rest of the queue proceed
          }
          // Transient: keep the op, persist progress, stop to preserve order,
          // and schedule a backed-off retry (capped) regardless of the
          // connectivity flag. Reconnect also triggers a flush.
          await _persist();
          final delay = Duration(seconds: (6 * op.attempts).clamp(6, 300));
          Future.delayed(delay, flush);
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _apply(SyncOp op) async {
    switch (op.type) {
      case SyncOpType.uploadAudio:
        var targetId = op.visitId;
        // A local (offline-synthesized) visit has no server row yet. Create it
        // first — once — so the audio attaches to a real visit the web app can
        // see. The real id is remembered in the payload so a retry never creates
        // a duplicate visit.
        if (targetId.startsWith('local_')) {
          var real = op.payload['realVisitId'] as String?;
          if (real == null) {
            AppLog.log('SYNC', 'creating server visit for local ${op.visitId}');
            final created = await backend.createVisit(
              patientId: (op.payload['patientId'] as num?)?.toInt() ?? 0,
              patientName: op.payload['patientName'] as String? ?? 'Patient',
            );
            real = created.id;
            op.payload['realVisitId'] = real;
            await _persist();
            onVisitRemapped?.call(op.visitId, real);
          }
          targetId = real;
        }
        AppLog.log('SYNC', 'apply uploadAudio visit=$targetId');
        await backend.uploadAudio(
            visitId: targetId, audioPath: op.payload['audioPath'] as String);
      case SyncOpType.editNote:
        await backend.saveNoteEdit(
            visitId: op.visitId, content: op.payload['content'] as String);
      case SyncOpType.requestChanges:
        await backend.requestChanges(
            visitId: op.visitId, comment: op.payload['comment'] as String);
      case SyncOpType.approveNote:
        await backend.approveNote(op.visitId);
    }
  }

  /// 4xx-class errors won't fix themselves on retry; network errors will.
  bool _isPermanent(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('400') ||
        s.contains('403') ||
        s.contains('404') ||
        s.contains('422');
  }

  /// True for *temporary* failures that will clear on their own — connectivity
  /// issues (offline / DNS / timeout) AND rate-limiting (429). These are retried
  /// indefinitely (with backoff) so a queued recording is never dropped just
  /// because the device was offline or the server briefly throttled us.
  bool _isNetwork(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('connection') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('socket') ||
        s.contains('unreachable') ||
        s.contains('failed host lookup') ||
        s.contains('no connection') ||
        s.contains("couldn't reach") ||
        s.contains('429') ||
        s.contains('too many requests') ||
        s.contains('rate') ||
        // Gateway / origin-down errors (CloudFront → backend). Temporary:
        // keep the recording queued and retry until the server recovers.
        s.contains('gateway') ||
        s.contains('unreachable') ||
        s.contains('502') ||
        s.contains('503') ||
        s.contains('504') ||
        s.contains('server error');
  }

  Future<void> _restore() async {
    final raw = await _secure.read(key: _queueKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _queue
        ..clear()
        ..addAll(list.map(SyncOp.fromJson));
      pending.value = _queue.length;
    } catch (_) {
      // Corrupt queue — discard rather than crash on launch.
      await _secure.delete(key: _queueKey);
    }
  }

  Future<void> _persist() async {
    pending.value = _queue.length;
    await _secure.write(
        key: _queueKey, value: jsonEncode(_queue.map((o) => o.toJson()).toList()));
  }
}
