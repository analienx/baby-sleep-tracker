import 'package:timezone/timezone.dart' as tz;

import 'sleep_session.dart';
import 'sleep_summary.dart';

/// A civil calendar date in a particular display time zone (not a UTC day).
final class SleepDay implements Comparable<SleepDay> {
  const SleepDay(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(SleepDay other) => DateTime.utc(
    year,
    month,
    day,
  ).compareTo(DateTime.utc(other.year, other.month, other.day));

  @override
  bool operator ==(Object other) =>
      other is SleepDay &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// Splits the union of actual sleep instants at *local midnight*. A day may
/// contain 23 or 25 hours across DST; never add 24 hours to a local midnight.
final class SleepCalendar {
  static Map<SleepDay, Duration> totalsByLocalDay(
    Iterable<SleepSession> sessions, {
    required DateTime fromUtc,
    required DateTime toUtc,
    required tz.Location zone,
  }) {
    final merged = SleepSummary.between(
      sessions,
      fromUtc: fromUtc,
      toUtc: toUtc,
    ).mergedIntervals;
    final totals = <SleepDay, Duration>{};

    for (final interval in merged) {
      var cursor = interval.start;
      while (cursor.isBefore(interval.end)) {
        final local = tz.TZDateTime.from(cursor, zone);
        final day = SleepDay(local.year, local.month, local.day);
        final nextMidnight = tz.TZDateTime(
          zone,
          local.year,
          local.month,
          local.day + 1,
        ).toUtc();
        if (!nextMidnight.isAfter(cursor)) {
          throw StateError('Non-increasing civil midnight in ${zone.name}.');
        }
        final end = interval.end.isBefore(nextMidnight)
            ? interval.end
            : nextMidnight;
        totals.update(
          day,
          (previous) => previous + end.difference(cursor),
          ifAbsent: () => end.difference(cursor),
        );
        cursor = end;
      }
    }
    final ordered = totals.keys.toList()..sort();
    return Map.unmodifiable({for (final day in ordered) day: totals[day]!});
  }
}
