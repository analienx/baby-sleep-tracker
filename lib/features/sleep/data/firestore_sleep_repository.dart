import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../domain/sleep_ledger.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_session.dart';

/// Emulator-only F1 repository, intentionally independent of the F2 household
/// schema. Never use this path with a production Firebase project or child data.
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
    _subscription = _operations
        .snapshots(includeMetadataChanges: true)
        .listen(_onSnapshot, onError: _onError);
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
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _subscription;

  List<SleepOperation> _lastOperations = const [];
  SleepLedgerResult _projection = const SleepLedgerResult(
    sessions: [],
    conflicts: [],
  );
  SleepStorageStatus _status = const SleepStorageStatus(StoragePhase.opening);
  Object? _error;

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    try {
      final operations = <SleepOperation>[
        for (final doc in snapshot.docs) _decode(doc.id, doc.data()),
      ];
      final projection = SleepLedger.project(operations);
      _lastOperations = operations;
      _projection = projection;
      // A rejected queued write can disappear from subsequent snapshots.
      // Keep its failure visible rather than mislabelling the rollback synced.
      if (_error == null) {
        _status = SleepStorageStatus(
          snapshot.metadata.hasPendingWrites
              ? StoragePhase.pending
              : snapshot.metadata.isFromCache
              ? StoragePhase.cached
              : StoragePhase.synced,
        );
      }
      _sessionChanges.add(projection.sessions);
      _conflictChanges.add(projection.conflicts);
      _storageChanges.add(_status);
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

  void _onError(Object error, [StackTrace? stack]) {
    _error = error;
    _status = const SleepStorageStatus(
      StoragePhase.failed,
      detail:
          'Storage or synchronization failed. Do not assume data was saved.',
    );
    _storageChanges.add(_status);
    _sessionChanges.addError(error, stack);
    _conflictChanges.addError(error, stack);
    if (!_firstSnapshot.isCompleted) {
      _firstSnapshot.completeError(error, stack);
    }
    for (final writer in _localWrites.values) {
      if (!writer.isCompleted) writer.completeError(error, stack);
    }
    _localWrites.clear();
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
    if (_firstSnapshot.isCompleted && _error == null) {
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
    if (_firstSnapshot.isCompleted && _error == null) {
      listener.add(_projection.conflicts);
    }
    listener.onCancel = subscription.cancel;
  });

  @override
  Future<List<SleepSession>> readSessions() async {
    await _firstSnapshot.future;
    if (_error != null) throw StateError('Sleep cache is unavailable.');
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
            (_) {},
            onError: (Object error, StackTrace stack) {
              final pending = _localWrites.remove(id);
              if (pending != null && !pending.isCompleted) {
                pending.completeError(error, stack);
              }
              _onError(error, stack);
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
    await _subscription.cancel();
    await _sessionChanges.close();
    await _storageChanges.close();
    await _conflictChanges.close();
  }
}
