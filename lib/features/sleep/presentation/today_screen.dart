import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/clock.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_summary.dart';
import 'presentation_helpers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sleepSessionsProvider);
    final compact =
        MediaQuery.sizeOf(context).height < 780 ||
        MediaQuery.textScalerOf(context).scale(16) > 20;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenIntro(
          title: "Today's sleep.",
          subtitle: 'One little moment at a time.',
        ),
        const SizedBox(height: 20),
        const PreviewWarning(),
        const SizedBox(height: 18),
        sessions.when(
          data: (value) =>
              _Dashboard(sessions: value, showEmbeddedAction: !compact),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => const Text(
            'Preview could not load. Restart the app to try again.',
          ),
        ),
      ],
    );
    if (!compact) return PageContainer(child: content);

    // The sole primary action remains visible above bottom navigation even on
    // short phones and with enlarged system text. The rest is scrollable.
    return Column(
      children: [
        Expanded(child: PageContainer(child: content)),
        _StickyActionBar(
          child: sessions.when(
            data: (value) => _SleepActionButton(
              sleeping: value.any((session) => session.isActive),
            ),
            loading: () => const _SleepActionButton(enabled: false),
            error: (_, _) => const _SleepActionButton(enabled: false),
          ),
        ),
      ],
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.sessions, required this.showEmbeddedAction});

  final List<SleepSession> sessions;
  final bool showEmbeddedAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final active = [
      for (final session in sessions)
        if (session.isActive) session,
    ];
    final sleeping = active.isNotEmpty;
    final latestEnd = [
      for (final session in sessions)
        if (session.endedAtUtc != null) session.endedAtUtc!,
    ]..sort((a, b) => b.compareTo(a));
    final since = sleeping
        ? active.first.startedAtUtc
        : latestEnd.isNotEmpty
        ? latestEnd.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(25, 26, 25, 25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SleepPalette.twilight, Color(0xFF3A3E62)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    sleeping
                        ? Icons.bedtime_rounded
                        : Icons.wb_twilight_rounded,
                    color: SleepPalette.lavender,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sleeping
                          ? 'SLEEPING NOW'
                          : since == null
                          ? 'READY WHEN YOU ARE'
                          : 'AWAKE FOR',
                      style: const TextStyle(
                        color: Color(0xFFE1DDF6),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _NowTicker(
                clock: clock,
                enabled: since != null,
                interval: const Duration(seconds: 1),
                builder: (nowUtc) {
                  final elapsed = since == null
                      ? null
                      : nowUtc.difference(since);
                  return Semantics(
                    label: elapsed == null
                        ? 'No sleep recorded'
                        : '${sleeping ? 'Asleep' : 'Awake'} for ${formatShortDuration(elapsed)}',
                    child: ExcludeSemantics(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          elapsed == null
                              ? '00:00:00'
                              : formatClockDuration(elapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 50,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                sleeping
                    ? 'Started ${formatLocalTime(context, active.first.startedAtUtc)}'
                    : latestEnd.isNotEmpty
                    ? 'Last wake-up ${formatLocalTime(context, latestEnd.first)}'
                    : 'Start with a single tap',
                style: const TextStyle(color: Color(0xFFD2D5E5), fontSize: 14),
              ),
              if (showEmbeddedAction) ...[
                const SizedBox(height: 32),
                _SleepActionButton(sleeping: sleeping),
              ],
            ],
          ),
        ),
        const SizedBox(height: 23),
        _NowTicker(
          clock: clock,
          enabled: sessions.isNotEmpty,
          interval: const Duration(minutes: 1),
          builder: (nowUtc) =>
              _SleepStatistics(sessions: sessions, nowUtc: nowUtc),
        ),
      ],
    );
  }
}

class _SleepStatistics extends StatelessWidget {
  const _SleepStatistics({required this.sessions, required this.nowUtc});

  final List<SleepSession> sessions;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final summary = SleepSummary.rolling24Hours(sessions, nowUtc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('At a glance', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.nights_stay_outlined,
                label: 'Last 24 hours',
                value: formatShortDuration(summary.sleep),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.auto_awesome_motion,
                label: 'Sleep sessions',
                value: '${summary.sessionCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        _TimelineCard(sessions: sessions, nowUtc: nowUtc),
      ],
    );
  }
}

class _SleepActionButton extends ConsumerWidget {
  const _SleepActionButton({this.sleeping = false, this.enabled = true});

  final bool sleeping;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
    onPressed: !enabled
        ? null
        : () async {
            bool changed;
            try {
              changed = await ref.read(sleepActionsProvider).toggle();
            } catch (_) {
              if (!context.mounted) return;
              _showActionMessage(
                context,
                'Preview could not update. Try again.',
              );
              return;
            }
            if (!context.mounted) return;
            if (changed) await HapticFeedback.lightImpact();
            if (!context.mounted) return;
            _showActionMessage(
              context,
              changed
                  ? 'Preview updated — not saved to your device.'
                  : 'No change made. Please try again.',
            );
          },
    icon: Icon(
      sleeping ? Icons.wb_sunny_rounded : Icons.bedtime_rounded,
      size: 22,
    ),
    label: Text(sleeping ? 'Wake up' : 'Start sleep'),
    style: FilledButton.styleFrom(
      backgroundColor: SleepPalette.lavender,
      foregroundColor: SleepPalette.ink,
    ),
  );
}

void _showActionMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _StickyActionBar extends StatelessWidget {
  const _StickyActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Repaints only its child while visible. The clock remains the authority;
/// neither a background service nor a persisted countdown is required.
class _NowTicker extends StatefulWidget {
  const _NowTicker({
    required this.clock,
    required this.enabled,
    required this.interval,
    required this.builder,
  });

  final Clock clock;
  final bool enabled;
  final Duration interval;
  final Widget Function(DateTime nowUtc) builder;

  @override
  State<_NowTicker> createState() => _NowTickerState();
}

class _NowTickerState extends State<_NowTicker> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_foreground && widget.enabled) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(_NowTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.interval != widget.interval) {
      _restartTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _restartTimer();
    if (foreground && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.clock.nowUtc);
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 7),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.sessions, required this.nowUtc});

  final List<SleepSession> sessions;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final first = nowUtc.subtract(const Duration(hours: 24));
    final occupancy = List.generate(24, (index) {
      final from = first.add(Duration(hours: index));
      final to = from.add(const Duration(hours: 1));
      return sessions.any((session) {
        final end = session.endedAtUtc ?? nowUtc;
        return session.startedAtUtc.isBefore(to) && end.isAfter(from);
      });
    });
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your little rhythm',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            Text(
              'Sleep throughout the last 24 hours',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 23),
            Semantics(
              label:
                  '${occupancy.where((value) => value).length} of 24 hourly slots contain sleep',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (final occupied in occupancy)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Container(
                            height: 29,
                            decoration: BoxDecoration(
                              color: occupied
                                  ? SleepPalette.lavender
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('24h ago', style: Theme.of(context).textTheme.labelSmall),
                Text('Now', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
