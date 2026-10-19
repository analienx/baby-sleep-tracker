import 'package:baby_sleep_tracker/features/sleep/domain/sleep_calendar.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

SleepSession record(String id, String start, String end) => SleepSession(
  id: id,
  startedAtUtc: DateTime.parse(start).toUtc(),
  endedAtUtc: DateTime.parse(end).toUtc(),
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('DST fall-back day has 25 physical hours in Prague', () {
    final totals = SleepCalendar.totalsByLocalDay(
      [
        record('fall-a', '2026-10-24T22:00:00Z', '2026-10-25T12:00:00Z'),
        record('fall-b', '2026-10-25T12:00:00Z', '2026-10-25T23:00:00Z'),
      ],
      fromUtc: DateTime.utc(2026, 10, 24),
      toUtc: DateTime.utc(2026, 10, 27),
      zone: tz.getLocation('Europe/Prague'),
    );

    expect(totals, {const SleepDay(2026, 10, 25): const Duration(hours: 25)});
  });

  test('spring-forward day has only 23 physical hours', () {
    final totals = SleepCalendar.totalsByLocalDay(
      [record('spring', '2027-03-27T23:00:00Z', '2027-03-28T22:00:00Z')],
      fromUtc: DateTime.utc(2027, 3, 27),
      toUtc: DateTime.utc(2027, 3, 30),
      zone: tz.getLocation('Europe/Prague'),
    );

    expect(totals, {const SleepDay(2027, 3, 28): const Duration(hours: 23)});
  });

  test('overlap is unioned before splitting at midnight and leap day', () {
    final records = [
      record('a', '2028-02-28T22:30:00Z', '2028-02-29T00:30:00Z'),
      record('b', '2028-02-28T23:00:00Z', '2028-02-29T01:00:00Z'),
    ];
    final totals = SleepCalendar.totalsByLocalDay(
      records,
      fromUtc: DateTime.utc(2028, 2, 28),
      toUtc: DateTime.utc(2028, 3, 1),
      zone: tz.getLocation('Europe/Prague'),
    );
    expect(totals, {
      const SleepDay(2028, 2, 28): const Duration(minutes: 30),
      const SleepDay(2028, 2, 29): const Duration(hours: 2),
    });
  });

  test('timezone travel changes civil dates, not elapsed instants', () {
    final data = [
      record('flight', '2026-10-19T22:00:00Z', '2026-10-20T00:00:00Z'),
    ];
    Map<SleepDay, Duration> byZone(String name) =>
        SleepCalendar.totalsByLocalDay(
          data,
          fromUtc: DateTime.utc(2026, 10, 19),
          toUtc: DateTime.utc(2026, 10, 21),
          zone: tz.getLocation(name),
        );
    expect(byZone('Europe/Prague'), {
      const SleepDay(2026, 10, 20): const Duration(hours: 2),
    });
    expect(byZone('America/New_York'), {
      const SleepDay(2026, 10, 19): const Duration(hours: 2),
    });
  });
}
