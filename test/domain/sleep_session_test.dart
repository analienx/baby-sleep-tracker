import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only UTC instants are accepted', () {
    expect(
      () => SleepSession(
        id: 'not-utc',
        startedAtUtc: DateTime(2026, 10, 19, 8),
        endedAtUtc: null,
      ),
      throwsArgumentError,
    );
  });

  test('zero and negative durations are rejected', () {
    final start = DateTime.utc(2026, 10, 19, 8);
    for (final end in [start, start.subtract(const Duration(seconds: 1))]) {
      expect(
        () => SleepSession(id: 'invalid', startedAtUtc: start, endedAtUtc: end),
        throwsArgumentError,
      );
    }
  });

  test('continuous sleep can cross midnight', () {
    final start = DateTime.utc(2026, 10, 18, 23, 30);
    final end = DateTime.utc(2026, 10, 19, 1, 15);
    final completed = SleepSession(
      id: 'across-midnight',
      startedAtUtc: start,
      endedAtUtc: null,
    ).finish(end);

    expect(completed.isActive, isFalse);
    expect(
      completed.endedAtUtc!.difference(completed.startedAtUtc),
      const Duration(hours: 1, minutes: 45),
    );
  });

  test('rejects impossible 25-hour sessions and empty IDs', () {
    final start = DateTime.utc(2026, 10, 19, 8);
    expect(
      () => SleepSession(id: ' ', startedAtUtc: start, endedAtUtc: null),
      throwsArgumentError,
    );
    expect(
      () => SleepSession(
        id: '25-hours',
        startedAtUtc: start,
        endedAtUtc: start.add(const Duration(hours: 25)),
      ),
      throwsArgumentError,
    );
  });
}
