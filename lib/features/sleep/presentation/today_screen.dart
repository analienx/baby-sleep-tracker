import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_summary.dart';
import 'presentation_helpers.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  Timer? _repaintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumeTicker();
  }

  void _resumeTicker() {
    _repaintTimer?.cancel();
    // Visual refresh only. The authoritative elapsed time is always calculated
    // from the persisted instant; there is no background timer/service.
    _repaintTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeTicker();
      if (mounted) setState(() {});
    } else {
      _repaintTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repaintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).nowUtc;
    final sessions = ref.watch(sleepSessionsProvider);
    final conflicts = ref.watch(sleepConflictsProvider);
    final compact =
        MediaQuery.textScalerOf(context).scale(16) > 24 ||
        (MediaQuery.sizeOf(context).height <= 620 &&
            MediaQuery.sizeOf(context).width <= 430);
    final content = PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenIntro(
            title: "Today's sleep.",
            subtitle: 'One little moment at a time.',
          ),
          const SizedBox(height: 12),
          const PreviewWarning(),
          const SizedBox(height: 12),
          sessions.when(
            data: (value) => _Dashboard(
              sessions: value,
              nowUtc: now,
              conflictCount: conflicts.asData?.value.length ?? 0,
              compact: compact,
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
      ),
    );
    if (!compact) return content;
    return Stack(
      children: [
        Positioned.fill(bottom: 90, child: content),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 13),
              child: sessions.when(
                data: (value) =>
                    _SleepActionRow(sessions: value, compact: true),
                loading: () => const SizedBox(height: 58),
                error: (_, _) => const SizedBox(height: 58),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({
    required this.sessions,
    required this.nowUtc,
    required this.conflictCount,
    required this.compact,
  });

  final List<SleepSession> sessions;
  final DateTime nowUtc;
  final int conflictCount;
  final bool compact;

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
    final active = [
      for (final session in sessions)
        if (session.isActive) session,
    ];
    final sleeping = active.isNotEmpty;
    final latestEnd = [
      for (final session in sessions)
        if (session.endedAtUtc != null) session.endedAtUtc!,
    ]..sort((a, b) => b.compareTo(a));
    final elapsed = active.length > 1
        ? null
        : sleeping
        ? nowUtc.difference(active.first.startedAtUtc)
        : latestEnd.isNotEmpty
        ? nowUtc.difference(latestEnd.first)
        : null;
    final summary = SleepSummary.rolling24Hours(sessions, nowUtc);

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
                      active.length > 1
                          ? 'NEEDS REVIEW'
                          : sleeping
                          ? 'SLEEPING NOW'
                          : elapsed == null
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
              const SizedBox(height: 14),
              Semantics(
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
              ),
              const SizedBox(height: 8),
              Text(
                active.length > 1
                    ? 'Check competing records in History'
                    : sleeping
                    ? 'Started ${formatLocalTime(context, active.first.startedAtUtc)}'
                    : latestEnd.isNotEmpty
                    ? 'Last wake-up ${formatLocalTime(context, latestEnd.first)}'
                    : 'Start with a single tap',
                style: const TextStyle(color: Color(0xFFD2D5E5), fontSize: 14),
              ),
              if (!compact) ...[
                const SizedBox(height: 18),
                _SleepActionRow(sessions: sessions),
              ],
            ],
          ),
        ),
        const SizedBox(height: 23),
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
        if (active.length > 1 || summary.hasOverlap || conflictCount > 0) ...[
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
                            : active.length > 1
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

/// Shared action for normal status-card and accessible compact sticky layout.
class _SleepActionRow extends ConsumerWidget {
  const _SleepActionRow({required this.sessions, this.compact = false});

  final List<SleepSession> sessions;
  final bool compact;

  Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function() action,
  ) async {
    bool changed;
    try {
      changed = await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this record. Try again.'),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (changed) unawaited(HapticFeedback.lightImpact());
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No change made. Check for an active-session conflict.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = sessions.where((session) => session.isActive).length;
    final sleeping = activeCount > 0;
    // A conflict in an *unrelated, completed* nap must never prevent parents
    // from ending an otherwise unambiguous current sleep. The separate
    // dashboard warning still directs caregivers to History for reconciliation.
    final needsReview = activeCount > 1;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: needsReview
                ? () => context.go('/history')
                : () => _perform(
                    context,
                    ref,
                    ref.read(sleepActionsProvider).toggle,
                  ),
            icon: Icon(
              sleeping ? Icons.wb_sunny_rounded : Icons.bedtime_rounded,
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
        if (!sleeping && !needsReview) ...[
          const SizedBox(width: 9),
          PopupMenuButton<int>(
            tooltip: 'Backdate sleep start',
            onSelected: (minutes) => _perform(
              context,
              ref,
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
            child: SizedBox(
              height: 52,
              width: compact ? 48 : null,
              child: Center(
                child: compact
                    ? Icon(
                        Icons.history_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                      )
                    : const Text(
                        'Earlier',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
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
                                  ? Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? SleepPalette.lavender
                                        : SleepPalette.daytimeChart
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
