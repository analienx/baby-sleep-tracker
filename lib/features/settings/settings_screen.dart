import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../features/sleep/domain/sleep_export.dart';
import '../../l10n/app_localizations.dart';

/// Controls whose backend does not exist are visibly disabled, rather than
/// implying that an invite or deletion request has been accepted.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    required this.appearance,
    required this.onAppearanceChanged,
    super.key,
  });

  final ThemeMode appearance;
  final Future<void> Function(ThemeMode) onAppearanceChanged;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  ThemeMode? _selectedAppearance;

  void _feedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAppearance(ThemeMode value) async {
    setState(() => _selectedAppearance = value);
    try {
      await widget.onAppearanceChanged(value);
    } catch (_) {
      if (!mounted) return;
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
      final sessions = await ref.read(sleepRepositoryProvider).readSessions();
      final now = ref.read(clockProvider).nowUtc;
      final contents = asJson
          ? SleepExport.json(sessions, exportedAtUtc: now)
          : SleepExport.csv(sessions);
      if (!mounted) return;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(contents)),
              mimeType: asJson ? 'application/json' : 'text/csv',
            ),
          ],
          fileNameOverrides: [
            asJson
                ? 'little-rest-sessions-v1.json'
                : 'little-rest-sessions-v1.csv',
          ],
          sharePositionOrigin: origin,
          title: strings.exportHeading,
        ),
      );
      if (!mounted) return;
      _feedback(switch (result.status) {
        ShareResultStatus.success => strings.exportDone,
        ShareResultStatus.dismissed => strings.exportDismissed,
        _ => strings.exportUnknown,
      });
    } catch (_) {
      if (mounted) _feedback(strings.exportError);
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
                const SizedBox(height: 14),
                _SettingsSection(
                  title: strings.familyHeading,
                  description: strings.familyNotReady,
                  child: Column(
                    children: [
                      ListTile(
                        enabled: false,
                        leading: const Icon(Icons.person_add_alt_outlined),
                        title: Text(strings.familyInvite),
                        subtitle: Text(strings.familyUnavailable),
                      ),
                      ListTile(
                        enabled: false,
                        leading: const Icon(Icons.group_outlined),
                        title: Text(strings.familyManage),
                        subtitle: Text(strings.familyUnavailable),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: strings.deleteHeading,
                  description: strings.deleteDescription,
                  child: ListTile(
                    enabled: false,
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: Text(strings.deleteHousehold),
                    subtitle: Text(strings.familyUnavailable),
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
