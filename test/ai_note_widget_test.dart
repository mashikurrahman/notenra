import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notenra/api/mock_backend.dart';
import 'package:notenra/api/token_store.dart';
import 'package:notenra/app_state.dart';
import 'package:notenra/screens/note_review_screen.dart';
import 'package:notenra/screens/patient_visit_screen.dart';
import 'package:notenra/services/clinical_service.dart';
import 'package:notenra/services/connectivity_service.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'create') {
          return 'mock_recorder_id';
        }
        if (methodCall.method == 'hasPermission') {
          return true;
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('AI Note UI & Review Flow Widgets', () {
    late MockBackend backend;
    late ClinicalService clinical;
    late AppState appState;

    setUp(() async {
      backend = MockBackend();
      clinical = ClinicalService(
        connectivity: ConnectivityService(),
        tokens: TokenStore(),
        backend: backend,
      );
      await clinical.init();
      appState = AppState(clinical: clinical, tokens: TokenStore());
    });

    testWidgets('NoteReviewScreen parses SOAP sections and renders interactive Medical Codes tab', (tester) async {
      // 1. Create a visit with AI Note
      final visit = await backend.createVisit(patientId: 1, patientName: 'Arthur Dent');
      final readyVisit = await backend.uploadAudio(visitId: visit.id, audioPath: '/tmp/rec.m4a');
      expect(readyVisit.note, isNotNull);

      // Refresh clinical service cache so it has the visit loaded
      await clinical.refresh();

      // 2. Pump NoteReviewScreen
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: clinical),
          ],
          child: MaterialApp(
            home: NoteReviewScreen(visitId: readyVisit.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Verify Patient header & Status pill
      expect(find.text('Arthur Dent'), findsOneWidget);
      expect(find.text('Ready for you'), findsOneWidget);

      // 4. Verify Tab bar contains All, Subjective, Objective, Assessment, Plan, Codes
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Subjective'), findsOneWidget);
      expect(find.text('Objective'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Codes (ICD/CPT)'), findsOneWidget);

      // 5. Tap the "Codes (ICD/CPT)" tab
      await tester.tap(find.text('Codes (ICD/CPT)'));
      await tester.pumpAndSettle();

      // 6. Verify Medical Codes chips & descriptions
      expect(find.text('ICD-10 Diagnosis Codes'), findsOneWidget);
      expect(find.text('I10'), findsOneWidget);
      expect(find.text('Essential (primary) hypertension'), findsOneWidget);
      expect(find.text('CPT / E&M Billing Codes'), findsOneWidget);
      expect(find.text('99214'), findsOneWidget);
      expect(find.text('Copy All Codes'), findsOneWidget);

      // 7. Verify Approval CTA footer button
      expect(find.text('Approve & Sign Note'), findsOneWidget);
    });

    testWidgets('PatientVisitScreen displays "AI Clinical Note Ready" CTA banner when note is ready', (tester) async {
      // 1. Setup visit that is readyForReview
      final visit = await backend.createVisit(patientId: 2, patientName: 'Ford Prefect');
      await backend.uploadAudio(visitId: visit.id, audioPath: '/tmp/rec2.m4a');

      // Refresh clinical service cache
      await clinical.refresh();

      // 2. Pump PatientVisitScreen
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: clinical),
          ],
          child: const MaterialApp(
            home: PatientVisitScreen(
              patientId: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Verify AI Note banner is displayed
      expect(find.text('AI Clinical Note Ready'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    });
  });
}
