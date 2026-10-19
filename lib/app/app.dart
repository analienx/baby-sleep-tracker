import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/sleep/presentation/history_screen.dart';
import '../features/sleep/presentation/today_screen.dart';
import '../features/sleep/presentation/trends_screen.dart';
import '../features/settings/settings_screen.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

final class BabySleepApp extends StatefulWidget {
  const BabySleepApp({super.key});

  @override
  State<BabySleepApp> createState() => _BabySleepAppState();
}

final class _BabySleepAppState extends State<BabySleepApp> {
  static const _appearanceKey = 'appearance-mode-v1';
  ThemeMode _appearance = ThemeMode.system;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
  }

  Future<void> _loadAppearance() async {
    try {
      final value = await _preferences.getString(_appearanceKey);
      if (!mounted) return;
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
    setState(() => _appearance = mode);
    await _preferences.setString(_appearanceKey, mode.name);
  }

  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => SettingsScreen(
          appearance: _appearance,
          onAppearanceChanged: _changeAppearance,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _TabShell(currentPath: state.uri.path, child: child),
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
  const _TabShell({required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final index = switch (currentPath) {
      '/history' => 1,
      '/trends' => 2,
      _ => 0,
    };
    return Scaffold(
      body: SafeArea(child: child),
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
