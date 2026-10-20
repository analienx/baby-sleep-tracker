import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_week.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('unknown days remain unknown, active current day is partial', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    final week = SleepWeek.lastSevenDays(
      [
        SleepSession(
          id: 'one',
          startedAtUtc: DateTime.utc(2026, 10, 19, 9),
          endedAtUtc: null,
        ),
      ],
      now,
      localToday: DateTime.utc(2026, 10, 19),
      localMidnightUtc: DateTime.utc,
    );
    expect(week, hasLength(7));
    expect(week.first.hasRecords, isFalse);
    expect(week.first.recordedSleep, Duration.zero);
    expect(week.last.isToday, isTrue);
    expect(week.last.sessionCount, 1);
    expect(week.last.recordedSleep, const Duration(hours: 3));
  });

  test('cross-midnight sessions split, overlapping minutes counted once', () {
    final records = [
      SleepSession(
        id: 'cross',
        startedAtUtc: DateTime.utc(2026, 10, 17, 23, 30),
        endedAtUtc: DateTime.utc(2026, 10, 18, 1, 30),
      ),
      SleepSession(
        id: 'overlap',
        startedAtUtc: DateTime.utc(2026, 10, 18, 0, 30),
        endedAtUtc: DateTime.utc(2026, 10, 18, 1),
      ),
    ];
    final week = SleepWeek.lastSevenDays(
      records,
      DateTime.utc(2026, 10, 19, 12),
      localToday: DateTime.utc(2026, 10, 19),
      localMidnightUtc: DateTime.utc,
    );
    expect(week[4].recordedSleep, const Duration(minutes: 30));
    expect(week[5].recordedSleep, const Duration(minutes: 90));
    expect(week[5].sessionCount, 2);
    expect(week[5].hasOverlap, isTrue);
    expect(week.last.hasOverlap, isFalse);
  });

  test('Prague autumn day measures 25 hours and spring day 23 hours', () {
    final zone = tz.getLocation('Europe/Prague');
    DateTime midnight(int y, int m, int d) =>
        tz.TZDateTime(zone, y, m, d).toUtc();

    final autumnStart = midnight(2026, 10, 25);
    final autumnEnd = midnight(2026, 10, 26);
    final autumn = SleepWeek.lastSevenDays(
      [
        SleepSession(
          id: 'autumn-1',
          startedAtUtc: autumnStart,
          endedAtUtc: autumnStart.add(const Duration(hours: 24)),
        ),
        SleepSession(
          id: 'autumn-2',
          startedAtUtc: autumnStart.add(const Duration(hours: 24)),
          endedAtUtc: autumnEnd,
        ),
      ],
      DateTime.utc(2026, 10, 26, 12),
      localToday: DateTime.utc(2026, 10, 26),
      localMidnightUtc: midnight,
    );
    expect(autumn[5].dayLength, const Duration(hours: 25));
    expect(autumn[5].recordedSleep, const Duration(hours: 25));

    final springStart = midnight(2026, 3, 29);
    final springEnd = midnight(2026, 3, 30);
    final spring = SleepWeek.lastSevenDays(
      [
        SleepSession(
          id: 'spring',
          startedAtUtc: springStart,
          endedAtUtc: springEnd,
        ),
      ],
      DateTime.utc(2026, 3, 30, 12),
      localToday: DateTime.utc(2026, 3, 30),
      localMidnightUtc: midnight,
    );
    expect(spring[5].dayLength, const Duration(hours: 23));
    expect(spring[5].recordedSleep, const Duration(hours: 23));
  });

  test('exact local midnight does not pass an empty interval to summary', () {
    final today = DateTime.utc(2026, 10, 19);
    final week = SleepWeek.lastSevenDays(
      const [],
      today,
      localToday: today,
      localMidnightUtc: DateTime.utc,
    );
    expect(week.last.sessionCount, 0);
  });
}
