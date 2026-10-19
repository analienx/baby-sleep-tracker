import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/sleep/data/preview_sleep_repository.dart';
import '../features/sleep/domain/sleep_actions.dart';
import '../features/sleep/domain/sleep_repository.dart';
import '../features/sleep/domain/sleep_session.dart';
import 'clock.dart';

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final previewRepositoryProvider = Provider<PreviewSleepRepository>((ref) {
  final repository = PreviewSleepRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final sleepRepositoryProvider = Provider<SleepRepository>(
  (ref) => ref.watch(previewRepositoryProvider),
);

final sleepSessionsProvider = StreamProvider<List<SleepSession>>(
  (ref) => ref.watch(sleepRepositoryProvider).watchSessions(),
);

final sleepStorageProvider = StreamProvider<SleepStorageStatus>(
  (ref) => ref.watch(sleepRepositoryProvider).watchStorageStatus(),
);

final sleepConflictsProvider = StreamProvider(
  (ref) => ref.watch(sleepRepositoryProvider).watchConflicts(),
);

final sleepActionsProvider = Provider<SleepActions>(
  (ref) => SleepActions(
    repository: ref.watch(sleepRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
