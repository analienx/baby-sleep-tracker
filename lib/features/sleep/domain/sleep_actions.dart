import 'package:uuid/uuid.dart';

import '../../../app/clock.dart';
import 'sleep_repository.dart';
import 'sleep_session.dart';

/// Local command serialization. The preview repository is volatile; the
/// immutable Firestore operation journal is the separate F1/F2 durability seam.
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
  ({SleepSession? before, SleepSession after})? _lastChange;
  bool get canUndo => _lastChange != null && !_working;

  Future<bool> toggle() async {
    return _change(backdate: Duration.zero, command: _Command.toggle);
  }

  Future<bool> start({Duration backdate = Duration.zero}) async {
    return _change(backdate: backdate, command: _Command.start);
  }

  Future<bool> stop() async {
    return _change(backdate: Duration.zero, command: _Command.stop);
  }

  Future<bool> _change({
    required Duration backdate,
    required _Command command,
  }) async {
    if (_working) return false;
    if (backdate.isNegative || backdate > const Duration(hours: 24)) {
      throw ArgumentError('Backdate must be between 0 and 24 hours.');
    }
    _working = true;
    try {
      final sessions = await repository.readSessions();
      final active = [
        for (final session in sessions)
          if (session.isActive) session,
      ];
      // Multiple active records indicate a remote/offline conflict. Never
      // choose one arbitrarily and silently close the wrong session.
      if (active.length > 1) return false;
      if (active.isNotEmpty) {
        if (command == _Command.start) return false;
        // No fabricated end before a start if the wall clock moves backwards.
        final now = clock.nowUtc;
        if (!now.isAfter(active.first.startedAtUtc)) return false;
        final next = active.first.finish(now);
        await repository.put(next);
        _lastChange = (before: active.first, after: next);
      } else {
        if (command == _Command.stop) return false;
        final next = SleepSession(
          id: _newId(),
          startedAtUtc: clock.nowUtc.subtract(backdate),
          endedAtUtc: null,
        );
        await repository.put(next);
        _lastChange = (before: null, after: next);
      }
      return true;
    } finally {
      _working = false;
    }
  }

  /// One-step reversal. Verify the record has not changed since our command:
  /// Undo is rejected if another editor modified the record in the meantime.
  Future<bool> undo() async {
    if (_working || _lastChange == null) return false;
    _working = true;
    try {
      final change = _lastChange!;
      final current = await repository.readSessions();
      if (!current.any((item) => item == change.after)) return false;
      if (change.before == null) {
        await repository.remove(change.after.id);
      } else {
        await repository.put(change.before!);
      }
      _lastChange = null;
      return true;
    } finally {
      _working = false;
    }
  }
}

enum _Command { toggle, start, stop }
