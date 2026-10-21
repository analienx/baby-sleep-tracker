import '../domain/sleep_repository.dart';

enum StorageEnvironment {
  volatilePreview,
  legacyEmulator,
  familyEmulator,
  familyCloud,
  personalCloud,
  personalEmulator,
}

String storageBadge(StorageEnvironment environment) => switch (environment) {
  StorageEnvironment.volatilePreview => 'PREVIEW',
  StorageEnvironment.legacyEmulator => 'EMULATOR',
  StorageEnvironment.familyEmulator => 'FAMILY DEV',
  StorageEnvironment.familyCloud => 'FAMILY',
  StorageEnvironment.personalCloud => 'CLOUD',
  StorageEnvironment.personalEmulator => 'PRIVATE DEV',
};

String storageMessage(
  StorageEnvironment environment,
  SleepStorageStatus? status,
) {
  if (environment == StorageEnvironment.volatilePreview) {
    return 'Preview only — entries are not saved and will disappear on restart.';
  }
  if (status == null) return 'Opening on-device cache…';
  return switch (status.phase) {
    StoragePhase.opening => 'Opening on-device cache…',
    StoragePhase.cached =>
      'Cached on device. Latest server state has not been verified.',
    StoragePhase.pending =>
      'Saved in local cache; pending server sync. Do not uninstall the app.',
    StoragePhase.synced => switch (environment) {
      StorageEnvironment.legacyEmulator =>
        'Synced with local development emulator. Synthetic data only.',
      StorageEnvironment.familyEmulator =>
        'Synced with local family emulator. Synthetic data only.',
      StorageEnvironment.familyCloud => 'Synced with your family cloud.',
      StorageEnvironment.personalCloud => 'Synced privately to Firebase. Protect your account with email before changing phones.',
      StorageEnvironment.personalEmulator =>
        'Synced with private-account test emulator. Synthetic data only.',
      StorageEnvironment.volatilePreview =>
        'Preview only — entries are not saved.',
    },
    StoragePhase.failed => status.detail ?? 'Storage or sync error. Some changes may not have reached the server.',
    StoragePhase.preview =>
      'Preview only — entries are not saved and will disappear on restart.',
  };
}
