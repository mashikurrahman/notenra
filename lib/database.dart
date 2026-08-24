import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'app_config.dart';
import 'models.dart';
import 'security.dart';

/// SQLCipher-encrypted database (AES-256 at rest). The encryption key is a
/// random 256-bit value held in the OS Keystore/Keychain (see [Security]),
/// not hardcoded — a HIPAA encryption/access-control safeguard.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'notenra_phi_vault.db');
    final key = await Security.getOrCreateDbKey();
    _db = await openDatabase(
      path,
      password: key,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _seedIfNeeded(_db!);
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_appointmentsTable);
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE recordings ADD COLUMN uploadStatus TEXT NOT NULL DEFAULT 'pending'");
    }
    if (oldVersion < 4) {
      // Tracks whether an audit row has been accepted by the server. Existing
      // rows default to 0 (unshipped) so history recorded before audit shipping
      // existed is still sent up rather than silently skipped.
      await db.execute(
          'ALTER TABLE audit_logs ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
    }
  }

  static const _appointmentsTable = '''
      CREATE TABLE IF NOT EXISTS appointments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remoteId TEXT NOT NULL DEFAULT '',
        patientId INTEGER NOT NULL,
        patientName TEXT NOT NULL,
        startAt INTEGER NOT NULL,
        durationMin INTEGER NOT NULL DEFAULT 30,
        reason TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'scheduled'
      )''';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        passwordHash TEXT NOT NULL,
        fullName TEXT NOT NULL,
        provider TEXT NOT NULL DEFAULT 'local',
        role TEXT NOT NULL DEFAULT 'clinician'
      )''');
    await db.execute('''
      CREATE TABLE patients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mrn TEXT NOT NULL,
        age INTEGER NOT NULL,
        gender TEXT NOT NULL,
        priority TEXT NOT NULL,
        lastContactDate INTEGER NOT NULL,
        medicalHistory TEXT NOT NULL,
        specialty TEXT NOT NULL DEFAULT 'General',
        emergencyContactName TEXT NOT NULL DEFAULT '',
        emergencyContactPhone TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patientId INTEGER NOT NULL,
        audioFilePath TEXT NOT NULL,
        label TEXT NOT NULL,
        durationMs INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        uploadStatus TEXT NOT NULL DEFAULT 'pending'
      )''');
    await db.execute('''
      CREATE TABLE audit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clinicianId INTEGER NOT NULL,
        clinicianName TEXT NOT NULL,
        action TEXT NOT NULL,
        patientId INTEGER,
        details TEXT NOT NULL DEFAULT '',
        timestamp INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // Shipping scans for unsynced rows on every flush; retention deletes by
    // timestamp among synced rows. Both are covered by one composite index.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_synced ON audit_logs(synced, timestamp)');
    await db.execute(_appointmentsTable);
  }

  Future<void> _seedIfNeeded(Database db) async {
    // Demo logins are seeded ONLY in demo/dev builds. A production build
    // (--dart-define=DEMO_ACCOUNTS=false) ships with no built-in credentials.
    if (!AppConfig.seedDemoAccounts) return;

    final userCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM users')) ??
        0;
    if (userCount == 0) {
      // Seeded demo credentials are stored hashed (PBKDF2), never plaintext.
      await db.insert('users', User(
        username: 'dr.smith@notenra.health',
        passwordHash: Security.hashPassword('password123'),
        fullName: 'Dr. Helen Smith',
      ).toMap());
      await db.insert('users', User(
        username: 'admin',
        passwordHash: Security.hashPassword('admin123'),
        fullName: 'System Administrator',
        role: 'admin',
      ).toMap());
    }

    final patientCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM patients')) ??
        0;
    if (patientCount == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      const hour = 3600000;
      const day = 86400000;
      final seed = [
        Patient(
          name: 'Arthur Pendelton', mrn: 'MRN-339281', age: 68, gender: 'Male',
          priority: 'High', lastContactDate: now - 2 * day, specialty: 'Cardiology',
          medicalHistory: 'Type 2 Diabetes, Chronic Hypertension. Coronary artery bypass in 2021. Review glucose charts and adjust Insulin.',
          emergencyContactName: 'Clara Pendelton (Spouse)', emergencyContactPhone: '+1 (555) 382-9011',
        ),
        Patient(
          name: 'Sophia Martinez', mrn: 'MRN-110293', age: 34, gender: 'Female',
          priority: 'High', lastContactDate: now - 1 * hour, specialty: 'Pediatrics',
          medicalHistory: 'Asthma, severe allergic rhinitis. Hospitalized last month for acute bronchospasm. Reviewing inhaler technique.',
          emergencyContactName: 'Mateo Martinez (Brother)', emergencyContactPhone: '+1 (555) 472-8821',
        ),
        Patient(
          name: 'Gregory Vance', mrn: 'MRN-992031', age: 52, gender: 'Male',
          priority: 'Medium', lastContactDate: now - 5 * day, specialty: 'Neurology',
          medicalHistory: 'Mild osteoarthritis in both knees. Regular physical therapist visits. Managing with low-dose NSAIDs.',
          emergencyContactName: 'Laura Vance (Wife)', emergencyContactPhone: '+1 (555) 901-4473',
        ),
        Patient(
          name: 'Eleanor Fitzgerald', mrn: 'MRN-445821', age: 79, gender: 'Female',
          priority: 'Low', lastContactDate: now - 12 * day, specialty: 'General',
          medicalHistory: 'Early stage osteoporosis. On calcium and Vitamin D supplements. Annual bone density scan scheduled.',
          emergencyContactName: 'Vivian Fitzgerald (Daughter)', emergencyContactPhone: '+1 (555) 124-7788',
        ),
      ];
      for (final pt in seed) {
        await db.insert('patients', pt.toMap());
      }
    }
  }

  // --- Users ---
  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final rows = await db.query('users', where: 'username = ?', whereArgs: [username], limit: 1);
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  Future<User?> getUserById(int id) async {
    final db = await database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final rows = await db.query('users', orderBy: 'id ASC');
    return rows.map(User.fromMap).toList();
  }

  Future<int> getAdminCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
            await db.rawQuery("SELECT COUNT(*) FROM users WHERE role = 'admin'")) ??
        0;
  }

  Future<void> insertUser(User u) async {
    final db = await database;
    await db.insert('users', u.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePassword(int id, String newPass) async {
    final db = await database;
    await db.update('users', {'passwordHash': newPass}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteUser(int id) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // --- Patients ---
  Future<List<Patient>> getAllPatients() async {
    final db = await database;
    final rows = await db.query('patients');
    return rows.map(Patient.fromMap).toList();
  }

  Future<int> insertPatient(Patient p) async {
    final db = await database;
    return db.insert('patients', p.toMap());
  }

  Future<void> updatePatientLastContact(int id, int timestamp) async {
    final db = await database;
    await db.update('patients', {'lastContactDate': timestamp},
        where: 'id = ?', whereArgs: [id]);
  }

  // --- Recordings ---
  Future<int> insertRecording(Recording r) async {
    final db = await database;
    return db.insert('recordings', r.toMap());
  }

  Future<List<Recording>> getAllRecordings() async {
    final db = await database;
    final rows = await db.query('recordings', orderBy: 'timestamp DESC');
    return rows.map(Recording.fromMap).toList();
  }

  Future<List<Recording>> getRecordingsForPatient(int patientId) async {
    final db = await database;
    final rows = await db.query('recordings',
        where: 'patientId = ?', whereArgs: [patientId], orderBy: 'timestamp DESC');
    return rows.map(Recording.fromMap).toList();
  }

  Future<Recording?> getRecordingById(int id) async {
    final db = await database;
    final rows =
        await db.query('recordings', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Recording.fromMap(rows.first);
  }

  Future<void> updateRecordingUploadStatus(String path, String status) async {
    final db = await database;
    await db.update('recordings', {'uploadStatus': status},
        where: 'audioFilePath = ?', whereArgs: [path]);
  }

  /// Repoint a recording's audio path (e.g. plaintext → encrypted once the
  /// background encryption finishes).
  Future<void> updateRecordingPath(String oldPath, String newPath) async {
    final db = await database;
    await db.update('recordings', {'audioFilePath': newPath},
        where: 'audioFilePath = ?', whereArgs: [oldPath]);
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  // --- Audit log ---
  Future<void> insertAudit(AuditEntry entry) async {
    final db = await database;
    await db.insert('audit_logs', entry.toMap());
  }

  Future<List<AuditEntry>> getAuditLogs({int limit = 500}) async {
    final db = await database;
    final rows =
        await db.query('audit_logs', orderBy: 'timestamp DESC', limit: limit);
    return rows.map(AuditEntry.fromMap).toList();
  }

  /// Oldest-first batch of audit rows the server hasn't accepted yet.
  ///
  /// Ascending by id so events reach the server in the order they happened, and
  /// so a row that repeatedly fails to ship stays at the head of the batch
  /// instead of being starved by newer ones.
  Future<List<AuditEntry>> getUnsyncedAudit({int limit = 200}) async {
    final db = await database;
    final rows = await db.query('audit_logs',
        where: 'synced = 0', orderBy: 'id ASC', limit: limit);
    return rows.map(AuditEntry.fromMap).toList();
  }

  /// Mark rows as accepted by the server. Call only after a confirmed success —
  /// marking optimistically would lose the events on a failed request.
  Future<void> markAuditSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
        'UPDATE audit_logs SET synced = 1 WHERE id IN ($placeholders)', ids);
  }

  Future<int> unsyncedAuditCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM audit_logs WHERE synced = 0')) ??
        0;
  }

  /// Local retention: drop audit rows older than [age] that the server already
  /// holds.
  ///
  /// The `synced = 1` predicate is the point of this method — the server is the
  /// system of record for the 7-year retention period, and the device keeps only
  /// a recent window. A row that has never shipped is never deleted here no
  /// matter how old it is, so an event can't be lost by a phone that spent
  /// months offline.
  Future<int> purgeSyncedAuditOlderThan(Duration age) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
    return db.delete('audit_logs',
        where: 'synced = 1 AND timestamp < ?', whereArgs: [cutoff]);
  }
}
