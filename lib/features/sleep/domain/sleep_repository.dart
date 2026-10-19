import 'sleep_session.dart';

/// The source of sessions can be replaced without changing presentation code.
/// F0 uses volatile preview storage; F1/F2 will use Firestore's offline cache.
abstract interface class SleepRepository {
  Stream<List<SleepSession>> watchSessions();
  Future<List<SleepSession>> readSessions();
  Future<void> put(SleepSession session);
}
