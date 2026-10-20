import 'package:baby_sleep_tracker/features/sleep/domain/sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/storage_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all four app storage modes have distinct truthful badges and messages',
    () {
      expect(storageBadge(StorageEnvironment.volatilePreview), 'PREVIEW');
      expect(storageBadge(StorageEnvironment.legacyEmulator), 'EMULATOR');
      expect(storageBadge(StorageEnvironment.familyEmulator), 'FAMILY DEV');
      expect(storageBadge(StorageEnvironment.familyCloud), 'FAMILY');
      const synced = SleepStorageStatus(StoragePhase.synced);
      expect(
        storageMessage(StorageEnvironment.volatilePreview, synced),
        contains('not saved'),
      );
      expect(
        storageMessage(StorageEnvironment.legacyEmulator, synced),
        contains('development emulator'),
      );
      expect(
        storageMessage(StorageEnvironment.familyEmulator, synced),
        contains('family emulator'),
      );
      expect(
        storageMessage(StorageEnvironment.familyCloud, synced),
        contains('family cloud'),
      );
      for (final family in [
        StorageEnvironment.familyCloud,
        StorageEnvironment.familyEmulator,
      ]) {
        expect(
          storageMessage(
            family,
            const SleepStorageStatus(StoragePhase.pending),
          ),
          contains('pending server sync'),
        );
        expect(
          storageMessage(family, const SleepStorageStatus(StoragePhase.cached)),
          contains('Cached on device'),
        );
        expect(
          storageMessage(
            family,
            const SleepStorageStatus(
              StoragePhase.failed,
              detail: 'Write rejected',
            ),
          ),
          'Write rejected',
        );
        expect(storageMessage(family, null), contains('Opening'));
      }
    },
  );
}
