import 'dart:async';

import '../domain/sleep_repository.dart';
import '../domain/sleep_session.dart';

/// Intentionally volatile. No production UI must call this "saved" or "synced".
final class PreviewSleepRepository implements SleepRepository {
  final Map<String, SleepSession> _sessions = {};
  final StreamController<List<SleepSession>> _changes =
      StreamController<List<SleepSession>>.broadcast(sync: true);

  List<SleepSession> get _snapshot {
    final sessions = _sessions.values.toList()
      ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
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

  void dispose() => _changes.close();
}
