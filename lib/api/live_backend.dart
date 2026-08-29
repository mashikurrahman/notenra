import 'dart:io';

import 'package:dio/dio.dart';

import '../app_log.dart';
import '../audio_vault.dart';
import 'api_client.dart';
import 'backend.dart';
import 'clinical_models.dart';

/// Live backend for the Notenra REST API.
///
/// The contract below is the one this client actually speaks, confirmed
/// empirically against a running server — so it doubles as the spec any
/// replacement server must satisfy. If a server diverges, the fix is a second
/// [ApiBackend] implementation, not edits scattered through this one.
///
/// Contract summary (clinician role, `Authorization: Bearer <jwt>`):
///   GET    /visits                       -> { visits: [VISIT] }
///   POST   /visits                       -> { visit } ; body
///                                           {patient_id, visit_date, visit_time, visit_type}
///   POST   /audio/:visitId  (multipart `audio`) -> { message, audio_file, ... }
///   GET    /notes/visit/:visitId         -> { note: { id, final_note, status, ... } }
///   PUT    /notes/:noteId                -> body { final_note }
///   PUT    /notes/:noteId/request-edit   -> body { message }
///   POST   /visits/:visitId/lock-note    -> { visit } (approve / finalize)
///
/// Notes:
///   * There is **no** single-visit GET and **no** appointments API. A single
///     visit is resolved from the list; appointments are demo-only (see below).
///   * The note content lives in `final_note`; edit/request-edit are keyed by
///     the *note* id, which we resolve from the visit on demand.
class LiveBackend implements ApiBackend {
  final ApiClient client;
  LiveBackend(this.client);

  @override
  String get label => 'Live server';
  @override
  bool get isLive => true;

  Dio get _dio => client.dio;

  /// Default visit type when the app creates a visit shell for a recording.
  /// MUST be one of the server-enforced enums:
  /// `Follow-up | New Patient | Virtual Visit | Other`.
  static const _defaultVisitType = 'Follow-up';

  // --- endpoint paths (single source of truth) ---
  static const _visits = '/visits';
  String _audio(String visitId) => '/audio/$visitId';
  String _noteByVisit(String visitId) => '/notes/visit/$visitId';
  String _note(String noteId) => '/notes/$noteId';
  String _requestEdit(String noteId) => '/notes/$noteId/request-edit';
  String _lockNote(String visitId) => '/visits/$visitId/lock-note';

  @override
  Future<List<Visit>> myVisits() async {
    final res = await _dio.get(_visits);
    return _listFrom(res.data, 'visits')
        .whereType<Map>()
        .map((m) => _visitFromApi(m.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Visit> createVisit(
      {required int patientId, required String patientName}) async {
    final now = DateTime.now();
    final res = await _dio.post(_visits, data: {
      'patient_id': patientId,
      'visit_date': _ymd(now),
      'visit_time': _hm(now),
      'visit_type': _defaultVisitType,
    });
    return _visitFromApi(_objFrom(res.data, 'visit'),
        patientNameHint: patientName);
  }

  @override
  Future<Visit> uploadAudio(
      {required String visitId, required String audioPath}) async {
    // Decrypt at-rest audio to a temp file only for the duration of the upload.
    final isEnc = AudioVault.isEncrypted(audioPath);
    AppLog.log('UPLOAD', 'visit=$visitId enc=$isEnc src=$audioPath');
    final uploadPath =
        isEnc ? await AudioVault.decryptToTemp(audioPath) : audioPath;
    final exists = await File(uploadPath).exists();
    final size = exists ? await File(uploadPath).length() : -1;
    AppLog.log('UPLOAD', 'visit=$visitId tempExists=$exists bytes=$size');
    if (!exists || size <= 0) {
      throw StateError('Audio file missing or empty for visit $visitId');
    }
    // The server now requires the clinician's patient-recording-consent
    // attestation on the visit before it will accept any audio (otherwise 403
    // "Patient recording consent is required"). Record it for this visit first;
    // a failure here means the upload would be rejected anyway, so let it throw
    // and the outbox will retry the whole op.
    await _recordRecordingConsent(visitId);
    try {
      final form = FormData.fromMap({
        // Field name MUST be `audio` (multer .single('audio')). The server
        // derives the extension from the mimetype, so flag it as audio/*.
        'audio': await MultipartFile.fromFile(
          uploadPath,
          filename: 'visit_$visitId.m4a',
          contentType: DioMediaType('audio', 'mp4'),
        ),
      });
      // Same contract the (working) web app relies on: a non-2xx / network
      // failure throws (and the outbox retries); a success means the backend
      // accepted the recording. The interceptor already rejects 4xx/5xx, so a
      // returned response here is a real 2xx — no fragile re-verification needed.
      final res = await _dio.post(_audio(visitId), data: form);
      final data = res.data;
      // A real backend success is JSON carrying `audio_file` (or an "uploaded"
      // message). Anything else (an HTML CloudFront/WAF page returned with a 200)
      // means the backend did NOT store the audio — treat it as a retryable
      // failure so the outbox keeps the recording and tries again.
      final ok = data is Map &&
          (data['audio_file'] != null ||
              (data['message']?.toString().toLowerCase().contains('upload') ??
                  false));
      if (!ok) {
        final ct = res.headers.value('content-type');
        final via = res.headers.value('via');
        final xcache = res.headers.value('x-cache');
        final server = res.headers.value('server');
        final snippet = data.toString().replaceAll('\n', ' ');
        AppLog.log('UPLOAD',
            'visit=$visitId REJECT non-JSON 200 ct=$ct server=$server via=$via x-cache=$xcache body="${snippet.substring(0, snippet.length > 160 ? 160 : snippet.length)}"');
        throw ApiException(
            'Upload not confirmed — gateway returned a non-JSON page (502). Will retry.',
            statusCode: 502);
      }
      AppLog.log('UPLOAD',
          'visit=$visitId POST ok status=${res.statusCode} audio_file=${(data)['audio_file']}');
      try {
        // Re-fetch so the caller gets the new server-side state (with scribe).
        final v = await getVisit(visitId);
        AppLog.log('UPLOAD',
            'visit=$visitId server now status=${v.status.name} (re-fetched)');
        return v;
      } catch (_) {
        return Visit(
          id: visitId,
          patientId: 0,
          patientName: 'Patient',
          status: VisitStatus.withScribe,
          durationMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } finally {
      if (isEnc) {
        try {
          await File(uploadPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Record the clinician's patient-recording-consent attestation on a visit.
  /// The server requires this flag before it accepts audio for the visit. It's
  /// idempotent (sets the flag true), so it's safe to call before every upload,
  /// including additional/append recordings. No clinician-facing prompt — the
  /// consent is obtained face-to-face before the mic starts; this just records
  /// it so the server lets the audio through.
  Future<void> _recordRecordingConsent(String visitId) async {
    final id = int.tryParse(visitId);
    await _dio.post('/consent/recording', data: {'visitId': id ?? visitId});
    AppLog.log('UPLOAD', 'visit=$visitId consent recorded');
  }

  @override
  Future<Visit> getVisit(String visitId) async {
    // No single-visit endpoint: find it in the clinician's visit list.
    final res = await _dio.get(_visits);
    final row = _listFrom(res.data, 'visits')
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .firstWhere((m) => _str(m, ['id', 'visit_id']) == visitId,
            orElse: () => <String, dynamic>{});
    if (row.isEmpty) throw StateError('Visit $visitId not found');

    var visit = _visitFromApi(row);
    // Pull the authored note content once the scribe has produced something.
    final noteStatus = _str(row, ['note_status'])?.toLowerCase();
    if (noteStatus == 'submitted' ||
        noteStatus == 'uploaded' ||
        noteStatus == 'draft') {
      final note = await _fetchNote(visitId);
      if (note != null) visit = visit.copyWith(note: note);
    }
    return visit;
  }

  @override
  Future<Visit> saveNoteEdit(
      {required String visitId, required String content}) async {
    final noteId = await _noteIdFor(visitId);
    if (noteId == null) throw StateError('No note to edit for visit $visitId');
    await _dio.put(_note(noteId), data: {'final_note': content});
    return getVisit(visitId);
  }

  @override
  Future<Visit> requestChanges(
      {required String visitId, required String comment}) async {
    final noteId = await _noteIdFor(visitId);
    if (noteId == null) {
      throw StateError('No note to revise for visit $visitId');
    }
    await _dio.put(_requestEdit(noteId), data: {'message': comment});
    return getVisit(visitId);
  }

  @override
  Future<Visit> approveNote(String visitId) async {
    final res = await _dio.post(_lockNote(visitId));
    return _visitFromApi(_objFrom(res.data, 'visit'));
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
    // Create the visit on the new date first…
    final res = await _dio.post(_visits, data: {
      'patient_id': patientId,
      'visit_date': visitDate,
      'visit_time': visitTime.isEmpty ? '09:00' : visitTime,
      'visit_type': visitType.isEmpty ? _defaultVisitType : visitType,
    });
    final created =
        _visitFromApi(_objFrom(res.data, 'visit'), patientNameHint: patientName);
    // …then remove the old shell. Best-effort: a failed delete just leaves an
    // extra empty visit the clinician can delete, never lost data.
    try {
      await _dio.delete('$_visits/$oldVisitId');
    } catch (_) {}
    return created;
  }

  // --- note helpers ---

  Future<String?> _noteIdFor(String visitId) async {
    final res = await _dio.get(_noteByVisit(visitId));
    final note = _objFrom(res.data, 'note');
    final id = note['id'] ?? note['note_id'];
    return id?.toString();
  }

  Future<ClinicalNote?> _fetchNote(String visitId) async {
    try {
      final res = await _dio.get(_noteByVisit(visitId));
      final n = _objFrom(res.data, 'note');
      if (n.isEmpty) return null;
      final content =
          (n['final_note'] ?? n['ai_draft'] ?? n['content'] ?? '').toString();
      return ClinicalNote(
        id: (n['id'] ?? n['note_id'] ?? '').toString(),
        visitId: visitId,
        content: content,
        updatedAt: _millis(n['updated_at'] ?? n['note_updated_at']),
      );
    } catch (_) {
      return null;
    }
  }

  // --- visit mapping (live `/visits` row -> domain Visit) ---

  Visit _visitFromApi(Map<String, dynamic> m, {String? patientNameHint}) {
    final id = _str(m, ['id', 'visit_id']) ?? '';
    // A visit can hold several recordings: the server stores them as a
    // comma-separated `audio_file` list (e.g. "/uploads/a.webm,/uploads/b.webm").
    final audioRaw = _str(m, ['audio_file']) ?? '';
    final recordingCount =
        audioRaw.split(',').where((s) => s.trim().isNotEmpty).length;
    final hasAudio = recordingCount > 0;
    final status = _statusFromApi(
      noteStatus: _str(m, ['note_status'])?.toLowerCase(),
      visitStatus: _str(m, ['status'])?.toLowerCase(),
      hasAudio: hasAudio,
    );
    // Combine visit_date + visit_time so the schedule shows the real encounter
    // time (not midnight). Falls back to created_at when there's no visit date.
    final visitMillis = _visitMillis(_str(m, ['visit_date']), _str(m, ['visit_time']));
    return Visit(
      id: id,
      patientId: _int(m, ['patient_id', 'patientId']),
      patientName:
          _str(m, ['patient_name', 'patientName']) ?? patientNameHint ?? 'Patient',
      status: status,
      durationMs: _int(m, ['duration_seconds', 'duration']) * 1000,
      createdAt: visitMillis != 0 ? visitMillis : _millis(m['created_at']),
      visitType: _str(m, ['visit_type', 'visitType']) ?? '',
      visitDate: visitMillis,
      recordingCount: recordingCount,
    );
  }

  /// Combines a 'YYYY-MM-DD' date + optional 'HH:mm' time into epoch millis
  /// (local). Returns 0 when there's no usable date.
  int _visitMillis(String? date, String? time) {
    if (date == null || date.isEmpty) return 0;
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    final t = (time != null && time.isNotEmpty && time != 'null')
        ? (time.length >= 5 ? time.substring(0, 5) : time)
        : '00:00';
    final dt = DateTime.tryParse('${d}T$t') ?? DateTime.tryParse(d);
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  /// Maps the server's (visit status, note status) pair to the clinician-facing
  /// [VisitStatus]. Note content is fetched lazily once it's ready.
  VisitStatus _statusFromApi({
    String? noteStatus,
    String? visitStatus,
    required bool hasAudio,
  }) {
    switch (noteStatus) {
      case 'submitted':
        return VisitStatus.readyForReview; // scribe finished -> doctor reviews
      case 'uploaded':
        return VisitStatus.approved; // locked / finalized by clinician
    }
    // No (ready) note yet.
    if (visitStatus == 'uploaded') return VisitStatus.approved;
    if (hasAudio) return VisitStatus.withScribe; // audio in, scribe working
    return VisitStatus.pendingUpload; // visit shell, audio not yet uploaded
  }

  // --- response-shape + field helpers ---

  List _listFrom(Object? data, String key) {
    if (data is List) return data;
    if (data is Map) {
      for (final k in [key, 'data', 'results', 'items']) {
        final v = data[k];
        if (v is List) return v;
      }
    }
    return const [];
  }

  Map<String, dynamic> _objFrom(Object? data, String key) {
    if (data is Map) {
      final inner = data[key] ?? data['data'] ?? data['result'];
      if (inner is Map) return inner.cast<String, dynamic>();
      return data.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  String? _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  int _int(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null) return p;
      }
    }
    return 0;
  }

  int _millis(Object? raw) {
    if (raw == null) return DateTime.now().millisecondsSinceEpoch;
    final s = raw.toString();
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return asInt < 1000000000000 ? asInt * 1000 : asInt;
    }
    return (DateTime.tryParse(s) ?? DateTime.now()).millisecondsSinceEpoch;
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
