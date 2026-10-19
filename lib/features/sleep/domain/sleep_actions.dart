import 'package:uuid/uuid.dart';

import '../../../app/clock.dart';
import 'sleep_repository.dart';
import 'sleep_session.dart';
import 'sleep_ledger.dart';

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
  ({String sessionId, SleepSession? before, SleepSession? after})? _lastChange;
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
        _lastChange = (sessionId: next.id, before: active.first, after: next);
      } else {
        if (command == _Command.stop) return false;
        final next = SleepSession(
          id: _newId(),
          startedAtUtc: clock.nowUtc.subtract(backdate),
          endedAtUtc: null,
        );
        await repository.put(next);
        _lastChange = (sessionId: next.id, before: null, after: next);
      }
      return true;
    } finally {
      _working = false;
    }
  }

  Future<bool> addCompleted(DateTime startUtc, DateTime endUtc) async {
    if (_working) return false;
    _working = true;
    try {
      _validateTime(startUtc, endUtc);
      final session = SleepSession(
        id: _newId(),
        startedAtUtc: startUtc,
        endedAtUtc: endUtc,
      );
      await repository.put(session);
      _lastChange = (sessionId: session.id, before: null, after: session);
      return true;
    } finally {
      _working = false;
    }
  }

  Future<bool> correct(
    SleepSession expected, {
    required DateTime startUtc,
    required DateTime? endUtc,
  }) async {
    if (_working) return false;
    _working = true;
    try {
      _validateTime(startUtc, endUtc);
      if (!await _isCurrent(expected)) return false;
      final updated = expected.corrected(startUtc: startUtc, endUtc: endUtc);
      if (updated == expected) return false;
      await repository.put(updated);
      _lastChange = (sessionId: expected.id, before: expected, after: updated);
      return true;
    } finally {
      _working = false;
    }
  }

  Future<bool> delete(SleepSession expected) async {
    if (_working) return false;
    _working = true;
    try {
      if (!await _isCurrent(expected)) return false;
      await repository.remove(expected.id);
      _lastChange = (sessionId: expected.id, before: expected, after: null);
      return true;
    } finally {
      _working = false;
    }
  }

  Future<bool> resolveConflict(
    SleepConflict conflict,
    SleepSession? selected,
  ) async {
    if (_working) return false;
    _working = true;
    try {
      await repository.resolveConflict(conflict, selected);
      _lastChange = null; // Reconciliation has its own audit history.
      return true;
    } finally {
      _working = false;
    }
  }

  void _validateTime(DateTime start, DateTime? end) {
    if (!start.isUtc || (end != null && !end.isUtc)) {
      throw ArgumentError('Record times must be UTC.');
    }
    if (!start.isBefore(clock.nowUtc) ||
        (end != null && end.isAfter(clock.nowUtc))) {
      throw ArgumentError('Sleep times cannot be in the future.');
    }
    if (end != null) {
      SleepSession(id: 'validation', startedAtUtc: start, endedAtUtc: end);
    }
  }

  Future<bool> _isCurrent(SleepSession expected) async {
    final records = await repository.readSessions();
    return records.any((session) => session == expected);
  }

  /// One-step reversal. Verify the record has not changed since our command:
  /// Undo is rejected if another editor modified the record in the meantime.
  Future<bool> undo() async {
    if (_working || _lastChange == null) return false;
    _working = true;
    try {
      final change = _lastChange!;
      final current = await repository.readSessions();
      if (change.after == null) {
        if (current.any((item) => item.id == change.sessionId)) return false;
      } else if (!current.any((item) => item == change.after)) {
        return false;
      }
      final conflicts = await repository.watchConflicts().first;
      if (conflicts.any((item) => item.sessionId == change.sessionId)) {
        return false;
      }
      if (change.before == null) {
        await repository.remove(change.sessionId);
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
