import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../domain/sleep_session.dart';
import 'presentation_helpers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sleepSessionsProvider);
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenIntro(
            title: 'Every little rest.',
            subtitle: 'Your sleep timeline, simply told.',
          ),
          const SizedBox(height: 29),
          sessions.when(
            data: (value) => value.isEmpty
                ? const _EmptyHistory()
                : Column(
                    children: [
                      for (final session in value)
                        _SessionTile(
                          session: session,
                          nowUtc: ref.watch(clockProvider).nowUtc,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('History is temporarily unavailable.'),
          ),
          const SizedBox(height: 24),
          const PreviewWarning(),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_toggle_off_rounded, size: 37),
          const SizedBox(height: 23),
          Text('A fresh start', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 9),
          const Text('Once you track a rest, you will find it here.'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go to Today'),
          ),
        ],
      ),
    ),
  );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.nowUtc});
  final SleepSession session;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    final ended = session.endedAtUtc;
    final duration = (ended ?? nowUtc).difference(session.startedAtUtc);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 19,
          vertical: 14,
        ),
        leading: const Icon(Icons.bedtime_rounded),
        title: Text(
          ended == null ? 'Sleeping now' : formatShortDuration(duration),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          '${formatLocalDateTime(context, session.startedAtUtc)} — '
          '${ended == null ? 'ongoing' : formatLocalDateTime(context, ended)}',
        ),
        trailing: ended == null
            ? const Icon(Icons.circle, color: Colors.green, size: 13)
            : null,
      ),
    );
  }
}
