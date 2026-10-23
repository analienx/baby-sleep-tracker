import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_summary.dart';
import '../domain/sleep_week.dart';
import 'presentation_helpers.dart';

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen>
    with WidgetsBindingObserver {
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumeTicker();
  }

  void _resumeTicker() {
    _minuteTicker?.cancel();
    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeTicker();
      if (mounted) setState(() {});
    } else {
      _minuteTicker?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minuteTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final sessions = ref.watch(sleepSessionsProvider);
    final now = ref.watch(clockProvider).nowUtc;
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenIntro(
            title: strings.trendsTitle,
            subtitle: strings.trendsSubtitle,
          ),
          const SizedBox(height: 20),
          const PreviewWarning(),
          const SizedBox(height: 18),
          sessions.when(
            data: (records) => _TrendsContent(records: records, nowUtc: now),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(strings.trendsError),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendsContent extends StatelessWidget {
  const _TrendsContent({required this.records, required this.nowUtc});

  final List<SleepSession> records;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final summary = SleepSummary.rolling24Hours(records, nowUtc);
    final days = SleepWeek.lastSevenDays(records, nowUtc);
    final loggedDays = days.where((day) => day.hasRecords).toList();
    final haveRecords = loggedDays.isNotEmpty;
    final missingDays = days.length - loggedDays.length;
    final longestLoggedDay = loggedDays.fold<int>(
      1,
      (maximum, day) => day.recordedSleep.inMicroseconds > maximum
          ? day.recordedSleep.inMicroseconds
          : maximum,
    );
    final hasWeekOverlap = days.any((day) => day.hasOverlap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(23),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.trendsLast24,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  summary.sessionCount == 0
                      ? strings.trendsNoRecords
                      : formatShortDuration(summary.sleep),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 9),
                Text(strings.trendsObservation),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.trendsWeek,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 9),
                Text(
                  strings.trendsWeekDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (!haveRecords) ...[
                  const Icon(Icons.auto_graph_rounded, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    strings.trendsEmptyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(strings.trendsEmptyBody),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${loggedDays.length} of 7 days with entries',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bars compare logged days, scaled to the longest '
                    'recorded day—not a sleep target.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  for (final day in loggedDays) ...[
                    _DayRow(day: day, longestLoggedDay: longestLoggedDay),
                    if (day != loggedDays.last) const SizedBox(height: 15),
                  ],
                  if (missingDays > 0) ...[
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$missingDays other ${missingDays == 1 ? 'day has' : 'days have'} '
                            'no entries. Missing records do not mean zero sleep.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    strings.trendsPartial,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasWeekOverlap) ...[
          const SizedBox(height: 14),
          Text(
            strings.trendsOverlap,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          strings.trendsFootnote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.longestLoggedDay});

  final SleepDayTotal day;
  final int longestLoggedDay;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = DateFormat.E(locale).format(day.localDate);
    final date = DateFormat.MMMEd(locale).format(day.localDate);
    final value = day.hasRecords
        ? formatShortDuration(day.recordedSleep)
        : strings.trendsNoRecords;
    // Relative scale among recorded days, never a 24-hour target.
    final portion = (day.recordedSleep.inMicroseconds / longestLoggedDay)
        .clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final highlight = day.isToday
        ? scheme.primary
        : Theme.of(context).brightness == Brightness.dark
        ? SleepPalette.sage
        : SleepPalette.daytimeChart;
    return Semantics(
      container: true,
      label: strings.trendsDayAccessible(
        date,
        value,
        '${day.isToday
            ? strings.trendsTodayStatus
            : !day.hasRecords
            ? strings.trendsMissingStatus
            : strings.trendsNoStatus}${day.hasOverlap ? strings.trendsDayOverlapStatus : ''}',
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  day.isToday ? '$label · Today' : label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (day.hasOverlap)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: scheme.error,
                    ),
                  ),
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              height: 9,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: portion,
                  child: ColoredBox(color: highlight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
