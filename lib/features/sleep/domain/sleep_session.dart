/// A single continuous interval. End is exclusive; null means in progress.
final class SleepSession {
  SleepSession({
    required this.id,
    required this.startedAtUtc,
    required this.endedAtUtc,
  }) {
    if (!startedAtUtc.isUtc || (endedAtUtc != null && !endedAtUtc!.isUtc)) {
      throw ArgumentError('Session timestamps must be UTC instants.');
    }
    if (endedAtUtc != null && !endedAtUtc!.isAfter(startedAtUtc)) {
      throw ArgumentError('A completed sleep must end after it starts.');
    }
  }

  final String id;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;

  bool get isActive => endedAtUtc == null;

  SleepSession finish(DateTime atUtc) =>
      SleepSession(id: id, startedAtUtc: startedAtUtc, endedAtUtc: atUtc);
}
