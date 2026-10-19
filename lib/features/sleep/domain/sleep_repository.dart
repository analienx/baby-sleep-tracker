import 'sleep_ledger.dart';
import 'sleep_session.dart';

enum StoragePhase { preview, opening, cached, pending, synced, failed }

final class SleepStorageStatus {
  const SleepStorageStatus(this.phase, {this.detail});

  final StoragePhase phase;
  final String? detail;
}

/// The source of sessions can be replaced without changing presentation code.
/// F0 uses volatile preview storage; F1/F2 will use Firestore's offline cache.
abstract interface class SleepRepository {
  Stream<List<SleepSession>> watchSessions();
  Future<List<SleepSession>> readSessions();
  Future<void> put(SleepSession session);
  Future<void> remove(String id);
  Stream<SleepStorageStatus> watchStorageStatus();
  Stream<List<SleepConflict>> watchConflicts();
}
