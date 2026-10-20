import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/emulator_bootstrap.dart';
import '../../../app/family_bootstrap.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'storage_copy.dart';

StorageEnvironment get appStorageEnvironment {
  if (useFamilyProduction) return StorageEnvironment.familyCloud;
  if (useFamilyEmulator) return StorageEnvironment.familyEmulator;
  if (useFirebaseEmulator) return StorageEnvironment.legacyEmulator;
  return StorageEnvironment.volatilePreview;
}

final storageEnvironmentProvider = Provider<StorageEnvironment>(
  (ref) => appStorageEnvironment,
);

String formatClockDuration(Duration duration) {
  final value = duration.isNegative ? Duration.zero : duration;
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String formatShortDuration(Duration duration) {
  final value = duration.isNegative ? Duration.zero : duration;
  return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
}

String formatLocalTime(BuildContext context, DateTime atUtc) =>
    TimeOfDay.fromDateTime(atUtc.toLocal()).format(context);

String formatLocalDateTime(BuildContext context, DateTime atUtc) {
  final local = atUtc.toLocal();
  return '${MaterialLocalizations.of(context).formatMediumDate(local)}, '
      '${formatLocalTime(context, atUtc)}';
}

class ScreenIntro extends StatelessWidget {
  const ScreenIntro({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: SleepPalette.lavender.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.bedtime_rounded,
                color: Theme.of(context).colorScheme.onSurface,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'little rest',
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!compact) const _PreviewBadge(),
            IconButton(
              tooltip: AppLocalizations.of(context).settingsTooltip,
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        if (compact) ...[const SizedBox(height: 8), const _PreviewBadge()],
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class PreviewWarning extends ConsumerWidget {
  const PreviewWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepStorageProvider);
    final environment = ref.watch(storageEnvironmentProvider);
    final message = state.when(
      data: (status) => storageMessage(environment, status),
      loading: () => storageMessage(environment, null),
      error: (_, _) => 'Storage error. Do not assume this change was synced.',
    );
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageContainer extends StatelessWidget {
  const PageContainer({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        child: child,
      ),
    ),
  );
}

class _PreviewBadge extends ConsumerWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(
      storageBadge(ref.watch(storageEnvironmentProvider)),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700),
    ),
  );
}
