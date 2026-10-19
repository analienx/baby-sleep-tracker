import 'dart:convert';

import 'sleep_session.dart';

/// Portable projection of the currently accepted, visible sessions.
/// The F1 repository does not expose the immutable audit journal yet.
final class SleepExport {
  static const schemaVersion = 1;

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
