import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/api/backend.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';

/// Reproduces the real failure behind visit 605: the server ACCEPTS and stores
/// the audio, but the client sees an error (a receive timeout on a long
/// recording, or a 2xx body it can't confirm). The outbox then retries. Because
/// the server appends to a comma-separated audio list rather than replacing,
/// each blind retry produced another audio card in the web app.
class _AcceptsThenReportsFailure implements ApiBackend {
  int storedFiles = 0;
  int uploadCalls = 0;
  int getVisitCalls = 0;
  final Map<String, Visit> _visits = {};

  @override
  String get label => 'Fake';
  @override
  bool get isLive => true;

  @override
  Future<List<Visit>> myVisits() async => _visits.values.toList();

  @override
  Future<Visit> getVisit(String visitId) async {
    getVisitCalls++;
    final v = _visits[visitId];
    if (v == null) throw StateError('no visit $visitId');
    // The visit reports however many files the server actually holds.
    return v.copyWith(recordingCount: storedFiles);
  }

  @override
  Future<Visit> createVisit(
      {required int patientId, required String patientName}) async {
    final v = Visit(
      id: 'srv_1',
      patientId: patientId,
      patientName: patientName,
      status: VisitStatus.pendingUpload,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _visits[v.id] = v;
    return v;
  }

  @override
  Future<Visit> uploadAudio(
      {required String visitId, required String audioPath}) async {
    uploadCalls++;
    // The file IS stored server-side...
    storedFiles++;
    // ...but the client is told it failed, exactly as a receive timeout or an
    // unconfirmable 2xx would.
    throw StateError('Upload not confirmed — connection timed out. Will retry.');
  }

  @override
  Future<Visit> saveNoteEdit(
          {required String visitId, required String content}) =>
      throw UnimplementedError();
  @override
  Future<Visit> requestChanges(
          {required String visitId, required String comment}) =>
      throw UnimplementedError();
  @override
  Future<Visit> approveNote(String visitId) => throw UnimplementedError();
  @override
  Future<Visit> rescheduleVisit({
    required String oldVisitId,
    required int patientId,
    required String patientName,
    required String visitDate,
    required String visitTime,
    required String visitType,
  }) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an upload the server accepted is not sent a second time', () async {
    final backend = _AcceptsThenReportsFailure();
    final svc = ClinicalService(
      connectivity: ConnectivityService(),
      tokens: TokenStore(),
      backend: backend,
    );
    addTearDown(svc.dispose);

    await svc.init();
    await svc.submitRecording(
      patientId: 7,
      patientName: 'Liam Costa',
      audioPath: '/tmp/one_recording.m4a.enc',
      durationMs: 300000,
    );

    // The first attempt stored the file and then reported failure, so the op
    // stays queued for a backed-off retry.
    expect(backend.uploadCalls, 1, reason: 'exactly one POST so far');
    expect(backend.storedFiles, 1, reason: 'the server holds one file');
    expect(svc.isUploadQueued('/tmp/one_recording.m4a.enc'), isTrue,
        reason: 'still queued — the client believes it failed');

    // Drive the retry directly rather than waiting out the backoff timer.
    await svc.flushOutboxForTest();

    expect(backend.storedFiles, 1,
        reason: 'the retry must NOT append a second copy — this is the bug '
            'that showed one recording as three cards in the web app');
    expect(backend.uploadCalls, 1,
        reason: 'the retry should detect the file already landed and skip the '
            'upload entirely');
    expect(svc.isUploadQueued('/tmp/one_recording.m4a.enc'), isFalse,
        reason: 'op is resolved, so no further retries can duplicate it');
  });
}
