/// A single continuous interval. End is exclusive; null means in progress.
final class SleepSession {
  SleepSession({
    required this.id,
    required this.startedAtUtc,
    required this.endedAtUtc,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A sleep session needs an ID.');
    }
    if (!startedAtUtc.isUtc || (endedAtUtc != null && !endedAtUtc!.isUtc)) {
      throw ArgumentError('Session timestamps must be UTC instants.');
    }
    if (endedAtUtc != null && !endedAtUtc!.isAfter(startedAtUtc)) {
      throw ArgumentError('A completed sleep must end after it starts.');
    }
    if (endedAtUtc != null &&
        endedAtUtc!.difference(startedAtUtc) > const Duration(hours: 24)) {
      throw ArgumentError(
        'A sleep record exceeds 24 hours. Check the date and time.',
      );
    }
  }

  final String id;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;

  bool get isActive => endedAtUtc == null;

  SleepSession finish(DateTime atUtc) =>
      SleepSession(id: id, startedAtUtc: startedAtUtc, endedAtUtc: atUtc);

  SleepSession corrected({required DateTime startUtc, DateTime? endUtc}) =>
      SleepSession(id: id, startedAtUtc: startUtc, endedAtUtc: endUtc);

  @override
  bool operator ==(Object other) =>
      other is SleepSession &&
      id == other.id &&
      startedAtUtc == other.startedAtUtc &&
      endedAtUtc == other.endedAtUtc;

  @override
  int get hashCode => Object.hash(id, startedAtUtc, endedAtUtc);
}
