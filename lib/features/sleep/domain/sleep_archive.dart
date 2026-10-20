import 'sleep_ledger.dart';
import 'sleep_session.dart';

/// A single repository snapshot. Accepted sessions alone are insufficient for
/// lossless recovery of concurrent edits, deletes and revision ancestry.
final class SleepArchive {
  const SleepArchive({
    required this.sessions,
    this.operations = const [],
    this.conflicts = const [],
    this.quarantinedSessionIds = const [],
    this.invalidOperationIds = const [],
    this.hasJournal = false,
    this.cloudConfirmed = false,
  });

  final List<SleepSession> sessions;
  final List<SleepOperation> operations;
  final List<SleepConflict> conflicts;
  final List<String> quarantinedSessionIds;

  /// Malformed server document IDs omitted from the decoded revision graph.
  /// Their presence explicitly prevents a full-fidelity backup claim.
  final List<String> invalidOperationIds;
  final bool hasJournal;
  final bool cloudConfirmed;

  bool get isComplete =>
      hasJournal &&
      cloudConfirmed &&
      quarantinedSessionIds.isEmpty &&
      invalidOperationIds.isEmpty;
}

/// Optional repository capability. The volatile F0 preview cannot promise
/// immutable operation history, but the family Firestore adapter can.
abstract interface class SleepArchiveSource {
  Future<SleepArchive> readArchive();
}
