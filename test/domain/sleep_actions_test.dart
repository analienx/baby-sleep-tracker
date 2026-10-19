import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_clock.dart';

void main() {
  test('one tap starts, another finishes, keeping the same ID', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: clock,
      newId: () => 'synthetic-id',
    );

    expect(await actions.toggle(), isTrue);
    clock.advance(const Duration(minutes: 42));
    expect(await actions.toggle(), isTrue);

    final records = await repository.readSessions();
    expect(records, hasLength(1));
    expect(records.single.id, 'synthetic-id');
    expect(
      records.single.endedAtUtc!.difference(records.single.startedAtUtc),
      const Duration(minutes: 42),
    );
  });

  test('concurrent taps do not start two sessions', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: clock,
      newId: () => 'synthetic-id',
    );

    final results = await Future.wait([actions.toggle(), actions.toggle()]);
    expect(results.where((changed) => changed), hasLength(1));
    expect((await repository.readSessions()).single.isActive, isTrue);
  });

  test(
    'backward device clock does not create an invalid finished session',
    () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);
      final actions = SleepActions(repository: repository, clock: clock);

      await actions.toggle();
      clock.advance(const Duration(minutes: -10));
      expect(await actions.toggle(), isFalse);
      expect((await repository.readSessions()).single.isActive, isTrue);
    },
  );

  test(
    'repository emits an initial snapshot and subsequent mutation',
    () async {
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);
      final emitted = <int>[];
      final subscription = repository.watchSessions().listen((items) {
        emitted.add(items.length);
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
      await SleepActions(
        repository: repository,
        clock: clock,
        newId: () => 'synthetic-id',
      ).toggle();
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [0, 1]);
    },
  );
}
