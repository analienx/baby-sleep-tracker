import 'dart:io';
import 'dart:typed_data';

import 'package:baby_sleep_tracker/features/sleep/data/sleep_export_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  final now = DateTime.utc(2026, 10, 19, 12);

  setUp(
    () async =>
        sandbox = await Directory.systemTemp.createTemp('rest-export-test-'),
  );
  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'staged private exports are controllable and cleaned explicitly',
    () async {
      final manager = SleepExportFiles(cacheRoot: sandbox, now: () => now);
      final staged = await manager.stage(
        bytes: Uint8List.fromList([123, 125]),
        asJson: true,
      );
      expect(staged.mimeType, 'application/json');
      expect(await File(staged.path).readAsBytes(), [123, 125]);
      await File(staged.path).setLastModified(now);
      expect(await manager.cleanupStale(), 0);
      expect(await manager.clearAfterSharing(), 1);
      expect(await File(staged.path).exists(), isFalse);
    },
  );

  test(
    'cleanup keeps fresh and unrelated files, removes only aged exports',
    () async {
      final manager = SleepExportFiles(cacheRoot: sandbox, now: () => now);
      final first = await manager.stage(
        bytes: Uint8List.fromList([1]),
        asJson: false,
      );
      final second = await manager.stage(
        bytes: Uint8List.fromList([2]),
        asJson: true,
      );
      await File(second.path).setLastModified(now);
      await File(first.path)
          .setLastModified(now.subtract(const Duration(days: 2)));
      final unrelated = File(
        '${sandbox.path}/little-rest-exports/preserve.txt',
      );
      await unrelated.writeAsString('other application data');
      expect(await manager.cleanupStale(), 1);
      expect(await File(first.path).exists(), isFalse);
      expect(await File(second.path).exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
