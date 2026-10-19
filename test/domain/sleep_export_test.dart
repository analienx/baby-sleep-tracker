import 'dart:convert';

import 'package:baby_sleep_tracker/features/sleep/domain/sleep_export.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_archive.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_ledger.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);

  test('JSON round-trips UTC instants, active/null end, and stable order', () {
    final original = [
      SleepSession(
        id: 'later',
        startedAtUtc: DateTime.utc(2026, 10, 19, 11),
        endedAtUtc: null,
      ),
      SleepSession(
        id: 'earlier',
        startedAtUtc: DateTime.utc(2026, 10, 18, 23, 45),
        endedAtUtc: DateTime.utc(2026, 10, 19, 0, 15),
      ),
    ];
    final json = SleepExport.json(original, exportedAtUtc: now);
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    expect(parsed['schemaVersion'], 1);
    expect(parsed['scope'], 'visibleAcceptedSessions');
    expect(parsed['recordCount'], 2);
    final restored = (parsed['sessions'] as List<dynamic>).map((row) {
      final data = row as Map<String, dynamic>;
      return SleepSession(
        id: data['id'] as String,
        startedAtUtc: DateTime.parse(data['startedAtUtc'] as String),
        endedAtUtc: data['endedAtUtc'] == null
            ? null
            : DateTime.parse(data['endedAtUtc'] as String),
      );
    }).toList();
    expect(restored, [original[1], original[0]]);
    expect(restored[1].endedAtUtc, isNull);
  });

  test('CSV exports empty header and properly escapes commas and quotes', () {
    expect(
      SleepExport.csv(const []),
      'schemaVersion,id,startedAtUtc,endedAtUtc\r\n',
    );
    final value = SleepExport.csv([
      SleepSession(
        id: 'a,"b"',
        startedAtUtc: DateTime.utc(2026, 10, 19, 9),
        endedAtUtc: DateTime.utc(2026, 10, 19, 10),
      ),
    ]);
    expect(value, contains('1,"a,""b""",2026-10-19T09:00:00.000Z'));
  });

  test('invalid non-UTC export instant rejected', () {
    expect(
      () => SleepExport.json(const [], exportedAtUtc: DateTime(2026, 10, 19)),
      throwsArgumentError,
    );
  });

  test('CSV neutralizes a formula-like external record ID', () {
    final csv = SleepExport.csv([
      SleepSession(
        id: '=SUM(1,1)',
        startedAtUtc: DateTime.utc(2026, 10, 19, 9),
        endedAtUtc: null,
      ),
    ]);
    expect(csv, contains('"\'=SUM(1,1)"'));
    final withWhitespace = SleepExport.csv([
      SleepSession(
        id: '  =1+1',
        startedAtUtc: DateTime.utc(2026, 10, 19, 9),
        endedAtUtc: null,
      ),
    ]);
    expect(withWhitespace, contains("'  =1+1"));
  });

  test(
    'archive v2 round-trips diverging operation history and deleted heads',
    () {
      final original = SleepSession(
        id: 'nap',
        startedAtUtc: DateTime.utc(2026, 10, 18, 9),
        endedAtUtc: DateTime.utc(2026, 10, 18, 10),
      );
      final changed = original.corrected(
        startUtc: DateTime.utc(2026, 10, 18, 9, 5),
        endUtc: DateTime.utc(2026, 10, 18, 10, 5),
      );
      final root = SleepOperation(
        id: 'root',
        actorId: 'parent-a',
        session: original,
        recordedAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
      );
      final left = SleepOperation(
        id: 'left',
        actorId: 'parent-a',
        session: changed,
        recordedAtUtc: DateTime.utc(2026, 10, 18, 10, 10),
        parentIds: ['root'],
      );
      final right = SleepOperation(
        id: 'right',
        actorId: 'parent-b',
        session: original,
        recordedAtUtc: DateTime.utc(2026, 10, 18, 10, 11),
        parentIds: ['root'],
        deleted: true,
      );
      final projection = SleepLedger.project([right, left, root]);
      final archive = SleepArchive(
        sessions: projection.sessions,
        operations: [right, root, left],
        conflicts: projection.conflicts,
        hasJournal: true,
        cloudConfirmed: true,
      );
      final data = jsonDecode(
        SleepExport.archiveJson(archive, exportedAtUtc: now),
      ) as Map<String, dynamic>;
      expect(data['schemaVersion'], 2);
      expect(data['complete'], isTrue);
      expect(data['operationCount'], 3);
      final operations = (data['operations'] as List<dynamic>).map((item) {
        final op = item as Map<String, dynamic>;
        final session = op['session'] as Map<String, dynamic>;
        return SleepOperation(
          id: op['id'] as String,
          actorId: op['actorId'] as String,
          recordedAtUtc: DateTime.parse(op['recordedAtUtc'] as String),
          parentIds: (op['parentIds'] as List<dynamic>).cast<String>(),
          deleted: op['deleted'] as bool,
          session: SleepSession(
            id: session['id'] as String,
            startedAtUtc: DateTime.parse(session['startedAtUtc'] as String),
            endedAtUtc: session['endedAtUtc'] == null
                ? null
                : DateTime.parse(session['endedAtUtc'] as String),
          ),
        );
      }).toList();
      final replayed = SleepLedger.project(operations);
      expect(replayed.sessions, projection.sessions);
      expect(replayed.conflicts.single.heads.map((h) => h.id).toSet(), {
        'left',
        'right',
      });

      final csv = SleepExport.archiveCsv(archive);
      expect(csv, contains('2,operation,nap,left,parent-a'));
      expect(csv, contains('2,operation,nap,right,parent-b'));
      expect(csv, contains('true'));
    },
  );

  test(
    'preview archive explicitly reports incomplete/no immutable journal',
    () {
      final archive = SleepArchive(
        sessions: [
          SleepSession(
            id: 'local',
            startedAtUtc: DateTime.utc(2026, 10, 19, 9),
            endedAtUtc: null,
          ),
        ],
      );
      final decoded = jsonDecode(
        SleepExport.archiveJson(archive, exportedAtUtc: now),
      ) as Map<String, dynamic>;
      expect(decoded['complete'], isFalse);
      expect(decoded['scope'], 'visibleAcceptedSessionsOnly');
      expect(decoded['operations'], isEmpty);
      expect(SleepExport.archiveCsv(archive), contains('2,metadata'));
      expect(SleepExport.archiveCsv(archive), contains('false,false'));
    },
  );

  test('corrupt operation IDs make cloud archive explicitly incomplete', () {
    const archive = SleepArchive(
      sessions: [],
      hasJournal: true,
      cloudConfirmed: true,
      invalidOperationIds: ['malformed-document'],
    );
    expect(archive.isComplete, isFalse);
    final encoded = jsonDecode(
      SleepExport.archiveJson(archive, exportedAtUtc: now),
    ) as Map<String, dynamic>;
    expect(encoded['complete'], isFalse);
    expect(encoded['invalidOperationIds'], ['malformed-document']);
    expect(SleepExport.archiveCsv(archive), contains('malformed-document'));
  });
}
