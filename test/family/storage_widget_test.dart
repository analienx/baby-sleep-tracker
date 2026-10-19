import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/presentation_helpers.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/storage_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget familyStatusView(
  StorageEnvironment environment,
  SleepStorageStatus status,
) => ProviderScope(
  overrides: [
    storageEnvironmentProvider.overrideWithValue(environment),
    sleepStorageProvider.overrideWith((ref) => Stream.value(status)),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          ScreenIntro(title: 'Little rest', subtitle: 'Family'),
          PreviewWarning(),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('family cloud badge and sync message are not volatile preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      familyStatusView(
        StorageEnvironment.familyCloud,
        const SleepStorageStatus(StoragePhase.synced),
      ),
    );
    await tester.pump();
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('Synced with your family cloud.'), findsOneWidget);
    expect(find.textContaining('not saved'), findsNothing);
  });

  testWidgets('family emulator shows pending state truthfully', (tester) async {
    await tester.pumpWidget(
      familyStatusView(
        StorageEnvironment.familyEmulator,
        const SleepStorageStatus(StoragePhase.pending),
      ),
    );
    await tester.pump();
    expect(find.text('FAMILY DEV'), findsOneWidget);
    expect(find.textContaining('pending server sync'), findsOneWidget);
  });

  testWidgets('family emulator shows cached state truthfully', (tester) async {
    await tester.pumpWidget(
      familyStatusView(
        StorageEnvironment.familyEmulator,
        const SleepStorageStatus(StoragePhase.cached),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Cached on device'), findsOneWidget);
  });
}
