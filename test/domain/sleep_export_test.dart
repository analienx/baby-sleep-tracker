import 'dart:convert';

import 'package:baby_sleep_tracker/features/sleep/domain/sleep_export.dart';
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
}
