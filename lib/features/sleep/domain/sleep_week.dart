import 'sleep_session.dart';
import 'sleep_summary.dart';

/// A local calendar day. The current day is always partial; a day with no
/// records is *unknown*, not evidence of zero sleep.
final class SleepDayTotal {
  const SleepDayTotal({
    required this.localDate,
    required this.recordedSleep,
    required this.sessionCount,
    required this.hasOverlap,
    required this.isToday,
    required this.dayLength,
  });

  final DateTime localDate;
  final Duration recordedSleep;
  final int sessionCount;
  final bool hasOverlap;
  final bool isToday;
  final Duration dayLength;
  bool get hasRecords => sessionCount > 0;
}

/// Builds seven civil (not 24-hour) days, using UTC instants at local
/// midnight. Injecting the boundary resolver makes DST tests deterministic.
final class SleepWeek {
  static List<SleepDayTotal> lastSevenDays(
    Iterable<SleepSession> sessions,
    DateTime nowUtc, {
    DateTime Function(int year, int month, int day)? localMidnightUtc,
    DateTime? localToday,
  }) {
    if (!nowUtc.isUtc) throw ArgumentError('nowUtc must be UTC.');
    final local = localToday ?? nowUtc.toLocal();
    final midnight =
        localMidnightUtc ??
        (int year, int month, int day) => DateTime(year, month, day).toUtc();
    final days = <SleepDayTotal>[];
    for (var offset = 6; offset >= 0; offset--) {
      // DateTime.utc is used only for civil-date arithmetic, not as a day
      // boundary. This never assumes that a DST day lasts 24 hours.
      final date = DateTime.utc(local.year, local.month, local.day - offset);
      final start = midnight(date.year, date.month, date.day);
      final next = midnight(date.year, date.month, date.day + 1);
      final isToday = offset == 0;
      final end = isToday && nowUtc.isBefore(next) ? nowUtc : next;
      final summary = end.isAfter(start)
          ? SleepSummary.between(sessions, fromUtc: start, toUtc: end)
          : null;
      days.add(
        SleepDayTotal(
          localDate: date,
          recordedSleep: summary?.sleep ?? Duration.zero,
          sessionCount: summary?.sessionCount ?? 0,
          hasOverlap: summary?.hasOverlap ?? false,
          isToday: isToday,
          dayLength: next.difference(start),
        ),
      );
    }
    return List.unmodifiable(days);
  }
}
