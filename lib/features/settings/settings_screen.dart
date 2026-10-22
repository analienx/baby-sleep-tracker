import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../features/sleep/data/sleep_export_files.dart';
import '../../features/sleep/domain/sleep_archive.dart';
import '../../features/sleep/domain/sleep_export.dart';
import '../../l10n/app_localizations.dart';

/// Controls whose backend does not exist are visibly disabled, rather than
/// implying that an invite or deletion request has been accepted.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    required this.appearance,
    required this.onAppearanceChanged,
    this.familyAvailable = false,
    this.personalCloudAvailable = false,
    this.sparkFamilyLiteAvailable = false,
    this.familyFromCache = false,
    super.key,
  });

  final ThemeMode appearance;
  final Future<void> Function(ThemeMode) onAppearanceChanged;
  final bool familyAvailable;
  final bool personalCloudAvailable;
  final bool sparkFamilyLiteAvailable;
  final bool familyFromCache;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final SleepExportFiles _exportFiles = SleepExportFiles();
  bool _exporting = false;
  ThemeMode? _selectedAppearance;
  int _appearanceRevision = 0;

  void _feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAppearance(ThemeMode value) async {
    final before = _selectedAppearance ?? widget.appearance;
    final revision = ++_appearanceRevision;
    setState(() => _selectedAppearance = value);
    try {
      await widget.onAppearanceChanged(value);
    } catch (_) {
      if (!mounted || revision != _appearanceRevision) return;
      setState(() => _selectedAppearance = before);
      _feedback(AppLocalizations.of(context).appearanceError);
    }
  }

  Future<void> _share({required bool asJson, required Rect origin}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final strings = AppLocalizations.of(context);
    try {
      // Fetch the latest accepted projection when the parent taps Export;
      // never reuse possibly stale records from the widget's last frame.
      final repository = ref.read(sleepRepositoryProvider);
      final archive = repository is SleepArchiveSource
          ? await (repository as SleepArchiveSource).readArchive()
          : SleepArchive(sessions: await repository.readSessions());
      final now = ref.read(clockProvider).nowUtc;
      final contents = asJson
          ? SleepExport.archiveJson(archive, exportedAtUtc: now)
          : SleepExport.archiveCsv(archive);
      if (!mounted) return;
      final file = await _exportFiles.stage(
        bytes: Uint8List.fromList(utf8.encode(contents)),
        asJson: asJson,
      );
      if (!mounted) return;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [
            asJson
                ? 'little-rest-archive-v2.json'
                : 'little-rest-archive-v2.csv',
          ],
          sharePositionOrigin: origin,
          title: strings.exportHeading,
        ),
      );
      if (!mounted) return;
      final outcome = switch (result.status) {
        ShareResultStatus.success => strings.exportDone,
        ShareResultStatus.dismissed => strings.exportDismissed,
        _ => strings.exportUnknown,
      };
      _feedback(
        archive.isComplete ? outcome : '${strings.exportIncomplete} $outcome',
      );
    } catch (_) {
      if (mounted) _feedback(strings.exportError);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clearExportFiles() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final cleared = await _exportFiles.clearAfterSharing();
      if (mounted) {
        _feedback(AppLocalizations.of(context).exportCacheCleared(cleared));
      }
    } catch (_) {
      if (mounted) _feedback(AppLocalizations.of(context).exportCacheError);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final appearance = _selectedAppearance ?? widget.appearance;
    final conflicts = ref.watch(sleepConflictsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _SettingsSection(
                  title: strings.appearanceHeading,
                  description: strings.appearanceDescription,
                  child: RadioGroup<ThemeMode>(
                    groupValue: appearance,
                    onChanged: (mode) {
                      if (mode != null) _setAppearance(mode);
                    },
                    child: Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.system,
                          title: Text(strings.appearanceSystem),
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.light,
                          title: Text(strings.appearanceLight),
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          title: Text(strings.appearanceDark),
                        ),
                      ],
                    ),
                  ),
                ),
                if (kIsWeb && widget.sparkFamilyLiteAvailable) ...[
                  const SizedBox(height: 14),
                  _SettingsSection(
                    title: 'Install on iPhone',
                    description:
                        'In Safari, tap Share → Add to Home Screen → '
                        'Open as Web App. Then open Little Rest from its icon.',
                    child: const ListTile(
                      leading: Icon(Icons.add_to_home_screen_rounded),
                      title: Text('No App Store or weekly renewal'),
                      subtitle: Text(
                        'Protect your account with a verified '
                        'email before changing phones. iPhone may clear '
                        'offline website data; wait for Synced before '
                        'closing the app.',
                      ),
                    ),
                  ),
                ],
                if (widget.personalCloudAvailable) ...[
                  const SizedBox(height: 14),
                  _SettingsSection(
                    title: 'Private cloud account',
                    description: widget.sparkFamilyLiteAvailable
                        ? 'Your cloud account keeps your sleep history across '
                              'restarts. Verify your email to share safely '
                              'with another caregiver on Firebase Spark.'
                        : 'Keep your sleep history across app restarts '
                              'and protect access with email. Family sharing '
                              'requires the separate secure family service.',
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: const Text('Account and recovery'),
                      subtitle: const Text(
                        'Email verification, restore, privacy and deletion',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/account'),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _SettingsSection(
                  title: strings.familyHeading,
                  description: widget.sparkFamilyLiteAvailable
                      ? 'Separate accounts. One owner-approved shared journal on Firebase Spark.'
                      : widget.familyAvailable
                      ? strings.familyReady
                      : strings.familyNotReady,
                  child: Column(
                    children: [
                      ListTile(
                        enabled:
                            widget.familyAvailable ||
                            widget.sparkFamilyLiteAvailable,
                        leading: const Icon(Icons.person_add_alt_outlined),
                        title: Text(strings.familyInvite),
                        subtitle:
                            widget.familyAvailable ||
                                widget.sparkFamilyLiteAvailable
                            ? null
                            : Text(strings.familyUnavailable),
                        onTap: widget.sparkFamilyLiteAvailable
                            ? () => context.push('/family-lite')
                            : widget.familyAvailable
                            ? () => context.push('/family')
                            : null,
                      ),
                      ListTile(
                        enabled:
                            widget.familyAvailable ||
                            widget.sparkFamilyLiteAvailable,
                        leading: const Icon(Icons.group_outlined),
                        title: Text(strings.familyManage),
                        subtitle:
                            widget.familyAvailable ||
                                widget.sparkFamilyLiteAvailable
                            ? null
                            : Text(strings.familyUnavailable),
                        onTap: widget.sparkFamilyLiteAvailable
                            ? () => context.push('/family-lite')
                            : widget.familyAvailable
                            ? () => context.push('/family')
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: strings.exportHeading,
                  description: strings.exportDescription,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (conflicts.asData?.value.isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Competing versions need review in History; '
                              'only the accepted projection is included.',
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        Text(
                          strings.exportWarning,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (buttonContext) => FilledButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _share(
                                    asJson: true,
                                    origin: _buttonRect(buttonContext),
                                  ),
                            icon: const Icon(Icons.ios_share_rounded),
                            label: Text(strings.exportJson),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Builder(
                          builder: (buttonContext) => OutlinedButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _share(
                                    asJson: false,
                                    origin: _buttonRect(buttonContext),
                                  ),
                            icon: const Icon(Icons.table_view_outlined),
                            label: Text(strings.exportCsv),
                          ),
                        ),
                        if (_exporting) ...[
                          const SizedBox(height: 10),
                          Text(strings.exportBusy),
                        ],
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: _exporting ? null : _clearExportFiles,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: Text(strings.exportClearCache),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: strings.deleteHeading,
                  description: strings.deleteDescription,
                  child: ListTile(
                    enabled: widget.familyAvailable && !widget.familyFromCache,
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: Text(strings.deleteHousehold),
                    subtitle: Text(
                      widget.familyAvailable
                          ? strings.deleteOwnerOnly
                          : strings.familyUnavailable,
                    ),
                    onTap: widget.familyAvailable && !widget.familyFromCache
                        ? () => context.push('/family')
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect _buttonRect(BuildContext buttonContext) {
    final renderObject = buttonContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(description),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}
