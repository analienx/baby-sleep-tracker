import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/sleep/presentation/history_screen.dart';
import '../features/sleep/presentation/today_screen.dart';
import '../features/sleep/presentation/trends_screen.dart';
import 'theme.dart';

final class BabySleepApp extends StatefulWidget {
  const BabySleepApp({super.key});

  @override
  State<BabySleepApp> createState() => _BabySleepAppState();
}

final class _BabySleepAppState extends State<BabySleepApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
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
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );
}

final class _TabShell extends StatelessWidget {
  const _TabShell({required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nightlight_outlined),
            selectedIcon: Icon(Icons.nightlight_round),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Trends',
          ),
        ],
      ),
    );
  }
}
