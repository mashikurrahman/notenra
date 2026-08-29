import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/models.dart';
import 'package:notenra/api/clinical_models.dart';
import 'package:notenra/widgets/nx.dart';

void main() {
  group('Patient.copyWith', () {
    final base = Patient(
      name: 'Alam',
      mrn: '1243689',
      age: 30,
      gender: 'Unknown',
      priority: 'Medium',
      lastContactDate: 0,
      medicalHistory: '',
    );

    test('overrides dob/visitType/visitDate and preserves the rest', () {
      final c = base.copyWith(
          dob: '1990-01-01', visitType: 'Follow-up', visitDate: 123);
      expect(c.dob, '1990-01-01');
      expect(c.visitType, 'Follow-up');
      expect(c.visitDate, 123);
      expect(c.name, 'Alam');
      expect(c.mrn, '1243689');
    });

    test('null arguments keep existing values', () {
      final c = base.copyWith(visitType: 'New Patient');
      expect(c.visitType, 'New Patient');
      expect(c.dob, '');
      expect(c.visitDate, 0);
    });
  });

  group('Visit.fromJson', () {
    test('parses visit_type and combines visit_date + visit_time', () {
      final v = Visit.fromJson({
        'id': 'v1',
        'patient_id': 7,
        'visit_type': 'Follow-up',
        'visit_date': '2026-06-21',
        'visit_time': '12:45',
      });
      expect(v.id, 'v1');
      expect(v.patientId, 7);
      expect(v.visitType, 'Follow-up');
      final dt = DateTime.fromMillisecondsSinceEpoch(v.visitDate);
      expect(dt.year, 2026);
      expect(dt.month, 6);
      expect(dt.day, 21);
      expect(dt.hour, 12);
      expect(dt.minute, 45);
    });

    test('missing visit type/date default safely', () {
      final v = Visit.fromJson({'id': 'v2', 'patient_id': 1});
      expect(v.visitType, '');
      expect(v.visitDate, 0);
    });
  });

  group('NxPinInput widget', () {
    testWidgets('renders 6 digit cells and responds to text changes',
        (tester) async {
      final ctrl = TextEditingController();
      bool submitted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NxPinInput(
              controller: ctrl,
              onSubmit: () => submitted = true,
            ),
          ),
        ),
      );

      expect(find.byType(NxPinInput), findsOneWidget);
      ctrl.text = '123456';
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(submitted, isTrue);
    });
  });

  group('NxNoteSkeleton widget', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NxNoteSkeleton(),
          ),
        ),
      );

      expect(find.byType(NxNoteSkeleton), findsOneWidget);
    });
  });
}
