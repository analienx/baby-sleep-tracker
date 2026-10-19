import 'sleep_session.dart';

/// Immutable snapshot operation. One ID maps to one Firestore document; a
/// retry writes the *same* ID. Parents encode the revision(s) observed by the
/// editor, so two offline edits can branch rather than silently overwrite.
final class SleepOperation {
  SleepOperation({
    required this.id,
    required this.actorId,
    required this.session,
    required this.recordedAtUtc,
    this.deleted = false,
    List<String> parentIds = const [],
  }) : parentIds = List.unmodifiable(parentIds) {
    if (id.trim().isEmpty || actorId.trim().isEmpty) {
      throw ArgumentError('Operation ID and actor ID must be non-empty.');
    }
    if (!recordedAtUtc.isUtc) {
      throw ArgumentError('Operation time must be a UTC instant.');
    }
    if (parentIds.length != parentIds.toSet().length ||
        parentIds.contains(id) ||
        parentIds.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Operation parents must be unique valid IDs.');
    }
    if (deleted && parentIds.isEmpty) {
      throw ArgumentError('Cannot delete a session before its creation.');
    }
  }

  final String id;
  final String actorId;
  final SleepSession session;
  final DateTime recordedAtUtc;
  final bool deleted;
  final List<String> parentIds;

  bool sameContent(SleepOperation other) =>
      id == other.id &&
      actorId == other.actorId &&
      session == other.session &&
      recordedAtUtc == other.recordedAtUtc &&
      deleted == other.deleted &&
      parentIds.length == other.parentIds.length &&
      parentIds.toSet().containsAll(other.parentIds);
}

final class SleepConflict {
  const SleepConflict({
    required this.sessionId,
    required this.heads,
    required this.commonAncestor,
  });

  final String sessionId;

  /// Every competing revision remains available for user-led resolution.
  final List<SleepOperation> heads;
  final SleepOperation? commonAncestor;
}

final class SleepLedgerResult {
  const SleepLedgerResult({
    required this.sessions,
    required this.conflicts,
    this.quarantinedSessionIds = const [],
  });

  /// Last uncontested state if two writers collide; never arbitrarily LWW.
  final List<SleepSession> sessions;
  final List<SleepConflict> conflicts;

  /// Invalid or incomplete ancestry is preserved in storage but excluded from
  /// the timeline until all referenced operations are available and valid.
  final List<String> quarantinedSessionIds;
  bool get hasConflicts => conflicts.isNotEmpty;
}

/// A deterministic operation-DAG projection. Time is deliberately *not* the
/// ordering key: device clocks can disagree or move backwards. The revision
/// dependency graph decides ancestry, with explicit multi-parent resolutions.
final class SleepLedger {
  static SleepLedgerResult project(Iterable<SleepOperation> input) {
    final groups = <String, Map<String, SleepOperation>>{};
    final ids = <String, SleepOperation>{};
    for (final op in input) {
      final existing = ids[op.id];
      if (existing != null) {
        if (!existing.sameContent(op)) {
          throw StateError('Operation ID ${op.id} has conflicting content.');
        }
        continue; // An identical retry is idempotent.
      }
      ids[op.id] = op;
      groups.putIfAbsent(op.session.id, () => {})[op.id] = op;
    }

    final sessions = <SleepSession>[];
    final conflicts = <SleepConflict>[];
    final quarantined = <String>[];
    for (final entry in groups.entries) {
      try {
        final projected = _projectFamily(entry.key, entry.value);
        sessions.addAll(projected.sessions);
        conflicts.addAll(projected.conflicts);
      } catch (error) {
        // A missing ancestor can be temporary while Firestore's local cache
        // fills; a cyclic or fabricated parent can be permanently invalid.
        // Neither should hide otherwise valid sessions from caregivers.
        if (error is! StateError &&
            error is! ArgumentError &&
            error is! FormatException) {
          rethrow;
        }
        quarantined.add(entry.key);
      }
    }
    sessions.sort((a, b) {
      final byStart = b.startedAtUtc.compareTo(a.startedAtUtc);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    conflicts.sort((a, b) => a.sessionId.compareTo(b.sessionId));
    return SleepLedgerResult(
      sessions: List.unmodifiable(sessions),
      conflicts: List.unmodifiable(conflicts),
      quarantinedSessionIds: List.unmodifiable(quarantined..sort()),
    );
  }

  static ({List<SleepSession> sessions, List<SleepConflict> conflicts})
  _projectFamily(String sessionId, Map<String, SleepOperation> ops) {
    final sessionResults = <SleepSession>[];
    final conflictResults = <SleepConflict>[];
    final referenced = <String>{};
    for (final op in ops.values) {
      for (final parent in op.parentIds) {
        if (!ops.containsKey(parent)) {
          throw StateError(
            'Missing/cross-session parent $parent for ${op.id}.',
          );
        }
        referenced.add(parent);
      }
    }

    // Memoized ancestry both rejects cycles and works if input arrives in
    // arbitrary server order. Each set includes its own revision ID.
    final memo = <String, Set<String>>{};
    final visiting = <String>{};
    Set<String> ancestors(String id) {
      if (memo.containsKey(id)) return memo[id]!;
      if (!visiting.add(id)) throw StateError('Revision cycle at $id.');
      final values = <String>{id};
      for (final parent in ops[id]!.parentIds) {
        values.addAll(ancestors(parent));
      }
      visiting.remove(id);
      memo[id] = values;
      return values;
    }

    for (final id in ops.keys) {
      ancestors(id);
    }
    final heads = [
      for (final id in ops.keys)
        if (!referenced.contains(id)) ops[id]!,
    ]..sort((a, b) => a.id.compareTo(b.id));

    if (heads.length == 1) {
      if (!heads.single.deleted) sessionResults.add(heads.single.session);
    } else {
      final common = Set<String>.from(memo[heads.first.id]!);
      for (final head in heads.skip(1)) {
        common.retainAll(memo[head.id]!);
      }
      // A common ancestor most deeply nested in the DAG has the maximum
      // ancestor count. Tie-break by ID, not clock timestamps.
      final ordered = common.toList()
        ..sort((a, b) {
          final depth = memo[b]!.length.compareTo(memo[a]!.length);
          return depth != 0 ? depth : a.compareTo(b);
        });
      final ancestor = ordered.isEmpty ? null : ops[ordered.first];
      if (ancestor != null && !ancestor.deleted) {
        sessionResults.add(ancestor.session);
      }
      conflictResults.add(
        SleepConflict(
          sessionId: sessionId,
          heads: List.unmodifiable(heads),
          commonAncestor: ancestor,
        ),
      );
    }

    return (sessions: sessionResults, conflicts: conflictResults);
  }
}
