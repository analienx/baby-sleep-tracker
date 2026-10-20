import 'package:baby_sleep_tracker/app/firebase_emulator_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String host(String value, {bool android = true, bool release = false}) =>
      resolveFirebaseEmulatorHost(
        isAndroid: android,
        configuredHost: value,
        isRelease: release,
      );

  test('native simulator defaults preserved', () {
    expect(host(''), '10.0.2.2');
    expect(host('', android: false), 'localhost');
  });
  test('physical phones use only trusted private network addresses', () {
    for (final address in [
      '192.168.1.18',
      '10.1.0.6',
      '172.25.5.2',
      '127.0.0.1',
      'qa-host.local',
    ]) {
      expect(host(address), address);
    }
    for (final address in [
      '8.8.8.8',
      '192.169.1.1',
      'https://192.168.1.1',
      '192.168.1.1:8080',
      '0.0.0.0',
      'a.host.com',
      'bad host',
      '192.168.1.1 ',
      '::1',
    ]) {
      expect(() => host(address), throwsArgumentError);
    }
  });
  test('release build never talks to Firebase emulator', () {
    expect(() => host('192.168.1.2', release: true), throwsStateError);
    expect(() => host('', release: true), throwsStateError);
  });
}
