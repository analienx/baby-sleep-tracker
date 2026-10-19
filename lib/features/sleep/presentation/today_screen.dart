import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final conflicts = ref.watch(sleepConflictsProvider);
    final conflictCount = conflicts.asData?.value.length ?? 0;
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
          data: (value) => _Dashboard(
            sessions: value,
            showEmbeddedAction: !compact,
            conflictCount: conflictCount,
          ),
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
            data: (value) => _SleepActionControls(
              sleeping: value.any((session) => session.isActive),
              needsReview:
                  conflictCount > 0 ||
                  value.where((session) => session.isActive).length > 1,
            ),
            loading: () => const _SleepActionControls(enabled: false),
            error: (_, _) => const _SleepActionControls(enabled: false),
          ),
        ),
      ],
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({
    required this.sessions,
    required this.conflictCount,
    required this.showEmbeddedAction,
  });

  final List<SleepSession> sessions;
  final int conflictCount;
  final bool showEmbeddedAction;

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    try {
      final restored = await ref.read(sleepActionsProvider).undo();
      if (!restored && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot undo because this record has changed.'),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Undo failed. The record was not changed.'),
        ),
      );
    }
  }

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
    final since = active.length > 1
        ? null
        : sleeping
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
                      conflictCount > 0 || active.length > 1
                          ? 'NEEDS REVIEW'
                          : sleeping
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
                  if (ref.read(sleepActionsProvider).canUndo)
                    IconButton(
                      tooltip: 'Undo last change',
                      onPressed: () => _undo(context, ref),
                      icon: const Icon(Icons.undo_rounded, color: Colors.white),
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
                conflictCount > 0 || active.length > 1
                    ? 'Check competing records in History'
                    : sleeping
                    ? 'Started ${formatLocalTime(context, active.first.startedAtUtc)}'
                    : latestEnd.isNotEmpty
                    ? 'Last wake-up ${formatLocalTime(context, latestEnd.first)}'
                    : 'Start with a single tap',
                style: const TextStyle(color: Color(0xFFD2D5E5), fontSize: 14),
              ),
              if (showEmbeddedAction) ...[
                const SizedBox(height: 32),
                _SleepActionControls(
                  sleeping: sleeping,
                  needsReview: conflictCount > 0 || active.length > 1,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 23),
        _NowTicker(
          clock: clock,
          enabled: sessions.isNotEmpty,
          interval: const Duration(minutes: 1),
          builder: (nowUtc) => _SleepStatistics(
            sessions: sessions,
            nowUtc: nowUtc,
            conflictCount: conflictCount,
          ),
        ),
      ],
    );
  }
}

class _SleepStatistics extends StatelessWidget {
  const _SleepStatistics({
    required this.sessions,
    required this.nowUtc,
    required this.conflictCount,
  });

  final List<SleepSession> sessions;
  final DateTime nowUtc;
  final int conflictCount;

  @override
  Widget build(BuildContext context) {
    final summary = SleepSummary.rolling24Hours(sessions, nowUtc);
    final activeCount = sessions.where((s) => s.isActive).length;
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
        if (activeCount > 1 || summary.hasOverlap || conflictCount > 0) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        conflictCount > 0
                            ? '$conflictCount competing edit(s) preserved. Check History; no automatic overwrite.'
                            : activeCount > 1
                            ? 'Multiple active sleeps found. Check History before stopping.'
                            : 'Overlapping sleeps found. Total uses each minute once; check History.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 23),
        _TimelineCard(sessions: sessions, nowUtc: nowUtc),
      ],
    );
  }
}

class _SleepActionControls extends ConsumerWidget {
  const _SleepActionControls({
    this.sleeping = false,
    this.needsReview = false,
    this.enabled = true,
  });

  final bool sleeping;
  final bool needsReview;
  final bool enabled;

  Future<void> _perform(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    try {
      final changed = await action();
      if (!context.mounted) return;
      if (changed) {
        unawaited(HapticFeedback.lightImpact());
      } else {
        _showActionMessage(
          context,
          'No change made. Check for an active-session conflict.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        _showActionMessage(context, 'Could not update this record. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: !enabled
              ? null
              : needsReview
              ? () => context.go('/history')
              : () => _perform(context, ref.read(sleepActionsProvider).toggle),
          icon: Icon(
            needsReview
                ? Icons.rule_rounded
                : sleeping
                ? Icons.wb_sunny_rounded
                : Icons.bedtime_rounded,
            size: 22,
          ),
          label: Text(
            needsReview
                ? 'Review History'
                : sleeping
                ? 'Wake up'
                : 'Start sleep',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: SleepPalette.lavender,
            foregroundColor: SleepPalette.ink,
          ),
        ),
      ),
      if (enabled && !sleeping && !needsReview) ...[
        const SizedBox(width: 9),
        PopupMenuButton<int>(
          tooltip: 'Backdate sleep start',
          onSelected: (minutes) => _perform(
            context,
            () => ref
                .read(sleepActionsProvider)
                .start(backdate: Duration(minutes: minutes)),
          ),
          itemBuilder: (_) => [
            for (final minutes in [5, 10, 15])
              PopupMenuItem(
                value: minutes,
                child: Text('Start $minutes min ago'),
              ),
          ],
          child: const SizedBox(
            height: 52,
            child: Center(
              child: Text('Earlier', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ],
    ],
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
