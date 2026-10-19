import 'package:baby_sleep_tracker/features/sleep/domain/sleep_ledger.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:flutter_test/flutter_test.dart';

final morning = DateTime.utc(2026, 10, 19, 8);

SleepOperation op(
  String id, {
  List<String> parents = const [],
  String actor = 'parent-a',
  DateTime? end,
  bool deleted = false,
  DateTime? recordedAt,
}) => SleepOperation(
  id: id,
  actorId: actor,
  parentIds: parents,
  deleted: deleted,
  recordedAtUtc: recordedAt ?? morning,
  session: SleepSession(id: 'sleep-1', startedAtUtc: morning, endedAtUtc: end),
);

void main() {
  test('replay is independent of arrival order and UTC clock skew', () {
    final initial = op('a');
    final finish = op(
      'b',
      parents: ['a'],
      end: morning.add(const Duration(hours: 1)),
      recordedAt: morning.subtract(const Duration(days: 1)),
    );
    final edit = op(
      'c',
      parents: ['b'],
      end: morning.add(const Duration(hours: 2)),
    );
    for (final shuffled in [
      [initial, finish, edit],
      [edit, initial, finish],
      [finish, edit, initial],
    ]) {
      final projected = SleepLedger.project(shuffled);
      expect(projected.hasConflicts, isFalse);
      expect(
        projected.sessions.single.endedAtUtc,
        morning.add(const Duration(hours: 2)),
      );
    }
  });

  test('a duplicate retry is a no-op; ID reuse with altered payload fails', () {
    final initial = op('same');
    expect(SleepLedger.project([initial, initial]).sessions, hasLength(1));
    expect(
      () => SleepLedger.project([
        initial,
        op('same', end: morning.add(const Duration(hours: 1))),
      ]),
      throwsStateError,
    );
  });

  test('concurrent edits preserve common state and both conflict versions', () {
    final initial = op('create');
    final parentA = op(
      'correct-a',
      parents: ['create'],
      end: morning.add(const Duration(minutes: 30)),
    );
    final parentB = op(
      'correct-b',
      parents: ['create'],
      actor: 'parent-b',
      end: morning.add(const Duration(minutes: 50)),
    );
    final result = SleepLedger.project([parentB, parentA, initial]);
    expect(result.sessions.single.isActive, isTrue); // Uncontested base.
    expect(result.conflicts.single.heads.map((h) => h.id), [
      'correct-a',
      'correct-b',
    ]);
    expect(result.conflicts.single.commonAncestor?.id, 'create');

    // A user explicitly resolves the divergence, referencing BOTH heads.
    final resolution = op(
      'resolve',
      parents: ['correct-a', 'correct-b'],
      end: morning.add(const Duration(minutes: 45)),
    );
    final resolved = SleepLedger.project([
      resolution,
      parentB,
      initial,
      parentA,
    ]);
    expect(resolved.hasConflicts, isFalse);
    expect(
      resolved.sessions.single.endedAtUtc,
      morning.add(const Duration(minutes: 45)),
    );
  });

  test(
    'deletion is reversible through a new revision, not physical removal',
    () {
      final base = op('created');
      final deleted = op('deleted', parents: ['created'], deleted: true);
      expect(SleepLedger.project([base, deleted]).sessions, isEmpty);
      final undo = op('undo', parents: ['deleted']);
      expect(SleepLedger.project([undo, base, deleted]).sessions, hasLength(1));
    },
  );

  test('offline delete versus edit remains visible as a conflict', () {
    final base = op('created');
    final removed = op('remove', parents: ['created'], deleted: true);
    final edited = op(
      'edit',
      parents: ['created'],
      actor: 'parent-b',
      end: morning.add(const Duration(minutes: 15)),
    );
    final result = SleepLedger.project([base, removed, edited]);
    expect(result.sessions.single.isActive, isTrue);
    expect(result.hasConflicts, isTrue);
    expect(
      result.conflicts.single.heads.where((op) => op.deleted),
      hasLength(1),
    );
  });

  test(
    'quarantines missing parents and cycles without losing other sleeps',
    () {
      final unrelated = SleepOperation(
        id: 'valid',
        actorId: 'parent-b',
        recordedAtUtc: morning,
        session: SleepSession(
          id: 'unrelated',
          startedAtUtc: morning,
          endedAtUtc: null,
        ),
      );
      final orphan = op('a', parents: ['unknown']);
      final quarantined = SleepLedger.project([orphan, unrelated]);
      expect(quarantined.sessions.single.id, 'unrelated');
      expect(quarantined.quarantinedSessionIds, ['sleep-1']);

      final cyclic = SleepLedger.project([
        unrelated,
        op('a', parents: ['b']),
        op('b', parents: ['a']),
      ]);
      expect(cyclic.sessions.single.id, 'unrelated');
      expect(cyclic.quarantinedSessionIds, ['sleep-1']);

      // Once the missing parent is available, the quarantine repairs itself.
      final recovered = SleepLedger.project([unrelated, orphan, op('unknown')]);
      expect(recovered.sessions, hasLength(2));
      expect(recovered.quarantinedSessionIds, isEmpty);
    },
  );

  test('rejects illegal tombstone and non-UTC times', () {
    expect(() => op('a', deleted: true), throwsArgumentError);
    expect(
      () => SleepOperation(
        id: 'a',
        actorId: 'p',
        session: SleepSession(id: 'a', startedAtUtc: morning, endedAtUtc: null),
        recordedAtUtc: DateTime(2026, 10, 19),
      ),
      throwsArgumentError,
    );
  });

  test('same session ID created independently cannot be silently resolved', () {
    final result = SleepLedger.project([op('a'), op('b', actor: 'parent-b')]);
    expect(result.sessions, isEmpty);
    expect(result.conflicts.single.heads, hasLength(2));
  });
}
