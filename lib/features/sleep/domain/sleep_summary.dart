import 'sleep_session.dart';

/// UTC interval arithmetic. Overlaps are merged so minutes cannot be counted
/// twice, and sessions crossing midnight remain a single source record.
final class SleepSummary {
  const SleepSummary({
    required this.sleep,
    required this.sessionCount,
    required this.mergedIntervals,
    required this.overlappingSessionIds,
  });

  final Duration sleep;
  final int sessionCount;
  final List<({DateTime start, DateTime end})> mergedIntervals;
  final Set<String> overlappingSessionIds;
  bool get hasOverlap => overlappingSessionIds.isNotEmpty;

  static SleepSummary rolling24Hours(
    Iterable<SleepSession> sessions,
    DateTime nowUtc,
  ) {
    if (!nowUtc.isUtc) throw ArgumentError('nowUtc must be a UTC instant.');
    final start = nowUtc.subtract(const Duration(hours: 24));
    return between(sessions, fromUtc: start, toUtc: nowUtc);
  }

  /// Clip to [fromUtc, toUtc), merge intersecting intervals in O(n log n),
  /// and retain the original IDs of overlapping records for correction.
  static SleepSummary between(
    Iterable<SleepSession> sessions, {
    required DateTime fromUtc,
    required DateTime toUtc,
  }) {
    if (!fromUtc.isUtc || !toUtc.isUtc || !toUtc.isAfter(fromUtc)) {
      throw ArgumentError('Expected an increasing UTC interval.');
    }
    final clipped = <({String id, DateTime start, DateTime end})>[];
    var count = 0;

    for (final session in sessions) {
      final end = session.endedAtUtc ?? toUtc;
      final left = session.startedAtUtc.isBefore(fromUtc)
          ? fromUtc
          : session.startedAtUtc;
      final right = end.isAfter(toUtc) ? toUtc : end;
      if (!right.isAfter(left)) continue;
      count++;
      clipped.add((id: session.id, start: left, end: right));
    }

    clipped.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({DateTime start, DateTime end})>[];
    final overlaps = <String>{};
    DateTime? cursorStart;
    DateTime? cursorEnd;
    var groupIds = <String>[];
    for (final interval in clipped) {
      if (cursorStart == null) {
        cursorStart = interval.start;
        cursorEnd = interval.end;
        groupIds = [interval.id];
      } else if (interval.start.isBefore(cursorEnd!)) {
        overlaps.addAll(groupIds);
        overlaps.add(interval.id);
        groupIds.add(interval.id);
        if (interval.end.isAfter(cursorEnd)) cursorEnd = interval.end;
      } else {
        merged.add((start: cursorStart, end: cursorEnd));
        cursorStart = interval.start;
        cursorEnd = interval.end;
        groupIds = [interval.id];
      }
    }
    if (cursorStart != null) {
      merged.add((start: cursorStart, end: cursorEnd!));
    }
    final total = merged.fold<Duration>(
      Duration.zero,
      (sum, interval) => sum + interval.end.difference(interval.start),
    );
    return SleepSummary(
      sleep: total,
      sessionCount: count,
      mergedIntervals: List.unmodifiable(merged),
      overlappingSessionIds: Set.unmodifiable(overlaps),
    );
  }
}
