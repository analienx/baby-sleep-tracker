import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/sleep_summary.dart';
import 'presentation_helpers.dart';

class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sleepSessionsProvider);
    final now = ref.watch(clockProvider).nowUtc;
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenIntro(
            title: 'Finding a rhythm.',
            subtitle: 'Gentle observations, without sleep scores.',
          ),
          const SizedBox(height: 29),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded in the last 24h',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    sessions.when(
                      data: (records) => formatShortDuration(
                        SleepSummary.rolling24Hours(records, now).sleep,
                      ),
                      loading: () => '…',
                      error: (_, _) => 'Unavailable',
                    ),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text('A simple observation, not a sleep target.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_graph_rounded, size: 38),
                  const SizedBox(height: 19),
                  Text(
                    'The story takes time',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'After a few days of sleep logs, patterns will become easier to see. '
                    'No predictions or rigid wake-window rules.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 23),
          const PreviewWarning(),
        ],
      ),
    );
  }
}
