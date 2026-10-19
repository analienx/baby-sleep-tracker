import 'package:flutter/material.dart';

import '../domain/local_wall_time.dart';
import '../domain/sleep_session.dart';

typedef SleepEdit = ({DateTime startUtc, DateTime? endUtc});

/// The date and time controls select *civil* values. Every selected value is
/// explicitly resolved to UTC before this sheet returns a command.
class HistoryEditor extends StatefulWidget {
  const HistoryEditor({
    required this.nowUtc,
    required this.otherSessions,
    this.original,
    this.wallTime = const LocalWallTime(),
    super.key,
  });

  final DateTime nowUtc;
  final List<SleepSession> otherSessions;
  final SleepSession? original;
  final LocalWallTime wallTime;

  @override
  State<HistoryEditor> createState() => _HistoryEditorState();
}

class _HistoryEditorState extends State<HistoryEditor> {
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _stillSleeping;
  DateTime? _selectedStart;
  DateTime? _selectedEnd;

  @override
  void initState() {
    super.initState();
    final end = widget.original?.endedAtUtc ?? widget.nowUtc;
    final start =
        widget.original?.startedAtUtc ??
        widget.nowUtc.subtract(const Duration(minutes: 30));
    _startDate = start.toLocal();
    _endDate = end.toLocal();
    _startTime = TimeOfDay.fromDateTime(_startDate);
    _endTime = TimeOfDay.fromDateTime(_endDate);
    _stillSleeping = widget.original?.isActive ?? false;
    _selectedStart = widget.original?.startedAtUtc;
    _selectedEnd = widget.original?.endedAtUtc;
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _startDate : _endDate;
    final today = widget.nowUtc.toLocal();
    final last = DateTime(today.year, today.month, today.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: current.isAfter(last) ? last : current,
      firstDate: DateTime(2000),
      lastDate: last,
      helpText: start ? 'Sleep start date' : 'Sleep end date',
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (start) {
        _startDate = selected;
        _selectedStart = null;
      } else {
        _endDate = selected;
        _selectedEnd = null;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      initialEntryMode: TimePickerEntryMode.input,
      helpText: start ? 'Sleep start time' : 'Sleep end time',
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (start) {
        _startTime = selected;
        _selectedStart = null;
      } else {
        _endTime = selected;
        _selectedEnd = null;
      }
    });
  }

  List<WallTimeCandidate> _candidates(bool start) {
    final date = start ? _startDate : _endDate;
    final time = start ? _startTime : _endTime;
    return widget.wallTime.candidates(
      date: date,
      hour: time.hour,
      minute: time.minute,
    );
  }

  DateTime? _instant(bool start, List<WallTimeCandidate> candidates) {
    final selected = start ? _selectedStart : _selectedEnd;
    if (selected != null) {
      // Keep the precise original instant (including seconds) when a parent
      // edits the *other* endpoint. A touched picker has minute precision.
      if (widget.original != null &&
          selected ==
              (start
                  ? widget.original!.startedAtUtc
                  : widget.original!.endedAtUtc)) {
        return selected;
      }
      if (candidates.any((candidate) => candidate.utc == selected)) {
        return selected;
      }
    }
    return candidates.length == 1 ? candidates.single.utc : null;
  }

  @override
  Widget build(BuildContext context) {
    final starts = _candidates(true);
    final ends = _stillSleeping ? <WallTimeCandidate>[] : _candidates(false);
    final start = _instant(true, starts);
    final end = _stillSleeping ? null : _instant(false, ends);
    String? error;
    if (starts.isEmpty || (!_stillSleeping && ends.isEmpty)) {
      error =
          'That local time never occurred when the clock moved forward. '
          'Choose another time.';
    } else if (start == null || (!_stillSleeping && end == null)) {
      error = 'Choose which occurrence of the repeated local time you mean.';
    } else if (!start.isBefore(widget.nowUtc) ||
        (end != null && end.isAfter(widget.nowUtc))) {
      error = 'A sleep record cannot be in the future.';
    } else if (end != null && !end.isAfter(start)) {
      error = 'The end must be after the start.';
    } else if (end != null &&
        end.difference(start) > const Duration(hours: 24)) {
      error = 'A single rest cannot exceed 24 hours. Check both dates.';
    }

    final overlapIds = <String>[];
    if (start != null && error == null) {
      final finish = end ?? widget.nowUtc;
      for (final other in widget.otherSessions) {
        if (other.id == widget.original?.id) continue;
        final otherEnd = other.endedAtUtc ?? widget.nowUtc;
        if (start.isBefore(otherEnd) && other.startedAtUtc.isBefore(finish)) {
          overlapIds.add(other.id);
        }
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(23, 9, 23, 27),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.original == null
                    ? 'Add a missed rest'
                    : 'Correct this rest',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose the dates and exact times. Nothing else is changed.',
              ),
              const SizedBox(height: 22),
              _DateTimeControls(
                label: 'Started',
                date: _startDate,
                time: _startTime,
                pickDate: () => _pickDate(true),
                pickTime: () => _pickTime(true),
              ),
              _FoldPicker(
                label: 'Started',
                candidates: starts,
                selected: start,
                onSelected: (utc) => setState(() => _selectedStart = utc),
              ),
              if (widget.original != null) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  title: const Text('Still sleeping'),
                  subtitle: const Text('Leave the wake-up time open'),
                  value: _stillSleeping,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setState(() => _stillSleeping = value),
                ),
              ],
              if (!_stillSleeping) ...[
                const SizedBox(height: 14),
                _DateTimeControls(
                  label: 'Ended',
                  date: _endDate,
                  time: _endTime,
                  pickDate: () => _pickDate(false),
                  pickTime: () => _pickTime(false),
                ),
                _FoldPicker(
                  label: 'Ended',
                  candidates: ends,
                  selected: end,
                  onSelected: (utc) => setState(() => _selectedEnd = utc),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (overlapIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(
                      'Overlaps ${overlapIds.length} other rest '
                      '${overlapIds.length == 1 ? 'record' : 'records'}. '
                      'Both will remain in History until you review them.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: error == null && start != null
                    ? () =>
                          Navigator.pop(context, (startUtc: start, endUtc: end))
                    : null,
                child: Text(
                  widget.original == null ? 'Add rest' : 'Save changes',
                ),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeControls extends StatelessWidget {
  const _DateTimeControls({
    required this.label,
    required this.date,
    required this.time,
    required this.pickDate,
    required this.pickTime,
  });

  final String label;
  final DateTime date;
  final TimeOfDay time;
  final VoidCallback pickDate;
  final VoidCallback pickTime;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final formattedDate = localizations.formatMediumDate(date);
    final formattedTime = time.format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: '$label date, $formattedDate',
                button: true,
                child: OutlinedButton.icon(
                  onPressed: pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(formattedDate, maxLines: 2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: '$label time, $formattedTime',
                button: true,
                child: OutlinedButton.icon(
                  onPressed: pickTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(formattedTime),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FoldPicker extends StatelessWidget {
  const _FoldPicker({
    required this.label,
    required this.candidates,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<WallTimeCandidate> candidates;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    if (candidates.length <= 1) return const SizedBox.shrink();
    return RadioGroup<DateTime>(
      groupValue: selected,
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text('$label happens twice on this date. Choose the correct one:'),
          const SizedBox(height: 8),
          for (var i = 0; i < candidates.length; i++)
            RadioListTile<DateTime>(
              title: Text('${i == 0 ? 'First' : 'Second'} occurrence'),
              subtitle: Text(candidates[i].description),
              value: candidates[i].utc,
            ),
        ],
      ),
    );
  }
}
