import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../domain/sleep_ledger.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_summary.dart';
import 'history_editor.dart';
import 'presentation_helpers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Future<void> _perform(
    Future<bool> Function() operation, {
    required String success,
  }) async {
    try {
      final changed = await operation();
      if (!mounted) return;
      _feedback(
        changed ? success : 'History changed elsewhere. Review it again.',
        undo: changed,
      );
    } catch (_) {
      if (!mounted) return;
      _feedback('Could not update this rest. Review the times and try again.');
    }
  }

  void _feedback(String message, {bool undo = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: undo
            ? SnackBarAction(label: 'Undo', onPressed: _performUndo)
            : null,
      ),
    );
  }

  Future<void> _performUndo() async {
    try {
      final undone = await ref.read(sleepActionsProvider).undo();
      if (!mounted) return;
      _feedback(
        undone
            ? 'Last change reversed.'
            : 'Cannot undo; the record changed elsewhere.',
      );
    } catch (_) {
      if (!mounted) return;
      _feedback('Could not restore this rest. Please review History.');
    }
  }

  Future<void> _edit(
    List<SleepSession> sessions, [
    SleepSession? original,
  ]) async {
    final change = await showModalBottomSheet<SleepEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistoryEditor(
        nowUtc: ref.read(clockProvider).nowUtc,
        otherSessions: sessions,
        original: original,
      ),
    );
    if (change == null || !mounted) return;
    final actions = ref.read(sleepActionsProvider);
    if (original == null) {
      await _perform(
        () => actions.addCompleted(change.startUtc, change.endUtc!),
        success: 'Rest added to History.',
      );
    } else {
      await _perform(
        () => actions.correct(
          original,
          startUtc: change.startUtc,
          endUtc: change.endUtc,
        ),
        success: 'Rest updated.',
      );
    }
  }

  Future<void> _delete(SleepSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this rest?'),
        content: const Text(
          'It will disappear from the timeline. You can undo the change. '
          'In synced mode, its history remains available for auditing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep rest'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove rest'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => ref.read(sleepActionsProvider).delete(session),
      success: 'Rest removed.',
    );
  }

  Future<void> _review(SleepConflict conflict) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        int? choice;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Choose the correct version'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edits made without seeing one another have been preserved. '
                    'Select the version that reflects what really happened.',
                  ),
                  const SizedBox(height: 13),
                  RadioGroup<int>(
                    groupValue: choice,
                    onChanged: (value) => setDialogState(() => choice = value),
                    child: Column(
                      children: [
                        for (var i = 0; i < conflict.heads.length; i++)
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Version ${i + 1}'),
                            subtitle: Text(
                              conflict.heads[i].deleted
                                  ? 'Removed in this version'
                                  : _describe(
                                      context,
                                      conflict.heads[i].session,
                                    ),
                            ),
                            value: i,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your choice creates a new revision. No competing version '
                    'is erased from the operation history.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: choice == null
                    ? null
                    : () => Navigator.pop(context, choice),
                child: const Text('Keep selected version'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    final branch = conflict.heads[selected];
    await _perform(
      () => ref
          .read(sleepActionsProvider)
          .resolveConflict(conflict, branch.deleted ? null : branch.session),
      success: 'Version chosen. The revision history is preserved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sleepSessionsProvider);
    final conflicts = ref.watch(sleepConflictsProvider);
    final nowUtc = ref.watch(clockProvider).nowUtc;
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenIntro(
            title: 'Every little rest.',
            subtitle: 'Your sleep timeline, simply told.',
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a missed rest'),
              onPressed: sessions.asData == null
                  ? null
                  : () => _edit(sessions.asData!.value),
            ),
          ),
          const SizedBox(height: 16),
          if (conflicts.asData?.value.isNotEmpty ?? false) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Competing edits need review',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'When available, the last agreed version is shown '
                      'below. Neither competing edit is silently applied.',
                    ),
                    for (final conflict in conflicts.asData!.value)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: OutlinedButton(
                          onPressed: () => _review(conflict),
                          child: Text(
                            'Review ${conflict.heads.length} versions of a rest',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
          ],
          sessions.when(
            data: (value) => value.isEmpty
                ? const _EmptyHistory()
                : _Timeline(
                    sessions: value,
                    nowUtc: nowUtc,
                    onEdit: (session) => _edit(value, session),
                    onDelete: _delete,
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text(
              'History is temporarily unavailable. Try again shortly.',
            ),
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
          const Text('A missed nap? Add it above, even if you forgot to tap.'),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to Today'),
          ),
        ],
      ),
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.sessions,
    required this.nowUtc,
    required this.onEdit,
    required this.onDelete,
  });

  final List<SleepSession> sessions;
  final DateTime nowUtc;
  final ValueChanged<SleepSession> onEdit;
  final ValueChanged<SleepSession> onDelete;

  @override
  Widget build(BuildContext context) {
    final overlapIds = SleepSummary.between(
      sessions,
      fromUtc: DateTime.utc(2000),
      toUtc: nowUtc,
    ).overlappingSessionIds;
    final sorted = [...sessions]
      ..sort((a, b) {
        final byStart = b.startedAtUtc.compareTo(a.startedAtUtc);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          if (i == 0 ||
              !_sameDay(
                sorted[i - 1].startedAtUtc.toLocal(),
                sorted[i].startedAtUtc.toLocal(),
              ))
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 16, 3, 5),
              child: Text(
                MaterialLocalizations.of(context)
                    .formatMediumDate(sorted[i].startedAtUtc.toLocal()),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          _SessionTile(
            session: sorted[i],
            nowUtc: nowUtc,
            overlap: overlapIds.contains(sorted[i].id),
            onEdit: () => onEdit(sorted[i]),
            onDelete: () => onDelete(sorted[i]),
          ),
        ],
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

String _describe(BuildContext context, SleepSession session) {
  final end = session.endedAtUtc;
  final date = MaterialLocalizations.of(context);
  final startLocal = session.startedAtUtc.toLocal();
  final first =
      '${date.formatMediumDate(startLocal)} '
      '${formatLocalTime(context, session.startedAtUtc)}';
  if (end == null) return '$first → ongoing';
  final endLocal = end.toLocal();
  final last =
      '${date.formatMediumDate(endLocal)} '
      '${formatLocalTime(context, end)}';
  return '$first → $last';
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.nowUtc,
    required this.overlap,
    required this.onEdit,
    required this.onDelete,
  });

  final SleepSession session;
  final DateTime nowUtc;
  final bool overlap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ended = session.endedAtUtc;
    final duration = (ended ?? nowUtc).difference(session.startedAtUtc);
    final localStart = session.startedAtUtc.toLocal();
    final localEnd = ended?.toLocal();
    final crossesMidnight =
        localEnd != null &&
        (localStart.year != localEnd.year ||
            localStart.month != localEnd.month ||
            localStart.day != localEnd.day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 15, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.bedtime_rounded, size: 24),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ended == null
                        ? 'Sleeping now'
                        : formatShortDuration(duration),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(_describe(context, session)),
                  if (crossesMidnight) ...[
                    const SizedBox(height: 5),
                    const Text('Across midnight · one rest'),
                  ],
                  if (overlap) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Overlaps another rest — review times',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Correct or remove rest',
              onSelected: (choice) => choice == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit times')),
                PopupMenuItem(value: 'delete', child: Text('Remove rest')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
