import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../domain/sleep_ledger.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_session.dart';

/// Immutable operation journal shared by the synthetic development adapter
/// and the F2 private family scope. The legacy dev path must never be enabled
/// against a production Firebase project.
/// The authoritative record is the immutable operation collection: clients
/// create unique documents instead of updating the same session document.
final class FirestoreSleepRepository implements SleepRepository {
  FirestoreSleepRepository({
    required FirebaseFirestore firestore,
    required String syntheticUserId,
    String Function()? newId,
  }) : _operations = firestore
           .collection('dev_users')
           .doc(syntheticUserId)
           .collection('operations'),
       _syntheticUserId = syntheticUserId,
       _newId = newId ?? const Uuid().v4 {
    _subscribe();
  }

  /// Creates a household-scoped repository, with actor enforced by Rules.
  FirestoreSleepRepository.family({
    required FirebaseFirestore firestore,
    required String familyId,
    required String babyId,
    required String actorId,
    String Function()? newId,
  }) : _operations = firestore
           .collection('families')
           .doc(familyId)
           .collection('babies')
           .doc(babyId)
           .collection('operations'),
       _syntheticUserId = actorId,
       _newId = newId ?? const Uuid().v4 {
    _subscribe();
  }

  final CollectionReference<Map<String, dynamic>> _operations;
  final String _syntheticUserId;
  final String Function() _newId;
  final StreamController<List<SleepSession>> _sessionChanges =
      StreamController.broadcast(sync: true);
  final StreamController<SleepStorageStatus> _storageChanges =
      StreamController.broadcast(sync: true);
  final StreamController<List<SleepConflict>> _conflictChanges =
      StreamController.broadcast(sync: true);
  final Completer<void> _firstSnapshot = Completer<void>();
  final Map<String, Completer<void>> _localWrites = {};
  late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _subscription;
  Timer? _retryTimer;
  bool _disposed = false;

  void _subscribe() {
    _subscription = _operations
        .snapshots(includeMetadataChanges: true)
        .listen(_onSnapshot, onError: _onError);
  }

  List<SleepOperation> _lastOperations = const [];
  SleepLedgerResult _projection = const SleepLedgerResult(
    sessions: [],
    conflicts: [],
  );
  SleepStorageStatus _status = const SleepStorageStatus(StoragePhase.opening);
  Object? _listenerError;
  Object? _lastWriteError;
  bool _hasSnapshot = false;
  bool _fromCache = true;
  bool _hasPendingWrites = false;
  int _quarantineCount = 0;

  void _updateStatus() {
    _status = _listenerError != null
        ? const SleepStorageStatus(
            StoragePhase.failed,
            detail:
                'Live updates unavailable. Showing last known history. '
                'Check your connection and family access.',
          )
        : _quarantineCount > 0
        ? SleepStorageStatus(
            StoragePhase.failed,
            detail:
                '$_quarantineCount incomplete or invalid record group(s) '
                'need attention. Other sleep records remain available.',
          )
        : _lastWriteError != null
        ? const SleepStorageStatus(
            StoragePhase.failed,
            detail:
                'A previous update was rejected by the server. '
                'History remains available, but this change was not synced.',
          )
        : SleepStorageStatus(
            _hasPendingWrites
                ? StoragePhase.pending
                : _fromCache
                ? StoragePhase.cached
                : StoragePhase.synced,
          );
    _storageChanges.add(_status);
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      final operations = <SleepOperation>[];
      final invalidDocumentIds = <String>[];
      for (final doc in snapshot.docs) {
        try {
          operations.add(_decode(doc.id, doc.data()));
        } on FormatException {
          invalidDocumentIds.add(doc.id);
        } on ArgumentError {
          invalidDocumentIds.add(doc.id);
        } on TypeError {
          invalidDocumentIds.add(doc.id);
        } on StateError {
          invalidDocumentIds.add(doc.id);
        }
      }
      // A bad document or a temporarily missing offline ancestor can never
      // hide the rest of a family's timeline. Do not modify or delete bad ops:
      // retain the immutable audit record for forensic repair.
      final projection = SleepLedger.project(operations);
      _lastOperations = operations;
      _projection = projection;
      _quarantineCount =
          invalidDocumentIds.length + projection.quarantinedSessionIds.length;
      _hasSnapshot = true;
      _listenerError =
          null; // Fresh snapshot recovers previous listener errors.
      _fromCache = snapshot.metadata.isFromCache;
      _hasPendingWrites = snapshot.metadata.hasPendingWrites;
      _updateStatus();
      _sessionChanges.add(projection.sessions);
      _conflictChanges.add(projection.conflicts);
      if (!_firstSnapshot.isCompleted) _firstSnapshot.complete();

      final observedIds = snapshot.docs.map((d) => d.id).toSet();
      for (final entry in _localWrites.entries.toList()) {
        if (observedIds.contains(entry.key)) {
          _localWrites.remove(entry.key);
          if (!entry.value.isCompleted) entry.value.complete();
        }
      }
    } catch (error, stack) {
      _onError(error, stack);
    }
  }

  void _onWriteError(Object error, StackTrace stack) {
    _lastWriteError = error;
    _updateStatus();
  }

  void _onError(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    _listenerError = error;
    _updateStatus();
    if (!_firstSnapshot.isCompleted) _firstSnapshot.complete();
    // The last valid projection remains accessible for readSessions().
    // A subsequent valid snapshot clears the listener error.
    _sessionChanges.addError(error, stack);
    _conflictChanges.addError(error, stack);
    for (final writer in _localWrites.values) {
      if (!writer.isCompleted) writer.completeError(error, stack);
    }
    _localWrites.clear();
    // Terminal stream errors may close the Firestore subscription. Recreate
    // it after a bounded delay; a good snapshot cancels the pending retry.
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () async {
      if (_disposed) return;
      await _subscription.cancel();
      if (_disposed) return;
      _subscribe();
    });
  }

  SleepOperation _decode(String id, Map<String, dynamic> value) {
    if (value['schemaVersion'] != 1 ||
        value['actorId'] is! String ||
        value['sessionId'] is! String ||
        value['deleted'] is! bool ||
        value['parentIds'] is! List ||
        value['startedAtUtc'] is! Timestamp ||
        value['recordedAtUtc'] is! Timestamp) {
      throw FormatException('Invalid sleep operation: $id');
    }
    final end = value['endedAtUtc'];
    if (end != null && end is! Timestamp) {
      throw FormatException('Invalid sleep end in $id');
    }
    return SleepOperation(
      id: id,
      actorId: value['actorId'] as String,
      parentIds: (value['parentIds'] as List).cast<String>(),
      recordedAtUtc: (value['recordedAtUtc'] as Timestamp).toDate().toUtc(),
      deleted: value['deleted'] as bool,
      session: SleepSession(
        id: value['sessionId'] as String,
        startedAtUtc: (value['startedAtUtc'] as Timestamp).toDate().toUtc(),
        endedAtUtc: (end as Timestamp?)?.toDate().toUtc(),
      ),
    );
  }

  Map<String, dynamic> _encode(SleepOperation op) => {
    'schemaVersion': 1,
    'actorId': op.actorId,
    'sessionId': op.session.id,
    'parentIds': op.parentIds,
    'deleted': op.deleted,
    'recordedAtUtc': Timestamp.fromDate(op.recordedAtUtc),
    'startedAtUtc': Timestamp.fromDate(op.session.startedAtUtc),
    'endedAtUtc': op.session.endedAtUtc == null
        ? null
        : Timestamp.fromDate(op.session.endedAtUtc!),
  };

  @override
  Stream<List<SleepSession>> watchSessions() => Stream.multi((listener) {
    final subscription = _sessionChanges.stream.listen(
      listener.add,
      onError: listener.addError,
    );
    if (_hasSnapshot) {
      listener.add(_projection.sessions);
    }
    listener.onCancel = subscription.cancel;
  });

  @override
  Stream<SleepStorageStatus> watchStorageStatus() => Stream.multi((listener) {
    final subscription = _storageChanges.stream.listen(listener.add);
    listener.add(_status);
    listener.onCancel = subscription.cancel;
  });

  @override
  Stream<List<SleepConflict>> watchConflicts() => Stream.multi((listener) {
    final subscription = _conflictChanges.stream.listen(
      listener.add,
      onError: listener.addError,
    );
    if (_hasSnapshot) {
      listener.add(_projection.conflicts);
    }
    listener.onCancel = subscription.cancel;
  });

  @override
  Future<List<SleepSession>> readSessions() async {
    await _firstSnapshot.future;
    if (!_hasSnapshot) throw StateError('No sleep cache is available.');
    return _projection.sessions;
  }

  @override
  Future<void> put(SleepSession session) => _append(session, deleted: false);

  @override
  Future<void> remove(String id) async {
    await readSessions();
    final matching = _projection.sessions.where((s) => s.id == id).toList();
    if (matching.length != 1) {
      throw StateError('Cannot remove a missing or conflicted session.');
    }
    await _append(matching.single, deleted: true);
  }

  @override
  Future<void> resolveConflict(
    SleepConflict conflict,
    SleepSession? selected,
  ) async {
    await readSessions();
    final current = [
      for (final item in _projection.conflicts)
        if (item.sessionId == conflict.sessionId) item,
    ];
    if (current.length != 1 ||
        current.single.heads.length != conflict.heads.length ||
        !current.single.heads
            .map((op) => op.id)
            .toSet()
            .containsAll(conflict.heads.map((op) => op.id))) {
      throw StateError('The competing revisions changed. Review them again.');
    }
    if (selected != null && selected.id != conflict.sessionId) {
      throw ArgumentError('Resolution must keep the same session ID.');
    }
    final snapshot = selected ?? conflict.heads.first.session;
    await _append(
      snapshot,
      deleted: selected == null,
      resolutionParents: current.single.heads.map((op) => op.id).toList(),
    );
  }

  Future<void> _append(
    SleepSession session, {
    required bool deleted,
    List<String>? resolutionParents,
  }) async {
    await readSessions();
    final existing = _lastOperations.where((op) => op.session.id == session.id);
    final referenced = existing.expand((op) => op.parentIds).toSet();
    final heads = [
      for (final op in existing)
        if (!referenced.contains(op.id)) op.id,
    ];
    if (heads.length > 1 && resolutionParents == null) {
      throw StateError('Competing offline edits need explicit resolution.');
    }
    if (resolutionParents != null &&
        (heads.length < 2 ||
            heads.length != resolutionParents.length ||
            !heads.toSet().containsAll(resolutionParents))) {
      throw StateError('Conflict heads changed; review again.');
    }
    if (deleted && heads.isEmpty) {
      throw StateError('Cannot delete an unknown sleep session.');
    }
    final id = _newId();
    final operation = SleepOperation(
      id: id,
      actorId: _syntheticUserId,
      session: session,
      parentIds: resolutionParents ?? heads,
      recordedAtUtc: DateTime.now().toUtc(),
      deleted: deleted,
    );
    final locallyVisible = Completer<void>();
    _localWrites[id] = locallyVisible;

    // A Firestore set() Future represents server acknowledgement and can stay
    // unresolved indefinitely offline. Instead, wait for the *local snapshot*
    // containing the immutable op; separately surface any later server error.
    unawaited(
      _operations
          .doc(id)
          .set(_encode(operation))
          .then(
            (_) {
              // Successful server acknowledgement of a later command may
              // clear a previous rejected write. Cache metadata still controls
              // whether an operation can be called synced.
              _lastWriteError = null;
              _updateStatus();
            },
            onError: (Object error, StackTrace stack) {
              final pending = _localWrites.remove(id);
              if (pending != null && !pending.isCompleted) {
                pending.completeError(error, stack);
              }
              // A single denied write MUST NOT poison unrelated read access.
              _onWriteError(error, stack);
            },
          ),
    );
    try {
      await locallyVisible.future.timeout(const Duration(seconds: 10));
    } finally {
      _localWrites.remove(id);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _subscription.cancel();
    await _sessionChanges.close();
    await _storageChanges.close();
    await _conflictChanges.close();
  }
}
