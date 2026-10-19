import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_summary.dart';
import 'package:flutter_test/flutter_test.dart';

SleepSession session(String id, DateTime start, DateTime? end) =>
    SleepSession(id: id, startedAtUtc: start, endedAtUtc: end);

void main() {
  test('rolling window clips both ends and includes an active session', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    final summary = SleepSummary.rolling24Hours([
      session(
        'a',
        DateTime.utc(2026, 10, 18, 10),
        DateTime.utc(2026, 10, 18, 14),
      ),
      session('b', DateTime.utc(2026, 10, 19, 11, 30), null),
      session(
        'outside',
        DateTime.utc(2026, 10, 17, 11),
        DateTime.utc(2026, 10, 17, 12),
      ),
    ], now);
    expect(summary.sleep, const Duration(hours: 2, minutes: 30));
    expect(summary.sessionCount, 2);
  });

  test('overlaps never inflate the total', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    final summary = SleepSummary.rolling24Hours([
      session(
        'a',
        DateTime.utc(2026, 10, 19, 8),
        DateTime.utc(2026, 10, 19, 10),
      ),
      session(
        'b',
        DateTime.utc(2026, 10, 19, 9),
        DateTime.utc(2026, 10, 19, 11),
      ),
    ], now);
    expect(summary.sleep, const Duration(hours: 3));
    expect(summary.sessionCount, 2);
  });

  test('Prague DST fallback measures instants, not wall clock difference', () {
    // 02:15 CEST and 02:45 CET occur 90 minutes apart on 25 October 2026.
    final start = DateTime.parse('2026-10-25T02:15:00+02:00');
    final end = DateTime.parse('2026-10-25T02:45:00+01:00');
    final summary = SleepSummary.rolling24Hours([
      session('fallback', start, end),
    ], DateTime.utc(2026, 10, 25, 3));
    expect(summary.sleep, const Duration(minutes: 90));
  });

  test('Prague DST spring-forward skips an hour without losing time', () {
    final start = DateTime.parse('2027-03-28T01:30:00+01:00');
    final end = DateTime.parse('2027-03-28T03:30:00+02:00');
    final summary = SleepSummary.rolling24Hours([
      session('spring', start, end),
    ], DateTime.utc(2027, 3, 28, 3));
    expect(summary.sleep, const Duration(hours: 1));
  });

  test('changing device time zone cannot change an elapsed UTC duration', () {
    final start = DateTime.parse('2026-10-19T08:00:00+02:00');
    final end = DateTime.parse('2026-10-19T03:00:00-04:00');
    final summary = SleepSummary.rolling24Hours([
      session('travel', start, end),
    ], DateTime.utc(2026, 10, 19, 12));
    expect(summary.sleep, const Duration(hours: 1));
  });
}
