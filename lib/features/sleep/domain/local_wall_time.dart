/// Convert a caregiver's civil date and minute to *all* corresponding UTC
/// instants. Local constructors can silently normalize spring-forward gaps or
/// pick one side of a fall-back fold, so they must not be used for input.
///
/// [toWall] normally calls `utc.toLocal()`. Inject `TZDateTime.from` for
/// deterministic IANA-zone tests (or a future explicit household zone).
final class LocalWallTime {
  const LocalWallTime({this.toWall = _deviceWall});

  final DateTime Function(DateTime utc) toWall;

  static DateTime _deviceWall(DateTime utc) => utc.toLocal();

  List<WallTimeCandidate> candidates({
    required DateTime date,
    required int hour,
    required int minute,
  }) {
    final civil = DateTime.utc(date.year, date.month, date.day, hour, minute);
    // Sample the actual offset on either side of the requested wall time.
    // An hourly grid across four days catches normal and unusual DST changes
    // without assuming that every transition changes the offset by one hour.
    final offsets = <Duration>{};
    for (var step = -48; step <= 48; step++) {
      final wall = toWall(civil.add(Duration(hours: step)));
      offsets.add(wall.timeZoneOffset);
    }

    final results = <WallTimeCandidate>[];
    for (final offset in offsets) {
      final instant = civil.subtract(offset);
      final back = toWall(instant);
      if (back.year == date.year &&
          back.month == date.month &&
          back.day == date.day &&
          back.hour == hour &&
          back.minute == minute) {
        results.add(WallTimeCandidate(instant, offset, back.timeZoneName));
      }
    }
    results.sort((a, b) => a.utc.compareTo(b.utc));
    return List.unmodifiable(results);
  }
}

final class WallTimeCandidate {
  const WallTimeCandidate(this.utc, this.offset, this.zoneName);

  final DateTime utc;
  final Duration offset;
  final String zoneName;

  String get description {
    final minutes = offset.inMinutes.abs();
    final sign = offset.isNegative ? '-' : '+';
    final hours = (minutes ~/ 60).toString().padLeft(2, '0');
    final remainder = (minutes % 60).toString().padLeft(2, '0');
    return '$zoneName (UTC$sign$hours:$remainder)';
  }
}
