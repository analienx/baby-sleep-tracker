import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

/// A PWA must not import dart:io. Use an in-memory Blob-backed XFile; the web
/// share implementation downloads or shares the file from the user gesture.
/// No stale temp files are generated in Safari's private local storage.
final class SleepExportFiles {
  SleepExportFiles({Object? cacheRoot, DateTime Function()? now});

  Future<XFile> stage({required Uint8List bytes, required bool asJson}) async {
    final extension = asJson ? 'json' : 'csv';
    final name = 'little-rest-share-${const Uuid().v4()}.$extension';
    return XFile.fromData(
      bytes,
      name: name,
      mimeType: asJson ? 'application/json' : 'text/csv',
    );
  }

  Future<int> cleanupStale() async => 0;
  Future<int> clearAfterSharing() async => 0;
}
