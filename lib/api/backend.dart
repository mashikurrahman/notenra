import 'clinical_models.dart';

/// The clinician-workflow backend contract.
///
/// Two implementations live behind this interface:
///   * [MockBackend]  — local, fully offline demo data (default until a live
///     server URL + credentials are configured).
///   * LiveBackend    — wired to the documented Notenra REST API.
///
/// Swapping between them is a one-line change in the service layer, so building
/// against the mock now requires zero rework when the live API is connected.
abstract class ApiBackend {
  /// Human label shown in Settings ("Demo data" / "Live server").
  String get label;

  /// Whether this backend reaches a real remote server.
  bool get isLive;

  /// Visits assigned to the signed-in clinician (review queue + history).
  Future<List<Visit>> myVisits();

  /// Create a visit shell for a patient before/at the start of recording.
  Future<Visit> createVisit({required int patientId, required String patientName});

  /// Upload the captured audio for [visitId]; moves the visit into [processing].
  Future<Visit> uploadAudio({required String visitId, required String audioPath});

  /// Poll/fetch the latest state of a single visit (note may now be ready).
  Future<Visit> getVisit(String visitId);

  /// Clinician saves their own small inline edits to the note text.
  Future<Visit> saveNoteEdit({required String visitId, required String content});

  /// Clinician sends comments back to the scribe requesting changes.
  Future<Visit> requestChanges({required String visitId, required String comment});

  /// Clinician approves the current note as final.
  Future<Visit> approveNote(String visitId);

  /// Move an un-recorded visit to a new date. The backend's PUT /visits only
  /// changes time/type, so "move" = create the visit on [visitDate] and delete
  /// the old one ([oldVisitId]). Returns the newly-created visit.
  Future<Visit> rescheduleVisit({
    required String oldVisitId,
    required int patientId,
    required String patientName,
    required String visitDate, // YYYY-MM-DD
    required String visitTime, // HH:mm (24h)
    required String visitType,
  });
}
