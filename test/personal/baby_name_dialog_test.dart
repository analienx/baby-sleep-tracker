import 'package:baby_sleep_tracker/features/personal/presentation/personal_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('baby name dialog: Enter submits once with no error', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const BabyNameDialog(
                    title: 'Rename baby',
                    initial: 'First',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rename baby'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Second');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 'Second');
    expect(find.text('Rename baby'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
