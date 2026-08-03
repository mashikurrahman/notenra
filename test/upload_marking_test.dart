import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/api/backend.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';

/// Accepts uploads and reports the visit back as "with scribe", like the real
/// server does once audio is attached.
class _AcceptingBackend implements ApiBackend {
  final List<String> uploaded = [];
  final Map<String, Visit> _visits = {};

  @override
  String get label => 'Fake';
  @override
  bool get isLive => true;

  @override
  Future<List<Visit>> myVisits() async => _visits.values.toList();

  @override
  Future<Visit> getVisit(String visitId) async =>
      _visits[visitId] ?? (throw StateError('no visit $visitId'));

  @override
  Future<Visit> createVisit(
      {required int patientId, required String patientName}) async {
    final v = Visit(
      id: 'srv_${_visits.length + 1}',
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
    uploaded.add(audioPath);
    final v = _visits[visitId]!.copyWith(status: VisitStatus.withScribe);
    _visits[visitId] = v;
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

  /// Regression: a recording whose upload was confirmed by the outbox used to
  /// leave its local row marked "pending", because only an inline upload
  /// reported success. Every later sign-in then re-sent the same file, and the
  /// server appends audio rather than replacing it — so one recording showed up
  /// as two, three, four audio cards on the visit.
  test('a confirmed upload reports its audio path back exactly once', () async {
    final backend = _AcceptingBackend();
    final svc = ClinicalService(
      connectivity: ConnectivityService(),
      tokens: TokenStore(),
      backend: backend,
    );
    addTearDown(svc.dispose);

    final marked = <String>[];
    svc.onAudioUploaded = marked.add;

    await svc.init();
    await svc.submitRecording(
      patientId: 7,
      patientName: 'Test Patient',
      audioPath: '/tmp/visit_audio.m4a.enc',
      durationMs: 4000,
    );

    expect(backend.uploaded, ['/tmp/visit_audio.m4a.enc'],
        reason: 'the file should reach the server exactly once');
    expect(marked, ['/tmp/visit_audio.m4a.enc'],
        reason: 'the local recording row must be told the server has it, '
            'otherwise a later sign-in re-uploads and duplicates it');
  });

  test('a drained queue reports nothing still pending for that file', () async {
    final backend = _AcceptingBackend();
    final svc = ClinicalService(
      connectivity: ConnectivityService(),
      tokens: TokenStore(),
      backend: backend,
    );
    addTearDown(svc.dispose);

    await svc.init();
    const path = '/tmp/another.m4a.enc';
    await svc.submitRecording(
      patientId: 9,
      patientName: 'Second Patient',
      audioPath: path,
      durationMs: 2000,
    );

    // Once applied, the recovery scan must see nothing queued for this file —
    // and, because it was marked uploaded, must not re-submit it either.
    expect(svc.isUploadQueued(path), isFalse);
  });
}
