import 'package:flutter_test/flutter_test.dart';
import 'package:notenra/screens/note_review_screen.dart';

void main() {
  group('AI Note Parsing & Validation', () {
    test('parseNoteSections extracts all SOAP sections and ICD-10/CPT codes correctly', () {
      const sampleClinicalNote = '''
SUBJECTIVE:
Chief Complaint: Acute onset bilateral throbbing headache for 3 days.
History: Patient reports mild photophobia, denies nausea, fever, or visual aura.

OBJECTIVE:
Vitals: BP 142/88 mmHg, HR 74 bpm regular, SpO2 98% on room air, Temp 98.4 F.
Physical Exam: Alert, oriented x4. Cranial nerves II-XII intact. Neck supple, no meningismus.

ASSESSMENT:
1. Primary tension-type headache with migraine features.
2. Stage 1 essential hypertension.

PLAN:
1. Ibuprofen 600mg PO TID PRN headache with food.
2. Lifestyle modifications for blood pressure control (DASH diet, reduce sodium).
3. Follow up in clinic in 4 weeks or sooner if red flag symptoms develop.

MEDICAL CODES & BILLING:
ICD-10-CM Diagnosis Codes:
- G44.209: Tension-type headache, unspecified, not intractable
- I10: Essential (primary) hypertension

CPT / E&M Procedure Codes:
- 99214: Office or other outpatient visit for evaluation and management (moderate complexity)
''';

      final sections = parseNoteSections(sampleClinicalNote);

      expect(sections.containsKey('SUBJECTIVE'), isTrue);
      expect(sections['SUBJECTIVE'], contains('Acute onset bilateral throbbing headache'));

      expect(sections.containsKey('OBJECTIVE'), isTrue);
      expect(sections['OBJECTIVE'], contains('BP 142/88 mmHg'));

      expect(sections.containsKey('ASSESSMENT'), isTrue);
      expect(sections['ASSESSMENT'], contains('tension-type headache'));

      expect(sections.containsKey('PLAN'), isTrue);
      expect(sections['PLAN'], contains('Ibuprofen 600mg'));

      expect(sections.containsKey('CODES'), isTrue);
      expect(sections['CODES'], contains('G44.209'));
      expect(sections['CODES'], contains('I10'));
      expect(sections['CODES'], contains('99214'));
    });
  });
}
