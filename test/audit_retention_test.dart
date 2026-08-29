import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:notenra/database.dart';
import 'package:notenra/models.dart';

/// Audit-trail durability: the schema migration that introduced `synced`, and
/// the retention purge that consumes it.
///
/// These run real SQL against an in-memory sqlite rather than asserting on
/// transcribed query strings — the failure mode being guarded against is a
/// mistake *in* the SQL (a `synced = 1` that should be `synced = 0` silently
/// destroys audit history), which a string comparison would happily reproduce.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final db = AppDatabase.instance;

  /// The v3 shape of `audit_logs`: identical to v4 except `synced` does not
  /// exist yet. Written out here because the codebase only carries the current
  /// DDL — a migration test needs the *old* schema to migrate from.
  const auditLogsV3 = '''
      CREATE TABLE audit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clinicianId INTEGER NOT NULL,
        clinicianName TEXT NOT NULL,
        action TEXT NOT NULL,
        patientId INTEGER,
        details TEXT NOT NULL DEFAULT '',
        timestamp INTEGER NOT NULL
      )''';

  const recordingsV3 = '''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patientId INTEGER NOT NULL,
        audioFilePath TEXT NOT NULL,
        label TEXT NOT NULL,
        durationMs INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        uploadStatus TEXT NOT NULL DEFAULT 'pending'
      )''';

  int daysAgo(int n) =>
      DateTime.now().subtract(Duration(days: n)).millisecondsSinceEpoch;

  Future<Database> openV4() async {
    final d = await factory.openDatabase(inMemoryDatabasePath);
    await db.createSchemaForTest(d);
    db.useDatabaseForTest(d);
    return d;
  }

  Future<void> insertAuditRow({
    required String action,
    required int timestamp,
    bool synced = false,
    int? patientId,
    String details = '',
  }) async {
    await db.insertAudit(AuditEntry(
      clinicianId: 1,
      clinicianName: 'Dr. Test',
      action: action,
      patientId: patientId,
      details: details,
      timestamp: timestamp,
      synced: synced,
    ));
  }

  group('v3 -> v4 migration', () {
    test('preserves existing audit rows and marks them unshipped', () async {
      final d = await factory.openDatabase(inMemoryDatabasePath);
      addTearDown(d.close);

      // A device sitting on v3 with audit history already recorded.
      await d.execute(auditLogsV3);
      await d.execute(recordingsV3);
      await d.insert('audit_logs', {
        'clinicianId': 7,
        'clinicianName': 'Dr. Pre-Upgrade',
        'action': 'AUTO_LOGOFF',
        'patientId': null,
        'details': 'session timed out',
        'timestamp': daysAgo(200),
      });
      await d.insert('audit_logs', {
        'clinicianId': 7,
        'clinicianName': 'Dr. Pre-Upgrade',
        'action': 'DELETE_RECORDING',
        'patientId': 42,
        'details': 'discarded before upload',
        'timestamp': daysAgo(199),
      });

      await db.upgradeSchemaForTest(d, 3, 4);

      final rows = await d.query('audit_logs', orderBy: 'id ASC');
      expect(rows.length, 2, reason: 'migration must not drop history');
      expect(rows[0]['action'], 'AUTO_LOGOFF');
      expect(rows[1]['action'], 'DELETE_RECORDING');
      expect(rows[1]['patientId'], 42);
      // Pre-existing rows must default to unshipped so history recorded before
      // audit shipping existed is still sent up, not silently skipped.
      expect(rows.every((r) => r['synced'] == 0), isTrue);
    });

    test('is a no-op on a database already at v4', () async {
      final d = await openV4();
      addTearDown(d.close);
      await insertAuditRow(action: 'LOGIN', timestamp: daysAgo(1));

      // oldVersion == newVersion: no branch fires, nothing is lost.
      await db.upgradeSchemaForTest(d, 4, 4);

      expect((await d.query('audit_logs')).length, 1);
    });
  });

  group('purgeSyncedAuditOlderThan', () {
    test('deletes only rows the server already holds', () async {
      final d = await openV4();
      addTearDown(d.close);

      await insertAuditRow(
          action: 'OLD_SHIPPED', timestamp: daysAgo(200), synced: true);
      await insertAuditRow(
          action: 'OLD_UNSHIPPED', timestamp: daysAgo(200), synced: false);
      await insertAuditRow(
          action: 'RECENT_SHIPPED', timestamp: daysAgo(10), synced: true);
      await insertAuditRow(
          action: 'RECENT_UNSHIPPED', timestamp: daysAgo(10), synced: false);

      final removed =
          await db.purgeSyncedAuditOlderThan(const Duration(days: 90));

      expect(removed, 1);
      final surviving = (await d.query('audit_logs'))
          .map((r) => r['action'] as String)
          .toSet();
      // The critical assertion: a row that never reached the server is retained
      // regardless of age. A phone offline for months must not lose events.
      expect(surviving, {'OLD_UNSHIPPED', 'RECENT_SHIPPED', 'RECENT_UNSHIPPED'});
    });

    test('deletes nothing when every row is unshipped', () async {
      final d = await openV4();
      addTearDown(d.close);

      for (var i = 0; i < 5; i++) {
        await insertAuditRow(action: 'EV_$i', timestamp: daysAgo(365));
      }

      expect(await db.purgeSyncedAuditOlderThan(const Duration(days: 90)), 0);
      expect((await d.query('audit_logs')).length, 5);
    });
  });

  group('unsynced audit queries', () {
    test('returns oldest-first and excludes shipped rows', () async {
      final d = await openV4();
      addTearDown(d.close);

      await insertAuditRow(action: 'FIRST', timestamp: daysAgo(3));
      await insertAuditRow(
          action: 'SHIPPED', timestamp: daysAgo(2), synced: true);
      await insertAuditRow(action: 'SECOND', timestamp: daysAgo(1));

      final pending = await db.getUnsyncedAudit();

      expect(pending.map((e) => e.action), ['FIRST', 'SECOND']);
      expect(await db.unsyncedAuditCount(), 2);
    });

    test('markAuditSynced marks exactly the given ids', () async {
      final d = await openV4();
      addTearDown(d.close);

      await insertAuditRow(action: 'A', timestamp: daysAgo(3));
      await insertAuditRow(action: 'B', timestamp: daysAgo(2));
      await insertAuditRow(action: 'C', timestamp: daysAgo(1));

      final pending = await db.getUnsyncedAudit();
      final ids = pending.map((e) => e.id).toList();
      await db.markAuditSynced([ids.first, ids.last]);

      final still = await db.getUnsyncedAudit();
      expect(still.map((e) => e.action), ['B']);
      expect(await db.unsyncedAuditCount(), 1);
    });

    test('markAuditSynced on an empty list is a no-op', () async {
      final d = await openV4();
      addTearDown(d.close);
      await insertAuditRow(action: 'A', timestamp: daysAgo(1));

      await db.markAuditSynced([]);

      expect(await db.unsyncedAuditCount(), 1);
    });

    test('synced survives a round trip through AuditEntry', () async {
      final d = await openV4();
      addTearDown(d.close);

      await insertAuditRow(
          action: 'SHIPPED', timestamp: daysAgo(1), synced: true);

      final all = await db.getAuditLogs();
      expect(all.single.synced, isTrue);
    });
  });
}
