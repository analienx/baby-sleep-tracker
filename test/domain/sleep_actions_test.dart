import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_actions.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
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

  test('quick backdate and undo preserve start/end state', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: clock,
      newId: () => 'same-id',
    );
    expect(await actions.start(backdate: const Duration(minutes: 15)), isTrue);
    expect(
      (await repository.readSessions()).single.startedAtUtc,
      DateTime.utc(2026, 10, 19, 7, 45),
    );
    expect(await actions.undo(), isTrue);
    expect(await repository.readSessions(), isEmpty);
    expect(await actions.undo(), isFalse);
    expect(await actions.start(), isTrue);
    clock.advance(const Duration(minutes: 45));
    expect(await actions.stop(), isTrue);
    expect(await actions.undo(), isTrue);
    expect((await repository.readSessions()).single.isActive, isTrue);
  });

  test('conflicting multiple active records prevent arbitrary stop', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 8));
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    await repository.put(
      SleepSession(
        id: 'a',
        startedAtUtc: DateTime.utc(2026, 10, 19, 7),
        endedAtUtc: null,
      ),
    );
    await repository.put(
      SleepSession(
        id: 'b',
        startedAtUtc: DateTime.utc(2026, 10, 19, 7, 30),
        endedAtUtc: null,
      ),
    );
    final actions = SleepActions(repository: repository, clock: clock);
    expect(await actions.stop(), isFalse);
    expect(
      (await repository.readSessions()).where((s) => s.isActive),
      hasLength(2),
    );
  });

  test('an invalid backdate cannot mutate history', () async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: FakeClock(DateTime.utc(2026, 10, 19, 8)),
    );
    await expectLater(
      actions.start(backdate: const Duration(days: 2)),
      throwsArgumentError,
    );
    expect(await repository.readSessions(), isEmpty);
  });

  test('missed nap can be added, corrected, deleted and restored', () async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: FakeClock(DateTime.utc(2026, 10, 19, 12)),
      newId: () => 'missed-nap',
    );
    expect(
      await actions.addCompleted(
        DateTime.utc(2026, 10, 18, 23, 45),
        DateTime.utc(2026, 10, 19, 0, 25),
      ),
      isTrue,
    );
    final original = (await repository.readSessions()).single;
    expect(original.id, 'missed-nap');
    expect(
      await actions.correct(
        original,
        startUtc: DateTime.utc(2026, 10, 18, 23, 40),
        endUtc: DateTime.utc(2026, 10, 19, 0, 30),
      ),
      isTrue,
    );
    expect(await actions.undo(), isTrue);
    expect((await repository.readSessions()).single, original);

    expect(await actions.delete(original), isTrue);
    expect(await repository.readSessions(), isEmpty);
    expect(await actions.undo(), isTrue);
    expect((await repository.readSessions()).single, original);
  });

  test('stale editor cannot delete or overwrite a newer correction', () async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final original = SleepSession(
      id: 'edit-me',
      startedAtUtc: DateTime.utc(2026, 10, 19, 8),
      endedAtUtc: DateTime.utc(2026, 10, 19, 9),
    );
    await repository.put(original);
    final actions = SleepActions(
      repository: repository,
      clock: FakeClock(DateTime.utc(2026, 10, 19, 12)),
    );
    final newer = original.corrected(
      startUtc: DateTime.utc(2026, 10, 19, 8, 10),
      endUtc: DateTime.utc(2026, 10, 19, 9),
    );
    await repository.put(newer);
    expect(await actions.delete(original), isFalse);
    expect(
      await actions.correct(
        original,
        startUtc: DateTime.utc(2026, 10, 19, 8, 20),
        endUtc: DateTime.utc(2026, 10, 19, 9),
      ),
      isFalse,
    );
    expect((await repository.readSessions()).single, newer);
  });

  test('invalid and future finished ranges cannot mutate history', () async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final actions = SleepActions(
      repository: repository,
      clock: FakeClock(DateTime.utc(2026, 10, 19, 12)),
    );
    await expectLater(
      actions.addCompleted(
        DateTime.utc(2026, 10, 19, 10),
        DateTime.utc(2026, 10, 19, 9),
      ),
      throwsArgumentError,
    );
    await expectLater(
      actions.addCompleted(
        DateTime.utc(2026, 10, 19, 10),
        DateTime.utc(2026, 10, 19, 13),
      ),
      throwsArgumentError,
    );
    await expectLater(
      actions.addCompleted(
        DateTime.utc(2026, 10, 17, 9),
        DateTime.utc(2026, 10, 18, 10),
      ),
      throwsArgumentError,
    );
    expect(await repository.readSessions(), isEmpty);
  });

  test('overlap is preserved as two records for review', () async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    var counter = 0;
    final actions = SleepActions(
      repository: repository,
      clock: FakeClock(DateTime.utc(2026, 10, 19, 12)),
      newId: () => 'id-${counter++}',
    );
    expect(
      await actions.addCompleted(
        DateTime.utc(2026, 10, 19, 8),
        DateTime.utc(2026, 10, 19, 9),
      ),
      isTrue,
    );
    expect(
      await actions.addCompleted(
        DateTime.utc(2026, 10, 19, 8, 30),
        DateTime.utc(2026, 10, 19, 9, 30),
      ),
      isTrue,
    );
    expect(await repository.readSessions(), hasLength(2));
  });
}
