import '../models.dart';
import 'api_client.dart';

/// Patient roster against the confirmed Anot Health REST API.
///
///   GET  /patients          -> { patients: [{id,name,mrn,date_of_birth,created_at}] }
///   POST /patients  body {name, mrn, date_of_birth?} -> 201 { patient: {...} }
///
/// IMPORTANT server behaviour: `GET /patients` only returns patients the
/// clinician already has a **visit** with (INNER JOIN visits). A patient created
/// via POST therefore won't appear in the list until a visit exists — so the
/// caller keeps the just-created patient in memory (returned here) so the doctor
/// can record immediately; it then shows up naturally once the first visit lands.
class PatientsApi {
  final ApiClient api;
  PatientsApi(this.api);

  Future<List<Patient>> list() async {
    final res = await api.dio.get('/patients');
    final data = res.data;
    final raw = data is Map ? (data['patients'] ?? data['data']) : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => _fromApi(m.cast<String, dynamic>()))
        .toList();
  }

  Future<Patient> create({required String name, required String mrn, String? dob}) async {
    final res = await api.dio.post('/patients', data: {
      'name': name,
      'mrn': mrn,
      if (dob != null && dob.isNotEmpty) 'date_of_birth': dob,
    });
    final data = res.data;
    final obj = data is Map ? (data['patient'] ?? data['data'] ?? data) : data;
    return _fromApi((obj as Map).cast<String, dynamic>());
  }

  /// Create an initial visit for a just-created patient so the server's
  /// `GET /patients` (which INNER JOINs visits) includes this patient — exactly
  /// what the web app's "Schedule New Patient" form does. Without a visit row the
  /// patient exists in the DB but is invisible to clinicians on app *and* web.
  /// Returns the new visit id so the recording can attach to this same visit.
  Future<String?> createVisitForPatient(int patientId,
      {String visitType = 'New Patient',
      String? visitDate,
      String? visitTime}) async {
    final now = DateTime.now();
    final date = visitDate ??
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = visitTime ??
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final res = await api.dio.post('/visits', data: {
      'patient_id': patientId,
      'visit_date': date,
      'visit_time': time,
      'visit_type': visitType,
    });
    final data = res.data;
    final obj = data is Map ? (data['visit'] ?? data['data'] ?? data) : data;
    if (obj is Map) {
      final id = obj['id'] ?? obj['visit_id'];
      if (id != null) return id.toString();
    }
    return null;
  }

  // --- mapping: server patient -> local Patient model ---
  Patient _fromApi(Map<String, dynamic> m) {
    final dob = m['date_of_birth']?.toString();
    return Patient(
      id: _int(m['id']),
      name: (m['name'] ?? '').toString(),
      mrn: (m['mrn'] ?? '').toString(),
      age: _ageFromDob(dob),
      gender: 'Unknown',
      priority: 'Medium',
      lastContactDate: _millis(m['created_at']),
      medicalHistory: '',
      specialty: 'General',
      dob: (dob == null || dob == 'null') ? '' : dob,
    );
  }

  static int _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int _ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return 0;
    final d = DateTime.tryParse(dob);
    if (d == null) return 0;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age < 0 || age > 130 ? 0 : age;
  }

  static int _millis(Object? raw) {
    if (raw == null) return DateTime.now().millisecondsSinceEpoch;
    final s = raw.toString();
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return asInt < 1000000000000 ? asInt * 1000 : asInt;
    }
    return (DateTime.tryParse(s) ?? DateTime.now()).millisecondsSinceEpoch;
  }
}
