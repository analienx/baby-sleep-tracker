import 'package:baby_sleep_tracker/features/sleep/domain/local_wall_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as database;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(database.initializeTimeZones);

  LocalWallTime inZone(String name) {
    final location = tz.getLocation(name);
    return LocalWallTime(
      toWall: (instant) => tz.TZDateTime.from(instant, location),
    );
  }

  test('spring-forward gap has no matching UTC instant', () {
    final resolver = inZone('Europe/Prague');
    expect(
      resolver.candidates(date: DateTime.utc(2026, 3, 29), hour: 2, minute: 30),
      isEmpty,
    );
    final valid = resolver.candidates(
      date: DateTime.utc(2026, 3, 29),
      hour: 3,
      minute: 30,
    );
    expect(valid, hasLength(1));
    expect(valid.single.utc, DateTime.utc(2026, 3, 29, 1, 30));
  });

  test('fall-back fold must expose both occurrences explicitly', () {
    final resolver = inZone('Europe/Prague');
    final candidates = resolver.candidates(
      date: DateTime.utc(2026, 10, 25),
      hour: 2,
      minute: 30,
    );
    expect(candidates, hasLength(2));
    expect(candidates[0].utc, DateTime.utc(2026, 10, 25, 0, 30));
    expect(candidates[1].utc, DateTime.utc(2026, 10, 25, 1, 30));
    expect(candidates[0].description, contains('UTC+02:00'));
    expect(candidates[1].description, contains('UTC+01:00'));
  });

  test('negative offsets and unusual 45-minute offsets round-trip', () {
    final kathmandu = inZone('Asia/Kathmandu');
    final candidates = kathmandu.candidates(
      date: DateTime.utc(2026, 10, 19),
      hour: 6,
      minute: 15,
    );
    expect(candidates.single.utc, DateTime.utc(2026, 10, 19, 0, 30));
    expect(candidates.single.description, contains('UTC+05:45'));

    final newYork = inZone('America/New_York');
    final fall = newYork.candidates(
      date: DateTime.utc(2026, 11, 1),
      hour: 1,
      minute: 15,
    );
    expect(fall, hasLength(2));
    expect(fall[0].description, contains('UTC-04:00'));
    expect(fall[1].description, contains('UTC-05:00'));
  });
}
