import 'package:flutter_test/flutter_test.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/api/mock_backend.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';
import 'package:notenra/status_ui.dart';

void main() {
  group('MockBackend AI Note Generation', () {
    late MockBackend backend;

    setUp(() {
      backend = MockBackend();
    });

    test('uploadAudio generates structured SOAP note with medical codes (ICD-10 & CPT)', () async {
      final visit = await backend.createVisit(patientId: 101, patientName: 'Dr. John Doe');
      expect(visit.status, VisitStatus.pendingUpload);

      final uploaded = await backend.uploadAudio(visitId: visit.id, audioPath: '/path/1.m4a');
      expect(uploaded.status, VisitStatus.readyForReview);
      expect(uploaded.recordingCount, 1);
      expect(uploaded.note, isNotNull);
      expect(uploaded.note!.content, contains('SUBJECTIVE:'));
      expect(uploaded.note!.content, contains('OBJECTIVE:'));
      expect(uploaded.note!.content, contains('ASSESSMENT:'));
      expect(uploaded.note!.content, contains('PLAN:'));
      // Medical coding verification
      expect(uploaded.note!.content, contains('MEDICAL CODES & BILLING:'));
      expect(uploaded.note!.content, contains('ICD-10-CM Diagnosis Codes:'));
      expect(uploaded.note!.content, contains('I10'));
      expect(uploaded.note!.content, contains('CPT / E&M Procedure Codes:'));
      expect(uploaded.note!.content, contains('99214'));
    });

    test('uploadAudio appends addendum and coding updates when multiple recordings exist', () async {
      final visit = await backend.createVisit(patientId: 102, patientName: 'Jane Smith');
      await backend.uploadAudio(visitId: visit.id, audioPath: '/path/1.m4a');

      // Second recording for same visit
      final secondUpload = await backend.uploadAudio(visitId: visit.id, audioPath: '/path/2.m4a');
      expect(secondUpload.recordingCount, 2);
      expect(secondUpload.note, isNotNull);
      expect(secondUpload.note!.content, contains('Addendum (from recording #2)'));
      expect(secondUpload.note!.content, contains('Z91.19'));
    });
  });

  group('ClinicalService Visit Reuse & Note Flow', () {
    late MockBackend backend;
    late ClinicalService service;

    setUp(() async {
      backend = MockBackend();
      service = ClinicalService(
        connectivity: ConnectivityService(),
        tokens: TokenStore(),
        backend: backend,
      );
      await service.init();
    });

    test('submitRecording reuses existing visit and attaches multiple recordings to one visit', () async {
      // First recording
      final v1 = await service.submitRecording(
        patientId: 201,
        patientName: 'Test Patient',
        audioPath: '/local/rec1.m4a',
        durationMs: 5000,
      );
      expect(v1, isNotNull);
      final initialVisitId = v1!.id;

      // Second recording for same patient
      final v2 = await service.submitRecording(
        patientId: 201,
        patientName: 'Test Patient',
        audioPath: '/local/rec2.m4a',
        durationMs: 3000,
      );
      expect(v2, isNotNull);
      expect(v2!.id, initialVisitId, reason: 'Must reuse the same visit ID for the patient encounter');

      // Flush outbox to trigger upload and note generation
      await service.flushOutboxForTest();

      final reloaded = service.visitById(initialVisitId);
      expect(reloaded, isNotNull);
      expect(service.patientRecorded(201), isTrue);
    });
  });

  group('Status Presentation & UI Styles', () {
    test('styleFor returns Recorded and Ready for review instead of active recording for finished visits', () {
      final sReady = styleFor(VisitStatus.readyForReview);
      expect(sReady.label, 'Ready for you');
      expect(sReady.detail, 'AI Note ready to review');

      final sRecorded = styleFor(VisitStatus.recording);
      expect(sRecorded.label, 'Recorded');
      expect(sRecorded.detail, 'Recording saved');

      final sQueued = styleFor(VisitStatus.pendingUpload);
      expect(sQueued.label, 'Queued');

      final sProcessing = styleFor(VisitStatus.withScribe);
      expect(sProcessing.label, 'Processing');
      expect(sProcessing.detail, 'AI generating note…');
    });
  });
}
