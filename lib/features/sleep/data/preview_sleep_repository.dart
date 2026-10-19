import 'dart:async';

import '../domain/sleep_ledger.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_session.dart';

/// Intentionally volatile. No production UI must call this "saved" or "synced".
final class PreviewSleepRepository implements SleepRepository {
  final Map<String, SleepSession> _sessions = {};
  final StreamController<List<SleepSession>> _changes =
      StreamController<List<SleepSession>>.broadcast(sync: true);

  List<SleepSession> get _snapshot {
    final sessions = _sessions.values.toList()
      ..sort((a, b) {
        final byStart = b.startedAtUtc.compareTo(a.startedAtUtc);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    return List.unmodifiable(sessions);
  }

  @override
  Stream<List<SleepSession>> watchSessions() => Stream.multi((listener) {
    final subscription = _changes.stream.listen(listener.add);
    listener.add(_snapshot);
    listener.onCancel = subscription.cancel;
  });

  @override
  Future<List<SleepSession>> readSessions() async => _snapshot;

  @override
  Future<void> put(SleepSession session) async {
    _sessions[session.id] = session;
    _changes.add(_snapshot);
  }

  @override
  Future<void> remove(String id) async {
    _sessions.remove(id);
    _changes.add(_snapshot);
  }

  @override
  Future<void> resolveConflict(
    SleepConflict conflict,
    SleepSession? selected,
  ) => Future.error(StateError('Preview history has no revision conflicts.'));

  @override
  Stream<SleepStorageStatus> watchStorageStatus() =>
      Stream.value(const SleepStorageStatus(StoragePhase.preview));

  @override
  Stream<List<SleepConflict>> watchConflicts() => Stream.value(const []);

  void dispose() => _changes.close();
}
