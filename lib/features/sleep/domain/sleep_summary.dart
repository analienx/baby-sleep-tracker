import 'sleep_session.dart';

/// UTC interval arithmetic. Overlaps are merged so minutes cannot be counted
/// twice, and sessions crossing midnight remain a single source record.
final class SleepSummary {
  const SleepSummary({required this.sleep, required this.sessionCount});

  final Duration sleep;
  final int sessionCount;

  static SleepSummary rolling24Hours(
    Iterable<SleepSession> sessions,
    DateTime nowUtc,
  ) {
    final start = nowUtc.subtract(const Duration(hours: 24));
    final clipped = <({DateTime start, DateTime end})>[];
    var count = 0;

    for (final session in sessions) {
      final end = session.endedAtUtc ?? nowUtc;
      final left = session.startedAtUtc.isBefore(start)
          ? start
          : session.startedAtUtc;
      final right = end.isAfter(nowUtc) ? nowUtc : end;
      if (!right.isAfter(left)) continue;
      count++;
      clipped.add((start: left, end: right));
    }

    clipped.sort((a, b) => a.start.compareTo(b.start));
    var total = Duration.zero;
    DateTime? cursorStart;
    DateTime? cursorEnd;
    for (final interval in clipped) {
      if (cursorStart == null) {
        cursorStart = interval.start;
        cursorEnd = interval.end;
      } else if (!interval.start.isAfter(cursorEnd!)) {
        if (interval.end.isAfter(cursorEnd)) cursorEnd = interval.end;
      } else {
        total += cursorEnd.difference(cursorStart);
        cursorStart = interval.start;
        cursorEnd = interval.end;
      }
    }
    if (cursorStart != null) total += cursorEnd!.difference(cursorStart);
    return SleepSummary(sleep: total, sessionCount: count);
  }
}
