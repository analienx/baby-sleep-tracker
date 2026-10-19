import 'package:uuid/uuid.dart';

import '../../../app/clock.dart';
import 'sleep_repository.dart';
import 'sleep_session.dart';

/// F0 preview interaction. Repository calls are serialized on this controller
/// to protect against duplicate taps on a single device. Cross-device
/// reconciliation belongs to F2, not this in-memory prototype.
final class SleepActions {
  SleepActions({
    required this.repository,
    required this.clock,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;

  final SleepRepository repository;
  final Clock clock;
  final String Function() _newId;
  bool _working = false;

  Future<bool> toggle() async {
    if (_working) return false;
    _working = true;
    try {
      final sessions = await repository.readSessions();
      final active = [
        for (final session in sessions)
          if (session.isActive) session,
      ];
      if (active.isNotEmpty) {
        // No fabricated end before a start if the wall clock moves backwards.
        final now = clock.nowUtc;
        if (!now.isAfter(active.first.startedAtUtc)) return false;
        await repository.put(active.first.finish(now));
      } else {
        await repository.put(
          SleepSession(
            id: _newId(),
            startedAtUtc: clock.nowUtc,
            endedAtUtc: null,
          ),
        );
      }
      return true;
    } finally {
      _working = false;
    }
  }
}
