import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

/// Owns only the export files that Little Rest generates. The share recipient
/// may still need the file after the native sheet returns, so automatic
/// deletion is delayed until the next cleanup after a full day. Parents can
/// explicitly remove the app's staged copies from Settings once sharing ends.
final class SleepExportFiles {
  SleepExportFiles({this.cacheRoot, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Directory? cacheRoot;
  final DateTime Function() _now;

  static const retention = Duration(days: 1);
  static const _filePrefix = 'little-rest-share-';

  Future<Directory> _directory() async {
    final root = cacheRoot ?? await getTemporaryDirectory();
    return Directory('${root.path}/little-rest-exports');
  }

  Future<XFile> stage({required Uint8List bytes, required bool asJson}) async {
    await cleanupStale();
    final directory = await _directory();
    await directory.create(recursive: true);
    final extension = asJson ? 'json' : 'csv';
    final filename = '$_filePrefix${const Uuid().v4()}.$extension';
    final file = File('${directory.path}/$filename');
    await file.create(exclusive: true);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await file.delete();
      rethrow;
    }
    return XFile(file.path, mimeType: asJson ? 'application/json' : 'text/csv');
  }

  Future<int> cleanupStale() => _cleanup(onlyStale: true);
  Future<int> clearAfterSharing() => _cleanup(onlyStale: false);

  Future<int> _cleanup({required bool onlyStale}) async {
    final directory = await _directory();
    if (!await directory.exists()) return 0;
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final basename = entity.uri.pathSegments.last;
      if (!basename.startsWith(_filePrefix) ||
          !(basename.endsWith('.json') || basename.endsWith('.csv'))) {
        continue;
      }
      final file = File(entity.path);
      if (onlyStale &&
          _now().difference(await file.lastModified()) < retention) {
        continue;
      }
      await file.delete();
      removed++;
    }
    return removed;
  }
}
