/// Domain models for the clinician note-review workflow.
///
/// Flow (clinician-only, per product spec):
///   record -> audio uploads -> note is generated -> clinician reviews ->
///   (optional) request edit + feedback -> note regenerated -> review again ->
///   approve as final -> a scribe later uploads the final note to the EHR.
///
/// The clinician app NEVER exposes a raw "generate transcript" action and never
/// performs the EHR upload itself — that is the scribe's step.
library;

/// Lifecycle of a visit + its note, from the clinician's point of view.
///
/// The note is authored by a **scribe**, not the app. The clinician records,
/// the scribe completes the note, then the clinician reviews/edits/approves.
enum VisitStatus {
  /// Audio is being captured on-device.
  recording,

  /// Audio captured, queued to upload (offline) or uploading now.
  pendingUpload,

  /// Audio submitted; a scribe is completing the note.
  withScribe,

  /// Scribe finished the note; waiting for the clinician to review.
  readyForReview,

  /// Clinician sent comments back to the scribe for changes.
  changesRequested,

  /// Clinician approved the note as final.
  approved,

  /// Scribe has pushed the final note to the EHR (terminal).
  syncedToEhr,

  /// Something failed (upload). Retryable.
  failed,
}

extension VisitStatusX on VisitStatus {
  String get label => switch (this) {
        VisitStatus.recording => 'Recording',
        VisitStatus.pendingUpload => 'Pending upload',
        VisitStatus.withScribe => 'With scribe',
        VisitStatus.readyForReview => 'Ready for review',
        VisitStatus.changesRequested => 'Changes requested',
        VisitStatus.approved => 'Approved',
        VisitStatus.syncedToEhr => 'In EHR',
        VisitStatus.failed => 'Needs attention',
      };

  /// Wire value used by the live backend (best-effort; parsing is defensive).
  String get wire => name;

  static VisitStatus parse(Object? v) {
    final s = v?.toString().toLowerCase().replaceAll(RegExp(r'[ _-]'), '');
    return switch (s) {
      'recording' => VisitStatus.recording,
      'pendingupload' || 'queued' => VisitStatus.pendingUpload,
      'withscribe' || 'scribe' || 'processing' || 'transcribing' ||
            'generating' || 'drafting' =>
        VisitStatus.withScribe,
      'readyforreview' || 'draft' || 'review' || 'ready' || 'completed' =>
        VisitStatus.readyForReview,
      'changesrequested' || 'editrequested' || 'revising' || 'revision' =>
        VisitStatus.changesRequested,
      'approved' || 'final' || 'locked' => VisitStatus.approved,
      'syncedtoehr' || 'synced' || 'ehr' || 'uploaded' =>
        VisitStatus.syncedToEhr,
      'failed' || 'error' => VisitStatus.failed,
      _ => VisitStatus.readyForReview,
    };
  }
}

/// A clinical visit: a patient encounter that produces one clinical note.
class Visit {
  final String id;
  final int patientId;
  final String patientName;
  final VisitStatus status;
  final int durationMs;
  final int createdAt; // epoch millis
  final String? localAudioPath; // present until uploaded
  final ClinicalNote? note;
  final String visitType; // 'New Patient' | 'Follow-up' | ... ('' if unknown)
  final int visitDate; // scheduled visit date/time, epoch millis (0 if unknown)
  // How many recordings the SERVER holds for this visit (a visit can hold
  // several — the server keeps them as a comma-separated audio_file list). 0
  // when unknown / none. Drives the "N recordings" count so a patient recorded
  // multiple times reads correctly even though it's a single visit.
  final int recordingCount;

  const Visit({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.status,
    required this.durationMs,
    required this.createdAt,
    this.localAudioPath,
    this.note,
    this.visitType = '',
    this.visitDate = 0,
    this.recordingCount = 0,
  });

  Visit copyWith({
    VisitStatus? status,
    int? durationMs,
    String? localAudioPath,
    bool clearLocalAudio = false,
    ClinicalNote? note,
    String? visitType,
    int? visitDate,
    int? recordingCount,
  }) =>
      Visit(
        id: id,
        patientId: patientId,
        patientName: patientName,
        status: status ?? this.status,
        durationMs: durationMs ?? this.durationMs,
        createdAt: createdAt,
        localAudioPath:
            clearLocalAudio ? null : (localAudioPath ?? this.localAudioPath),
        note: note ?? this.note,
        visitType: visitType ?? this.visitType,
        visitDate: visitDate ?? this.visitDate,
        recordingCount: recordingCount ?? this.recordingCount,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'patientId': patientId,
        'patientName': patientName,
        'status': status.wire,
        'durationMs': durationMs,
        'createdAt': createdAt,
        if (localAudioPath != null) 'localAudioPath': localAudioPath,
        if (note != null) 'note': note!.toJson(),
        'recordingCount': recordingCount,
      };

  /// Defensive parser for live-API visit objects (field names vary).
  factory Visit.fromJson(Map<String, dynamic> m, {String? patientNameHint}) {
    String? str(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null) return v.toString();
      }
      return null;
    }

    int intOf(List<String> keys, [int fallback = 0]) {
      for (final k in keys) {
        final v = m[k];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) {
          final p = int.tryParse(v);
          if (p != null) return p;
        }
      }
      return fallback;
    }

    final createdRaw = str(['createdAt', 'created_at', 'created', 'date']);
    final created = _parseMillis(createdRaw);
    final noteJson = m['note'] ?? m['clinicalNote'] ?? m['noteData'];

    return Visit(
      id: str(['id', '_id', 'visitId', 'visit_id']) ?? '',
      patientId: intOf(['patientId', 'patient_id']),
      patientName: str(['patientName', 'patient_name', 'patient']) ??
          patientNameHint ??
          'Patient',
      status: VisitStatusX.parse(m['status'] ?? m['state']),
      durationMs: intOf(['durationMs', 'duration_ms', 'duration']),
      createdAt: created,
      localAudioPath: str(['localAudioPath']),
      note: noteJson is Map
          ? ClinicalNote.fromJson(noteJson.cast<String, dynamic>())
          : null,
      visitType: str(['visitType', 'visit_type', 'type']) ?? '',
      visitDate: _parseVisitDate(
          str(['visitDate', 'visit_date', 'scheduledDate']),
          str(['visitTime', 'visit_time', 'scheduledTime'])),
      recordingCount: intOf(['recordingCount']),
    );
  }

  factory Visit.fromMap(Map<String, Object?> m) =>
      Visit.fromJson(m.cast<String, dynamic>());
}

/// A piece of clinician feedback during the review cycle.
class NoteFeedback {
  final String message;
  final int at; // epoch millis
  const NoteFeedback(this.message, this.at);

  Map<String, Object?> toJson() => {'message': message, 'at': at};
  factory NoteFeedback.fromJson(Map<String, dynamic> m) => NoteFeedback(
        (m['message'] ?? m['text'] ?? '').toString(),
        _parseMillis(m['at']?.toString() ?? m['createdAt']?.toString()),
      );
}

/// The generated clinical note (SOAP) under review.
class ClinicalNote {
  final String id;
  final String visitId;
  final String content; // the rendered note (markdown-ish plain text)
  final int version; // increments each regeneration
  final List<NoteFeedback> feedback;
  final int updatedAt;

  const ClinicalNote({
    required this.id,
    required this.visitId,
    required this.content,
    this.version = 1,
    this.feedback = const [],
    required this.updatedAt,
  });

  ClinicalNote copyWith({
    String? content,
    int? version,
    List<NoteFeedback>? feedback,
    int? updatedAt,
  }) =>
      ClinicalNote(
        id: id,
        visitId: visitId,
        content: content ?? this.content,
        version: version ?? this.version,
        feedback: feedback ?? this.feedback,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'visitId': visitId,
        'content': content,
        'version': version,
        'feedback': feedback.map((f) => f.toJson()).toList(),
        'updatedAt': updatedAt,
      };

  factory ClinicalNote.fromJson(Map<String, dynamic> m) {
    final fb = m['feedback'] ?? m['feedbackHistory'] ?? m['revisions'];
    return ClinicalNote(
      id: (m['id'] ?? m['_id'] ?? m['noteId'] ?? '').toString(),
      visitId: (m['visitId'] ?? m['visit_id'] ?? '').toString(),
      content:
          (m['content'] ?? m['note'] ?? m['text'] ?? m['body'] ?? '').toString(),
      version: (m['version'] is num) ? (m['version'] as num).toInt() : 1,
      feedback: fb is List
          ? fb
              .whereType<Map>()
              .map((e) => NoteFeedback.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      updatedAt: _parseMillis(
          m['updatedAt']?.toString() ?? m['updated_at']?.toString()),
    );
  }
}

/// Combines a 'YYYY-MM-DD' date with an optional 'HH:mm' time into epoch millis.
/// Returns 0 when there is no usable date.
int _parseVisitDate(String? date, String? time) {
  if (date == null || date.isEmpty || date == 'null') return 0;
  final d = date.length >= 10 ? date.substring(0, 10) : date;
  final t = (time != null && time.isNotEmpty && time != 'null')
      ? (time.length >= 5 ? time.substring(0, 5) : time)
      : '00:00';
  final dt = DateTime.tryParse('${d}T$t');
  return dt?.millisecondsSinceEpoch ?? 0;
}

/// Accepts epoch millis, epoch seconds, or ISO-8601; falls back to now.
int _parseMillis(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now().millisecondsSinceEpoch;
  final asInt = int.tryParse(raw);
  if (asInt != null) {
    // Heuristic: < 10^12 looks like seconds.
    return asInt < 1000000000000 ? asInt * 1000 : asInt;
  }
  final dt = DateTime.tryParse(raw);
  return (dt ?? DateTime.now()).millisecondsSinceEpoch;
}
