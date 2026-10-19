import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/family/data/family_client.dart';
import '../features/family/presentation/family_screen.dart';
import '../features/sleep/presentation/history_screen.dart';
import '../features/sleep/presentation/today_screen.dart';
import '../features/sleep/presentation/trends_screen.dart';
import 'theme.dart';

final class BabySleepApp extends StatefulWidget {
  const BabySleepApp({
    super.key,
    this.familyClient,
    this.family,
    this.familyFromCache = false,
  });
  final FamilyClient? familyClient;
  final FamilyContext? family;
  final bool familyFromCache;

  @override
  State<BabySleepApp> createState() => _BabySleepAppState();
}

final class _BabySleepAppState extends State<BabySleepApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _TabShell(
          currentPath: state.uri.path,
          familyEnabled: widget.family != null,
          familyFromCache: widget.familyFromCache,
          child: child,
        ),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TodayScreen()),
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/trends', builder: (_, _) => const TrendsScreen()),
          if (widget.familyClient != null && widget.family != null)
            GoRoute(
              path: '/family',
              builder: (_, _) => FamilyScreen(
                client: widget.familyClient!,
                family: widget.family!,
              ),
            ),
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
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );
}

final class _TabShell extends StatelessWidget {
  const _TabShell({
    required this.currentPath,
    required this.child,
    required this.familyEnabled,
    required this.familyFromCache,
  });
  final String currentPath;
  final Widget child;
  final bool familyEnabled;
  final bool familyFromCache;

  @override
  Widget build(BuildContext context) {
    final index = switch (currentPath) {
      '/history' => 1,
      '/trends' => 2,
      '/family' => 3,
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
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (selected) => context.go(switch (selected) {
          1 => '/history',
          2 => '/trends',
          3 => '/family',
          _ => '/',
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.nightlight_outlined),
            selectedIcon: Icon(Icons.nightlight_round),
            label: 'Today',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Trends',
          ),
          if (familyEnabled)
            const NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Family',
            ),
        ],
      ),
    );
  }
}
