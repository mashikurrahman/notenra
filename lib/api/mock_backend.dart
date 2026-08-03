import 'dart:async';
import 'dart:math';

import 'backend.dart';
import 'clinical_models.dart';

/// In-memory demo backend. Simulates the full clinician workflow with a
/// **scribe** authoring the note: audio is submitted, a scribe completes the
/// note (after a short delay), the clinician reviews / edits / requests changes
/// / approves. Appointments persist to the local encrypted DB so the demo
/// survives restarts. No live server required.
class MockBackend implements ApiBackend {
  @override
  String get label => 'Demo data';
  @override
  bool get isLive => false;

  final _rng = Random();
  final Map<String, Visit> _visits = {};

  @override
  Future<List<Visit>> myVisits() async {
    await _latency();
    final list = _visits.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<Visit> createVisit(
      {required int patientId, required String patientName}) async {
    await _latency();
    final id = 'v${DateTime.now().millisecondsSinceEpoch}';
    final v = Visit(
      id: id,
      patientId: patientId,
      patientName: patientName,
      status: VisitStatus.recording,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _visits[id] = v;
    return v;
  }

  @override
  Future<Visit> uploadAudio(
      {required String visitId, required String audioPath}) async {
    await _latency(extraMs: 400);
    var v = _visits[visitId];
    v ??= Visit(
      id: visitId,
      patientId: 0,
      patientName: 'Patient',
      status: VisitStatus.withScribe,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    v = v.copyWith(status: VisitStatus.withScribe, clearLocalAudio: true);
    _visits[visitId] = v;
    // The note is authored by a real scribe (scribe portal) — NOT fabricated.
    // The visit simply waits in "With scribe" until a scribe submits a note.
    return v;
  }

  @override
  Future<Visit> getVisit(String visitId) async {
    await _latency();
    final v = _visits[visitId];
    if (v == null) throw StateError('Visit $visitId not found');
    return v;
  }

  @override
  Future<Visit> saveNoteEdit(
      {required String visitId, required String content}) async {
    await _latency();
    final v = _visits[visitId];
    if (v == null) throw StateError('Visit $visitId not found');
    if (v.note == null) return v; // nothing to edit until a scribe submits
    final note = v.note!.copyWith(
      content: content,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    // Doctor's own edit keeps the note in review (no scribe round-trip).
    _visits[visitId] = v.copyWith(status: VisitStatus.readyForReview, note: note);
    return _visits[visitId]!;
  }

  @override
  Future<Visit> requestChanges(
      {required String visitId, required String comment}) async {
    await _latency();
    final v = _visits[visitId];
    if (v == null) throw StateError('Visit $visitId not found');
    final history = [
      ...?v.note?.feedback,
      NoteFeedback(comment, DateTime.now().millisecondsSinceEpoch),
    ];
    // Send back to the scribe with the doctor's comments; a real scribe revises
    // and re-submits via the scribe portal (no auto-generated revision).
    _visits[visitId] = v.copyWith(
        status: VisitStatus.changesRequested,
        note: v.note?.copyWith(feedback: history));
    return _visits[visitId]!;
  }

  @override
  Future<Visit> approveNote(String visitId) async {
    await _latency();
    final v = _visits[visitId];
    if (v == null) throw StateError('Visit $visitId not found');
    _visits[visitId] = v.copyWith(status: VisitStatus.approved);
    return _visits[visitId]!;
  }

  @override
  Future<Visit> rescheduleVisit({
    required String oldVisitId,
    required int patientId,
    required String patientName,
    required String visitDate,
    required String visitTime,
    required String visitType,
  }) async {
    await _latency();
    final dt = DateTime.tryParse(
            '${visitDate}T${visitTime.isEmpty ? '09:00' : visitTime}') ??
        DateTime.now();
    final millis = dt.millisecondsSinceEpoch;
    final id = 'v${DateTime.now().millisecondsSinceEpoch}';
    final v = Visit(
      id: id,
      patientId: patientId,
      patientName: patientName,
      status: VisitStatus.pendingUpload, // an un-recorded scheduled shell
      durationMs: 0,
      createdAt: millis,
      visitType: visitType,
      visitDate: millis,
    );
    _visits[id] = v;
    _visits.remove(oldVisitId);
    return v;
  }

  // --- helpers ---
  // No fabricated notes: a visit only exists once the doctor records, and a
  // note only exists once a real scribe submits one via the scribe portal.

  Future<void> _latency({int extraMs = 0}) =>
      Future.delayed(Duration(milliseconds: 150 + _rng.nextInt(250) + extraMs));
}
