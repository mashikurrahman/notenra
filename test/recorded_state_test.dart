import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/api/backend.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';

/// A backend that simulates the real-world bounce bug: the upload succeeds, but
/// the server's visit list keeps reporting the visit as NOT-yet-recorded for a
/// while (no `audio_file`, status still pending) due to processing lag. Before
/// the fix this made a just-recorded patient jump back to "To see" / NEXT UP on
/// the next refresh.
class _LaggyBackend implements ApiBackend {
  _LaggyBackend(this.serverVisits);
  final List<Visit> serverVisits;

  @override
  String get label => 'Fake';
  @override
  bool get isLive => true;

  @override
  Future<List<Visit>> myVisits() async => List.of(serverVisits);

  @override
  Future<Visit> getVisit(String visitId) async =>
      serverVisits.firstWhere((v) => v.id == visitId);

  @override
  Future<Visit> uploadAudio(
      {required String visitId, required String audioPath}) async {
    // Server accepts the audio (2xx) but — simulating lag — does NOT yet reflect
    // it in the visit list. Return the still-pending server copy.
    return serverVisits.firstWhere((v) => v.id == visitId);
  }

  @override
  Future<Visit> createVisit(
      {required int patientId, required String patientName}) async {
    final v = Visit(
      id: 'srv_${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      patientName: patientName,
      status: VisitStatus.pendingUpload,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    serverVisits.add(v);
    return v;
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

  test('a recorded patient stays recorded across a refresh that lags', () async {
    // One scheduled, un-recorded visit for patient 7.
    final scheduled = Visit(
      id: 'v1',
      patientId: 7,
      patientName: 'Test Patient',
      status: VisitStatus.pendingUpload,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final backend = _LaggyBackend([scheduled]);
    final svc = ClinicalService(
      connectivity: ConnectivityService(), // online by default
      tokens: TokenStore(),
      backend: backend,
    );
    addTearDown(svc.dispose);

    await svc.init();
    expect(svc.patientRecorded(7), isFalse, reason: 'nothing recorded yet');

    // Doctor records the visit.
    await svc.submitRecording(
      patientId: 7,
      patientName: 'Test Patient',
      audioPath: '/tmp/fake_audio.m4a',
      durationMs: 3000,
    );
    expect(svc.patientRecorded(7), isTrue, reason: 'recorded right after submit');

    // Refresh — the server STILL reports the visit as not-yet-recorded (lag).
    await svc.refresh();
    expect(svc.patientRecorded(7), isTrue,
        reason: 'must NOT bounce back to To-see/NEXT UP after refresh');

    // And it counts as one recording for the badge.
    expect(svc.recordedCountForPatient(7), greaterThanOrEqualTo(1));
  });
}
