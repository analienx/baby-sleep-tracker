import 'dart:io';

/// Explicit debug-only host override for physical phones on a trusted LAN.
/// Firebase emulator mobile SDKs require a hostname, not a URL or port.
String resolveFirebaseEmulatorHost({
  required bool isAndroid,
  required String configuredHost,
  required bool isRelease,
}) {
  if (isRelease) {
    throw StateError(
      'Firebase emulator mode is not available in release builds.',
    );
  }
  if (configuredHost.isEmpty) return isAndroid ? '10.0.2.2' : 'localhost';
  final host = configuredHost.trim();
  if (host != configuredHost ||
      host.isEmpty ||
      host.contains(RegExp(r'[/:\\\s]')) ||
      host == '0.0.0.0') {
    throw ArgumentError(
      'FIREBASE_EMULATOR_HOST must be a single trusted LAN host or IP.',
    );
  }
  final addr = InternetAddress.tryParse(host);
  if (addr != null && addr.type == InternetAddressType.IPv4) {
    final p = addr.rawAddress;
    final isPrivate =
        p[0] == 10 ||
        (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
        (p[0] == 192 && p[1] == 168) ||
        p[0] == 127;
    if (!isPrivate)
      throw ArgumentError('Emulator address must be private or loopback.');
    return host;
  }
  if (host == 'localhost' || RegExp(r'^[a-zA-Z0-9-]+\.local$').hasMatch(host)) {
    return host;
  }
  throw ArgumentError(
    'Use a private IPv4 address, localhost or a .local hostname.',
  );
}

const configuredFirebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
);
