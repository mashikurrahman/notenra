import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/audit_scrub.dart';

/// The audit trail is retained for years and shipped off-device, so a PHI leak
/// in `details` is both durable and remote. [AuditScrub] is the single funnel all
/// 20 `_audit()` call sites pass through — these tests pin its behaviour.
void main() {
  const roster = [
    'Arthur Pendelton',
    'Sophia Martinez',
    'Eleanor Fitzgerald',
    'Bo', // Deliberately short: must not be used as a redaction pattern.
  ];

  group('MRN redaction', () {
    test('strips an MRN in each written form', () {
      for (final raw in [
        'Added patient MRN-339281',
        'Added patient MRN 339281',
        'Added patient MRN:339281',
        'Added patient mrn339281',
        'Added patient Mrn-339281',
      ]) {
        final out = AuditScrub.details(raw, roster);
        expect(out, 'Added patient [mrn]', reason: 'failed on: $raw');
        expect(out.contains('339281'), isFalse);
      }
    });

    test('strips multiple MRNs in one string', () {
      expect(
        AuditScrub.details('merged MRN-1001 into MRN-2002', roster),
        'merged [mrn] into [mrn]',
      );
    });

    test('leaves unrelated digits alone', () {
      expect(
        AuditScrub.details('Uploaded 3 recordings, visit 88', roster),
        'Uploaded 3 recordings, visit 88',
      );
    });
  });

  group('patient name redaction', () {
    test('strips a name from the loaded roster', () {
      expect(
        AuditScrub.details('Opened visit for Sophia Martinez', roster),
        'Opened visit for [patient]',
      );
    });

    test('strips the longest matching name, not a fragment of it', () {
      // 'Sophia' alone is also a roster entry here; the full name must win so
      // the surname is not left behind.
      const overlapping = ['Sophia', 'Sophia Martinez'];
      expect(
        AuditScrub.details('Opened visit for Sophia Martinez', overlapping),
        'Opened visit for [patient]',
      );
    });

    test('strips every occurrence of a name', () {
      expect(
        AuditScrub.details(
            'Arthur Pendelton rescheduled; notified Arthur Pendelton', roster),
        '[patient] rescheduled; notified [patient]',
      );
    });

    test('ignores roster names shorter than three characters', () {
      // 'Bo' would otherwise match inside ordinary words like "Both".
      expect(
        AuditScrub.details('Both recordings uploaded', roster),
        'Both recordings uploaded',
      );
    });

    test('keeps the clinician who acted', () {
      // An audit trail exists to record who acted; the actor is not PHI to be
      // scrubbed, and only patients are on the roster.
      expect(
        AuditScrub.details('Approved by Dr. Helen Smith', roster),
        'Approved by Dr. Helen Smith',
      );
    });

    test('handles an empty roster', () {
      expect(AuditScrub.details('Signed in', const []), 'Signed in');
    });

    test('strips name and MRN together', () {
      expect(
        AuditScrub.details('Added patient Sophia Martinez (MRN-110293)', roster),
        'Added patient [patient] ([mrn])',
      );
    });
  });

  group('length', () {
    test('passes short strings through untouched', () {
      expect(AuditScrub.details('', roster), '');
      expect(AuditScrub.details('Signed out', roster), 'Signed out');
    });

    test('truncates an over-long detail to the cap', () {
      final out = AuditScrub.details('x' * 900, roster);
      expect(out.length, AuditScrub.maxLength);
      expect(out.endsWith('...'), isTrue);
    });

    test('does not truncate a string exactly at the cap', () {
      final out = AuditScrub.details('y' * AuditScrub.maxLength, roster);
      expect(out.length, AuditScrub.maxLength);
      expect(out.endsWith('...'), isFalse);
    });
  });
}
