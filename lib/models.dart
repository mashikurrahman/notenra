/// Data models ported from the original Android app (com.example.data.model).
library;

class User {
  final int id;
  final String username;
  final String passwordHash; // NOTE: plaintext in the original app; kept as-is for parity.
  final String fullName;
  final String provider;
  final String role; // 'clinician' | 'admin'

  User({
    this.id = 0,
    required this.username,
    required this.passwordHash,
    required this.fullName,
    this.provider = 'local',
    this.role = 'clinician',
  });

  bool get isAdmin => role == 'admin';

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'username': username,
        'passwordHash': passwordHash,
        'fullName': fullName,
        'provider': provider,
        'role': role,
      };

  factory User.fromMap(Map<String, Object?> m) => User(
        id: m['id'] as int,
        username: m['username'] as String,
        passwordHash: m['passwordHash'] as String,
        fullName: m['fullName'] as String,
        provider: (m['provider'] as String?) ?? 'local',
        role: (m['role'] as String?) ?? 'clinician',
      );

  User copyWith({String? passwordHash, String? fullName, String? role}) => User(
        id: id,
        username: username,
        passwordHash: passwordHash ?? this.passwordHash,
        fullName: fullName ?? this.fullName,
        provider: provider,
        role: role ?? this.role,
      );
}

class Recording {
  final int id;
  final int patientId;
  final String audioFilePath;
  final String label;
  final int durationMs;
  final int timestamp;
  final String uploadStatus; // pending | uploading | uploaded | failed

  Recording({
    this.id = 0,
    required this.patientId,
    required this.audioFilePath,
    required this.label,
    required this.durationMs,
    required this.timestamp,
    this.uploadStatus = 'pending',
  });

  bool get isUploaded => uploadStatus == 'uploaded';

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'patientId': patientId,
        'audioFilePath': audioFilePath,
        'label': label,
        'durationMs': durationMs,
        'timestamp': timestamp,
        'uploadStatus': uploadStatus,
      };

  factory Recording.fromMap(Map<String, Object?> m) => Recording(
        id: m['id'] as int,
        patientId: m['patientId'] as int,
        audioFilePath: m['audioFilePath'] as String,
        label: m['label'] as String,
        durationMs: m['durationMs'] as int,
        timestamp: m['timestamp'] as int,
        uploadStatus: (m['uploadStatus'] as String?) ?? 'pending',
      );
}

class AuditEntry {
  final int id;
  final int clinicianId;
  final String clinicianName;
  final String action;
  final int? patientId;
  final String details;
  final int timestamp;

  AuditEntry({
    this.id = 0,
    required this.clinicianId,
    required this.clinicianName,
    required this.action,
    this.patientId,
    this.details = '',
    required this.timestamp,
  });

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'clinicianId': clinicianId,
        'clinicianName': clinicianName,
        'action': action,
        'patientId': patientId,
        'details': details,
        'timestamp': timestamp,
      };

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
        id: m['id'] as int,
        clinicianId: m['clinicianId'] as int,
        clinicianName: (m['clinicianName'] as String?) ?? '',
        action: m['action'] as String,
        patientId: m['patientId'] as int?,
        details: (m['details'] as String?) ?? '',
        timestamp: m['timestamp'] as int,
      );
}

class Patient {
  final int id;
  final String name;
  final String mrn;
  final int age;
  final String gender;
  final String priority; // High | Medium | Low
  final int lastContactDate; // epoch millis
  final String medicalHistory;
  final String specialty;
  final String emergencyContactName;
  final String emergencyContactPhone;
  // Date of birth as 'YYYY-MM-DD' ('' if unknown). Kept in-memory only (not in
  // the local SQLite schema) — sourced from the server's `date_of_birth`.
  final String dob;
  // The current visit type for this patient (e.g. 'New Patient', 'Follow-up').
  // In-memory only; populated on add and via the visits join.
  final String visitType;
  // Scheduled visit date/time as epoch millis (0 if unknown). In-memory only.
  final int visitDate;

  Patient({
    this.id = 0,
    required this.name,
    required this.mrn,
    required this.age,
    required this.gender,
    required this.priority,
    required this.lastContactDate,
    required this.medicalHistory,
    this.specialty = 'General',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.dob = '',
    this.visitType = '',
    this.visitDate = 0,
  });

  Patient copyWith({
    String? dob,
    String? visitType,
    int? visitDate,
    int? lastContactDate,
  }) =>
      Patient(
        id: id,
        name: name,
        mrn: mrn,
        age: age,
        gender: gender,
        priority: priority,
        lastContactDate: lastContactDate ?? this.lastContactDate,
        medicalHistory: medicalHistory,
        specialty: specialty,
        emergencyContactName: emergencyContactName,
        emergencyContactPhone: emergencyContactPhone,
        dob: dob ?? this.dob,
        visitType: visitType ?? this.visitType,
        visitDate: visitDate ?? this.visitDate,
      );

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'mrn': mrn,
        'age': age,
        'gender': gender,
        'priority': priority,
        'lastContactDate': lastContactDate,
        'medicalHistory': medicalHistory,
        'specialty': specialty,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
      };

  factory Patient.fromMap(Map<String, Object?> m) => Patient(
        id: m['id'] as int,
        name: m['name'] as String,
        mrn: m['mrn'] as String,
        age: m['age'] as int,
        gender: m['gender'] as String,
        priority: m['priority'] as String,
        lastContactDate: m['lastContactDate'] as int,
        medicalHistory: m['medicalHistory'] as String,
        specialty: (m['specialty'] as String?) ?? 'General',
        emergencyContactName: (m['emergencyContactName'] as String?) ?? '',
        emergencyContactPhone: (m['emergencyContactPhone'] as String?) ?? '',
      );
}
