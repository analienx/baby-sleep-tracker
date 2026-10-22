import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/family/data/family_client.dart';
import '../features/family/presentation/family_screen.dart';
import '../features/personal/data/personal_cloud_client.dart';
import '../features/personal/data/spark_baby_profiles.dart';
import '../features/personal/data/spark_family_lite_controller.dart';
import '../features/personal/presentation/spark_family_lite_screen.dart';
import '../features/personal/presentation/personal_account_screen.dart';
import '../features/sleep/presentation/history_screen.dart';
import '../features/sleep/presentation/today_screen.dart';
import '../features/sleep/presentation/trends_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sleep/data/sleep_export_files.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

final class BabySleepApp extends StatefulWidget {
  const BabySleepApp({
    super.key,
    this.familyClient,
    this.family,
    this.familyFromCache = false,
    this.personalClient,
    this.sparkFamilyLite,
    this.babyProfiles,
    this.selectedBabyId,
    this.onBabyChanged,
    this.onAddBaby,
    this.onRenameBaby,
  });
  final FamilyClient? familyClient;
  final FamilyContext? family;
  final bool familyFromCache;
  final PersonalCloudClient? personalClient;
  final SparkFamilyLiteController? sparkFamilyLite;
  final List<SparkBabyProfile>? babyProfiles;
  final String? selectedBabyId;
  final Future<void> Function(String)? onBabyChanged;
  final Future<void> Function(BuildContext)? onAddBaby;
  final Future<void> Function(BuildContext)? onRenameBaby;

  @override
  State<BabySleepApp> createState() => _BabySleepAppState();
}

final class _BabySleepAppState extends State<BabySleepApp> {
  static const _appearanceKey = 'appearance-mode-v1';
  ThemeMode _appearance = ThemeMode.system;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  int _appearanceRevision = 0;
  Future<void> _appearanceWrite = Future<void>.value();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
    unawaited(
      SleepExportFiles().cleanupStale().then((_) {}).catchError((Object _) {}),
    );
  }

  Future<void> _loadAppearance() async {
    final initialRevision = _appearanceRevision;
    try {
      final value = await _preferences.getString(_appearanceKey);
      if (!mounted || initialRevision != _appearanceRevision) return;
      setState(() {
        _appearance = ThemeMode.values.firstWhere(
          (mode) => mode.name == value,
          orElse: () => ThemeMode.system,
        );
      });
    } catch (_) {
      // Retain the OS appearance when platform preferences are unavailable.
    }
  }

  Future<void> _changeAppearance(ThemeMode mode) async {
    final old = _appearance;
    final revision = ++_appearanceRevision;
    setState(() => _appearance = mode);
    // Preference writes from rapid taps must be serialized. Otherwise an
    // older, slower write may complete last and silently replace the UI's
    // selected mode on the next app start.
    final write = _appearanceWrite
        .catchError((Object _) {})
        .then((_) => _preferences.setString(_appearanceKey, mode.name));
    _appearanceWrite = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      // A failed preference write must never leave a false "saved" state.
      if (mounted && revision == _appearanceRevision) {
        setState(() => _appearance = old);
      }
      rethrow;
    }
  }

  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => SettingsScreen(
          appearance: _appearance,
          onAppearanceChanged: _changeAppearance,
          familyAvailable: widget.familyClient != null && widget.family != null,
          familyFromCache: widget.familyFromCache,
          personalCloudAvailable: widget.personalClient != null,
          sparkFamilyLiteAvailable: widget.sparkFamilyLite != null,
        ),
      ),
      if (widget.personalClient != null)
        GoRoute(
          path: '/account',
          builder: (_, _) =>
              PersonalAccountScreen(client: widget.personalClient!),
        ),
      if (widget.familyClient != null && widget.family != null)
        GoRoute(
          path: '/family',
          builder: (_, _) => FamilyScreen(
            client: widget.familyClient!,
            family: widget.family!,
          ),
        ),
      if (widget.sparkFamilyLite != null)
        GoRoute(
          path: '/family-lite',
          builder: (_, _) =>
              SparkFamilyLiteScreen(client: widget.sparkFamilyLite!),
        ),
      ShellRoute(
        builder: (context, state, child) => _TabShell(
          currentPath: state.uri.path,
          familyFromCache: widget.familyFromCache,
          babyProfiles: widget.babyProfiles,
          selectedBabyId: widget.selectedBabyId,
          onBabyChanged: widget.onBabyChanged,
          onAddBaby: widget.onAddBaby,
          onRenameBaby: widget.onRenameBaby,
          child: child,
        ),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TodayScreen()),
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/trends', builder: (_, _) => const TrendsScreen()),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Little Rest',
    debugShowCheckedModeBanner: false,
    theme: SleepTheme.light(),
    darkTheme: SleepTheme.dark(),
    themeMode: _appearance,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: _router,
  );
}

final class _TabShell extends StatelessWidget {
  const _TabShell({
    required this.currentPath,
    required this.child,
    required this.familyFromCache,
    this.babyProfiles,
    this.selectedBabyId,
    this.onBabyChanged,
    this.onAddBaby,
    this.onRenameBaby,
  });
  final List<SparkBabyProfile>? babyProfiles;
  final String? selectedBabyId;
  final Future<void> Function(String)? onBabyChanged;
  final Future<void> Function(BuildContext)? onAddBaby;
  final Future<void> Function(BuildContext)? onRenameBaby;
  final String currentPath;
  final Widget child;
  final bool familyFromCache;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final index = switch (currentPath) {
      '/history' => 1,
      '/trends' => 2,
      _ => 0,
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (familyFromCache)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  'Offline family cache — membership is not verified. '
                  'Previously downloaded records may be stale.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (babyProfiles != null && selectedBabyId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 5),
                child: Row(
                  children: [
                    const Icon(Icons.child_care_rounded, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value:
                              babyProfiles!.any((p) => p.id == selectedBabyId)
                              ? selectedBabyId
                              : null,
                          hint: const Text('Select a baby'),
                          items: [
                            for (final baby in babyProfiles!)
                              DropdownMenuItem<String>(
                                value: baby.id,
                                child: Text(
                                  baby.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: onBabyChanged == null
                              ? null
                              : (id) {
                                  if (id != null) {
                                    unawaited(onBabyChanged!(id));
                                  }
                                },
                        ),
                      ),
                    ),
                    if (onRenameBaby != null)
                      IconButton(
                        tooltip: 'Rename selected baby',
                        onPressed: () => unawaited(onRenameBaby!(context)),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (onAddBaby != null)
                      IconButton(
                        tooltip: 'Add another baby',
                        onPressed: () => unawaited(onAddBaby!(context)),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                  ],
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (selected) => context.go(switch (selected) {
          1 => '/history',
          2 => '/trends',
          _ => '/',
        }),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.nightlight_outlined),
            selectedIcon: const Icon(Icons.nightlight_round),
            label: strings.navToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: strings.navHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: strings.navTrends,
          ),
        ],
      ),
    );
  }
}
