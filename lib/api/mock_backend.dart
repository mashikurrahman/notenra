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
      status: VisitStatus.pendingUpload,
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
      status: VisitStatus.pendingUpload,
      durationMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final count = v.recordingCount + 1;
    final noteContent = _buildAiSoapNote(v.patientName, count);
    final note = ClinicalNote(
      id: 'note_$visitId',
      visitId: visitId,
      content: noteContent,
      version: (v.note?.version ?? 0) + 1,
      feedback: v.note?.feedback ?? const [],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    v = v.copyWith(
      status: VisitStatus.readyForReview,
      clearLocalAudio: true,
      recordingCount: count,
      note: note,
    );
    _visits[visitId] = v;
    return v;
  }

  String _buildAiSoapNote(String patientName, int recordingCount) {
    final addendum = recordingCount > 1
        ? '\n\n*Addendum (from recording #$recordingCount):* Patient confirmed adherence to medication regimen and reported no adverse side effects.'
        : '';
    final addendumAssessment = recordingCount > 1
        ? '\n4. Medication compliance review (ICD-10: Z91.19) - Active regimen verified.'
        : '';
    final addendumCode = recordingCount > 1
        ? '\n• Z91.19 - Patient noncompliance with other medical treatment and regimen (monitoring/history)'
        : '';

    return '''SUBJECTIVE:
Chief Complaint: General clinical follow-up and health evaluation.
History of Present Illness: Patient $patientName presents for clinical evaluation. Reports ongoing symptoms with moderate severity, responding well to current interventions. Denies fever, chills, acute chest discomfort, or respiratory distress. Sleep and appetite reported within normal baseline.$addendum

OBJECTIVE:
General: Alert, oriented x3, well-nourished, in no acute distress.
Vital Signs: BP 122/78 mmHg, HR 72 bpm, SpO2 99% on room air, Temp 98.4 F, RR 16/min.
HEENT: Normocephalic, atraumatic. Pupils equal, round, and reactive to light.
Cardiovascular: Regular rate and rhythm, normal S1/S2, no murmurs or gallops.
Pulmonary: Clear to auscultation bilaterally, no wheezes or rales.
Abdomen: Soft, non-tender, non-distended, normoactive bowel sounds.

ASSESSMENT:
1. Essential (primary) hypertension (ICD-10: I10) - Stable, well-controlled on current therapy.
2. Encounter for general adult medical examination without abnormal findings (ICD-10: Z00.00).
3. Routine health maintenance and counseling (ICD-10: Z71.89) - Addressed dietary sodium and cardiovascular wellness.$addendumAssessment

PLAN:
1. Continue current antihypertensive regimen as tolerated.
2. Maintain regular home blood pressure monitoring logs (target < 130/80 mmHg).
3. Routine preventive laboratory orders: CMP, Lipid Profile, and Urinalysis.
4. Patient counselled regarding low-sodium lifestyle and cardiovascular risk reduction.
5. Follow up in 3 months or sooner if symptoms arise.

MEDICAL CODES & BILLING:
ICD-10-CM Diagnosis Codes:
• I10 - Essential (primary) hypertension
• Z00.00 - Encounter for general adult medical examination without abnormal findings
• Z71.89 - Other specified counseling$addendumCode

CPT / E&M Procedure Codes:
• 99214 - Office or other outpatient visit, established patient (30-39 minutes, moderate complexity MDM)
• 99401 - Preventive medicine counseling and/or risk factor reduction intervention (15 minutes)''';
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
