import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/api/mock_backend.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/screens/note_review_screen.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  group('AI Note UI & Parsing Tests', () {
    test('parseNoteSections parses full SOAP sections and medical coding', () {
      const rawNote = '''
SUBJECTIVE:
Patient reports persistent headaches.

OBJECTIVE:
BP 140/90 mmHg, HR 72 bpm.

ASSESSMENT:
Primary essential hypertension.

PLAN:
Start Lisinopril 10mg daily.

MEDICAL CODES & BILLING:
ICD-10-CM Diagnosis Codes:
- I10: Essential (primary) hypertension
- R51.9: Headache, unspecified

CPT / E&M Procedure Codes:
- 99214: Office or other outpatient visit (moderate complexity)
''';

      final sections = parseNoteSections(rawNote);
      expect(sections.containsKey('SUBJECTIVE'), isTrue);
      expect(sections['SUBJECTIVE'], contains('Patient reports persistent headaches'));
      expect(sections.containsKey('OBJECTIVE'), isTrue);
      expect(sections['OBJECTIVE'], contains('BP 140/90 mmHg'));
      expect(sections.containsKey('ASSESSMENT'), isTrue);
      expect(sections['ASSESSMENT'], contains('Primary essential hypertension'));
      expect(sections.containsKey('PLAN'), isTrue);
      expect(sections['PLAN'], contains('Start Lisinopril 10mg daily'));
      expect(sections.containsKey('CODES'), isTrue);
      expect(sections['CODES'], contains('I10'));
      expect(sections['CODES'], contains('99214'));
    });

    testWidgets('NoteReviewScreen renders SOAP tabs and Medical Codes', (tester) async {
      final backend = MockBackend();
      final clinical = ClinicalService(
        connectivity: ConnectivityService(),
        tokens: TokenStore(),
        backend: backend,
      );
      await clinical.init();

      final visit = await backend.createVisit(patientId: 1, patientName: 'Arthur Dent');
      final readyVisit = await backend.uploadAudio(visitId: visit.id, audioPath: '/tmp/rec.m4a');
      expect(readyVisit.note, isNotNull);
      await clinical.refresh();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: clinical),
          ],
          child: MaterialApp(
            home: NoteReviewScreen(visitId: readyVisit.id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Header & status
      expect(find.text('Arthur Dent'), findsOneWidget);
      expect(find.text('Ready for you'), findsOneWidget);

      // Tabs
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Subjective'), findsOneWidget);
      expect(find.text('Codes (ICD/CPT)'), findsOneWidget);

      // Switch to Codes tab
      await tester.tap(find.text('Codes (ICD/CPT)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ICD-10 Diagnosis Codes'), findsOneWidget);
      expect(find.text('I10'), findsOneWidget);
      expect(find.text('99214'), findsOneWidget);
      expect(find.text('Approve & Sign Note'), findsOneWidget);

      // Tear down widget tree cleanly
      await tester.pumpWidget(const SizedBox());
    });
  });
}
