import 'dart:convert';

import 'sleep_session.dart';
import 'sleep_archive.dart';
import 'sleep_ledger.dart';

/// Portable projection of the currently accepted, visible sessions.
/// The F1 repository does not expose the immutable audit journal yet.
final class SleepExport {
  static const schemaVersion = 1;
  static const archiveSchemaVersion = 2;

  static List<SleepSession> _ordered(Iterable<SleepSession> sessions) =>
      [...sessions]..sort((a, b) {
        final byStart = a.startedAtUtc.compareTo(b.startedAtUtc);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });

  static String json(
    Iterable<SleepSession> sessions, {
    required DateTime exportedAtUtc,
  }) {
    if (!exportedAtUtc.isUtc) {
      throw ArgumentError('UTC export instant required.');
    }
    final ordered = _ordered(sessions);
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': schemaVersion,
      'scope': 'visibleAcceptedSessions',
      'exportedAtUtc': exportedAtUtc.toIso8601String(),
      'recordCount': ordered.length,
      'sessions': [
        for (final session in ordered)
          {
            'id': session.id,
            'startedAtUtc': session.startedAtUtc.toIso8601String(),
            'endedAtUtc': session.endedAtUtc?.toIso8601String(),
          },
      ],
    });
  }

  static String csv(Iterable<SleepSession> sessions) {
    final rows = <String>[
      'schemaVersion,id,startedAtUtc,endedAtUtc',
      for (final session in _ordered(sessions))
        [
          '$schemaVersion',
          session.id,
          session.startedAtUtc.toIso8601String(),
          session.endedAtUtc?.toIso8601String() ?? '',
        ].map(_escapeCsv).join(','),
    ];
    return '${rows.join('\r\n')}\r\n';
  }

  /// An export suitable for reconstructing the immutable revision DAG, not
  /// just the currently accepted projection. Never label a cached/pending or
  /// quarantined snapshot as a verified complete cloud backup.
  static String archiveJson(
    SleepArchive archive, {
    required DateTime exportedAtUtc,
  }) {
    if (!exportedAtUtc.isUtc) {
      throw ArgumentError('UTC export instant required.');
    }
    final ops = [...archive.operations]..sort((a, b) => a.id.compareTo(b.id));
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': archiveSchemaVersion,
      'scope': archive.hasJournal
          ? 'acceptedSessionsAndOperationJournal'
          : 'visibleAcceptedSessionsOnly',
      'cloudConfirmed': archive.cloudConfirmed,
      'complete': archive.isComplete,
      'exportedAtUtc': exportedAtUtc.toIso8601String(),
      'recordCount': archive.sessions.length,
      'operationCount': ops.length,
      'sessions': [
        for (final record in _ordered(archive.sessions)) _sessionData(record),
      ],
      'operations': [for (final op in ops) _operationData(op)],
      'conflicts': [
        for (final conflict in archive.conflicts)
          {
            'sessionId': conflict.sessionId,
            'headOperationIds': [for (final head in conflict.heads) head.id]
              ..sort(),
            'commonAncestorOperationId': conflict.commonAncestor?.id,
          },
      ],
      'quarantinedSessionIds': archive.quarantinedSessionIds,
      'invalidOperationIds': archive.invalidOperationIds,
    });
  }

  /// A single RFC4180 CSV holds both the accepted projection and each audit
  /// operation, with a row type and an explicit deleted flag. This avoids
  /// silently omitting revisions from the spreadsheet representation.
  static String archiveCsv(SleepArchive archive) {
    final rows = <String>[
      'schemaVersion,recordType,sessionId,operationId,actorId,startedAtUtc,endedAtUtc,recordedAtUtc,deleted,parentIds,conflict,cloudConfirmed,archiveComplete,journalAvailable,invalidOperationIds,quarantinedSessionIds',
      [
        '$archiveSchemaVersion',
        'metadata',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '${archive.cloudConfirmed}',
        '${archive.isComplete}',
        '${archive.hasJournal}',
        jsonEncode(archive.invalidOperationIds),
        jsonEncode(archive.quarantinedSessionIds),
      ].map(_escapeCsv).join(','),
    ];
    final conflictIds = archive.conflicts.map((c) => c.sessionId).toSet();
    for (final session in _ordered(archive.sessions)) {
      rows.add(
        [
          '$archiveSchemaVersion',
          'accepted',
          session.id,
          '',
          '',
          session.startedAtUtc.toIso8601String(),
          session.endedAtUtc?.toIso8601String() ?? '',
          '',
          '',
          '',
          '${conflictIds.contains(session.id)}',
          '${archive.cloudConfirmed}',
          '${archive.isComplete}',
          '${archive.hasJournal}',
          '',
          '',
        ].map(_escapeCsv).join(','),
      );
    }
    final operations = [...archive.operations]
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final op in operations) {
      rows.add(
        [
          '$archiveSchemaVersion',
          'operation',
          op.session.id,
          op.id,
          op.actorId,
          op.session.startedAtUtc.toIso8601String(),
          op.session.endedAtUtc?.toIso8601String() ?? '',
          op.recordedAtUtc.toIso8601String(),
          '${op.deleted}',
          jsonEncode(op.parentIds),
          '${conflictIds.contains(op.session.id)}',
          '${archive.cloudConfirmed}',
          '${archive.isComplete}',
          '${archive.hasJournal}',
          '',
          '',
        ].map(_escapeCsv).join(','),
      );
    }
    // A conflict with *no* accepted head still needs its references in CSV.
    for (final conflict in archive.conflicts) {
      rows.add(
        [
          '$archiveSchemaVersion',
          'conflict',
          conflict.sessionId,
          '',
          '',
          '',
          '',
          '',
          '',
          jsonEncode(conflict.heads.map((h) => h.id).toList()),
          'true',
          '${archive.cloudConfirmed}',
          '${archive.isComplete}',
          '${archive.hasJournal}',
          '',
          '',
        ].map(_escapeCsv).join(','),
      );
    }
    return '${rows.join('\r\n')}\r\n';
  }

  static Map<String, Object?> _sessionData(SleepSession session) => {
    'id': session.id,
    'startedAtUtc': session.startedAtUtc.toIso8601String(),
    'endedAtUtc': session.endedAtUtc?.toIso8601String(),
  };

  static Map<String, Object?> _operationData(SleepOperation op) => {
    'id': op.id,
    'actorId': op.actorId,
    'recordedAtUtc': op.recordedAtUtc.toIso8601String(),
    'deleted': op.deleted,
    'parentIds': op.parentIds,
    'session': _sessionData(op.session),
  };

  static String _escapeCsv(String cell) {
    // Quoting alone does not stop spreadsheet formula evaluation. Leading
    // apostrophe is only needed for unexpected formula-like external IDs.
    // JSON remains the canonical byte-for-byte round-trip format.
    final safe = RegExp(r'^[\x00-\x20]*[=+\-@]').hasMatch(cell)
        ? "'$cell"
        : cell;
    if (safe.contains(RegExp('[,"\r\n]'))) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }
}
