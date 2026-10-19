import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_ledger.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/history_editor.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/presentation_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clock.dart';

Widget appForTest({PreviewSleepRepository? repository, FakeClock? clock}) =>
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(
          clock ?? FakeClock(DateTime.utc(2026, 10, 19, 10)),
        ),
        sleepRepositoryProvider.overrideWithValue(
          repository ?? PreviewSleepRepository(),
        ),
      ],
      child: const BabySleepApp(),
    );

void main() {
  testWidgets('Today, History and Trends are reachable from the main nav', (
    tester,
  ) async {
    await tester.pumpWidget(appForTest());
    await tester.pumpAndSettle();
    expect(find.text("Today's sleep."), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Every little rest.'), findsOneWidget);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('Finding a rhythm.'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Start sleep'), findsOneWidget);
  });

  testWidgets('Start and stop are a single tap and visible in History', (
    tester,
  ) async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 10));
    await tester.pumpWidget(appForTest(clock: clock));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start sleep'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Wake up'), findsOneWidget);

    clock.advance(const Duration(minutes: 35));
    await tester.tap(find.text('Wake up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Start sleep'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('0h 35m'), findsOneWidget);
  });

  for (final scenario in [
    (size: const Size(320, 568), textScale: 1.0),
    (size: const Size(360, 640), textScale: 1.0),
    (size: const Size(375, 667), textScale: 1.0),
    (size: const Size(390, 844), textScale: 1.6),
    (size: const Size(320, 568), textScale: 2.0),
  ]) {
    testWidgets('Primary action remains visible at ${scenario.size} '
        'with ${scenario.textScale}x text', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.textScale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(appForTest());
      await tester.pumpAndSettle();

      final action = find.widgetWithText(FilledButton, 'Start sleep');
      expect(action, findsOneWidget);
      final bounds = tester.getRect(action);
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThan(navigationTop));
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.widgetWithText(FilledButton, 'Wake up'), findsOneWidget);
    });
  }

  testWidgets('elapsed ticker stops when backgrounded and resyncs on resume', (
    tester,
  ) async {
    final clock = FakeClock(DateTime.utc(2026, 10, 19, 10));
    await tester.pumpWidget(appForTest(clock: clock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start sleep'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    clock.advance(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:00:15'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:00:15'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('00:02:15'), findsOneWidget);
  });

  testWidgets('compact Today keeps backdate alongside the sticky action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(appForTest(repository: repository));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Start sleep'), findsOneWidget);
    final backdate = find.byTooltip('Backdate sleep start');
    expect(backdate, findsOneWidget);
    final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    expect(tester.getRect(backdate).bottom, lessThan(navigationTop));
    await tester.tap(backdate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start 5 min ago'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(FilledButton, 'Wake up'), findsOneWidget);
    expect((await repository.readSessions()).length, 1);
  });

  testWidgets('conflicting active sessions block the sticky toggle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    await repository.put(
      SleepSession(
        id: 'one',
        startedAtUtc: DateTime.utc(2026, 10, 19, 9),
        endedAtUtc: null,
      ),
    );
    await repository.put(
      SleepSession(
        id: 'two',
        startedAtUtc: DateTime.utc(2026, 10, 19, 9, 30),
        endedAtUtc: null,
      ),
    );
    await tester.pumpWidget(appForTest(repository: repository));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Review History'), findsOneWidget);
    expect(find.byTooltip('Backdate sleep start'), findsNothing);
    await tester.tap(find.text('Review History'));
    await tester.pumpAndSettle();
    expect(find.text('Every little rest.'), findsOneWidget);
    expect((await repository.readSessions()).length, 2);
  });

  testWidgets('History labels both sides of a cross-midnight session', (
    tester,
  ) async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final start = DateTime.utc(2026, 10, 19, 12);
    final end = DateTime.utc(2026, 10, 20, 12);
    await repository.put(
      SleepSession(id: 'cross-day', startedAtUtc: start, endedAtUtc: end),
    );

    await tester.pumpWidget(appForTest(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Every little rest.'));
    final localizations = MaterialLocalizations.of(context);
    final subtitle =
        '${localizations.formatMediumDate(start.toLocal())} '
        '${formatLocalTime(context, start)} → '
        '${localizations.formatMediumDate(end.toLocal())} '
        '${formatLocalTime(context, end)}';
    expect(find.text(subtitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'History adds missed rest, deletes after confirmation, restores',
    (tester) async {
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(appForTest(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('A fresh start'), findsOneWidget);

      await tester.tap(find.text('Add a missed rest'));
      await tester.pumpAndSettle();
      expect(find.text('Add a missed rest'), findsNWidgets(2));
      expect(find.text('Started'), findsOneWidget);
      expect(find.text('Ended'), findsOneWidget);
      await tester.tap(find.text('Add rest'));
      await tester.pumpAndSettle();
      expect(await repository.readSessions(), hasLength(1));
      expect(find.text('0h 30m'), findsOneWidget);

      await tester.tap(find.byTooltip('Correct or remove rest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove rest').last);
      await tester.pumpAndSettle();
      expect(find.text('Remove this rest?'), findsOneWidget);
      await tester.tap(find.text('Keep rest'));
      await tester.pumpAndSettle();
      expect(await repository.readSessions(), hasLength(1));

      await tester.tap(find.byTooltip('Correct or remove rest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove rest').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove rest'));
      await tester.pumpAndSettle();
      expect(await repository.readSessions(), isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await repository.readSessions(), hasLength(1));
    },
  );

  testWidgets('History keeps crossed-midnight record and highlights overlaps', (
    tester,
  ) async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    await repository.put(
      SleepSession(
        id: 'crosses-midnight',
        startedAtUtc: DateTime(2026, 10, 18, 23, 50).toUtc(),
        endedAtUtc: DateTime(2026, 10, 19, 0, 30).toUtc(),
      ),
    );
    await repository.put(
      SleepSession(
        id: 'other',
        startedAtUtc: DateTime(2026, 10, 19, 0, 10).toUtc(),
        endedAtUtc: DateTime(2026, 10, 19, 0, 40).toUtc(),
      ),
    );
    await tester.pumpWidget(appForTest(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Across midnight · one rest'), findsOneWidget);
    expect(find.text('Overlaps another rest — review times'), findsNWidgets(2));
    expect(find.text('0h 40m'), findsOneWidget);
    expect(find.text('0h 30m'), findsOneWidget);
  });

  testWidgets(
    'History correction editor exposes accessible date/time controls',
    (tester) async {
      final handle = tester.ensureSemantics();
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);
      await repository.put(
        SleepSession(
          id: 'review',
          startedAtUtc: DateTime.utc(2026, 10, 19, 8),
          endedAtUtc: DateTime.utc(2026, 10, 19, 9),
        ),
      );
      await tester.pumpWidget(appForTest(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Correct or remove rest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit times'));
      await tester.pumpAndSettle();
      expect(find.text('Correct this rest'), findsOneWidget);
      for (final endpoint in ['Started', 'Ended']) {
        for (final field in ['date', 'time']) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  (widget.properties.label ?? '').startsWith(
                    '$endpoint $field,',
                  ),
            ),
            findsOneWidget,
          );
        }
      }
      // Explicit active flag must not be toggled as a side effect of editing.
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      handle.dispose();
    },
  );

  testWidgets('Competing versions require an explicit caregiver selection', (
    tester,
  ) async {
    final first = SleepSession(
      id: 'conflicted',
      startedAtUtc: DateTime.utc(2026, 10, 19, 7),
      endedAtUtc: DateTime.utc(2026, 10, 19, 8),
    );
    final second = first.corrected(
      startUtc: DateTime.utc(2026, 10, 19, 7, 10),
      endUtc: DateTime.utc(2026, 10, 19, 8, 10),
    );
    final conflict = SleepConflict(
      sessionId: 'conflicted',
      heads: [
        SleepOperation(
          id: 'head-a',
          actorId: 'synthetic',
          session: first,
          recordedAtUtc: DateTime.utc(2026, 10, 19, 9),
        ),
        SleepOperation(
          id: 'head-b',
          actorId: 'synthetic',
          session: second,
          recordedAtUtc: DateTime.utc(2026, 10, 19, 9),
        ),
      ],
      commonAncestor: null,
    );
    final repository = _ConflictRepository(conflict);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(
            FakeClock(DateTime.utc(2026, 10, 19, 10)),
          ),
          sleepRepositoryProvider.overrideWithValue(repository),
        ],
        child: const BabySleepApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 2 versions of a rest'));
    await tester.pumpAndSettle();
    expect(find.text('Keep selected version'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Keep selected version'),
    );
    expect(confirm.onPressed, isNull);
    await tester.tap(find.text('Version 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep selected version'));
    await tester.pumpAndSettle();
    expect(repository.chosen, second);
  });

  testWidgets('Invalid future correction is visible and cannot be saved', (
    tester,
  ) async {
    final original = SleepSession(
      id: 'clock-moved-back',
      startedAtUtc: DateTime.utc(2026, 10, 19, 10),
      endedAtUtc: DateTime.utc(2026, 10, 19, 11),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryEditor(
            original: original,
            otherSessions: const [],
            nowUtc: DateTime.utc(2026, 10, 19, 10, 30),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('A sleep record cannot be in the future.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Quick backdate is explicit and undo removes the preview record',
    (tester) async {
      final clock = FakeClock(DateTime.utc(2026, 10, 19, 10));
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(appForTest(clock: clock, repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earlier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start 10 min ago'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        (await repository.readSessions()).single.startedAtUtc,
        DateTime.utc(2026, 10, 19, 9, 50),
      );
      expect(find.text('Wake up'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo last change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(await repository.readSessions(), isEmpty);
    },
  );

  testWidgets(
    'One-handed primary control and preview disclosure have semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(appForTest());
      await tester.pumpAndSettle();

      final primary = tester.getSize(
        find.widgetWithText(FilledButton, 'Start sleep'),
      );
      expect(primary.height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('No sleep recorded'), findsOneWidget);
      await tester.ensureVisible(find.byType(PreviewWarning));
      await tester.pumpAndSettle();
      final warningSemantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(PreviewWarning),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(warningSemantics.properties.label, contains('not saved'));
      handle.dispose();
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('$brightness Today visual baseline', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });

      await tester.pumpWidget(appForTest());
      await tester.pumpAndSettle();
      // A tired parent must not scroll to reach the only primary action.
      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'Start sleep'),
      );
      expect(button.bottom, lessThan(844 - 76));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/today_${brightness.name}.png'),
      );
    });
  }
}

final class _ConflictRepository implements SleepRepository {
  _ConflictRepository(this.conflict);

  final SleepConflict conflict;
  SleepSession? chosen;

  @override
  Stream<List<SleepSession>> watchSessions() => Stream.value(const []);

  @override
  Future<List<SleepSession>> readSessions() async => const [];

  @override
  Stream<List<SleepConflict>> watchConflicts() => Stream.value([conflict]);

  @override
  Stream<SleepStorageStatus> watchStorageStatus() =>
      Stream.value(const SleepStorageStatus(StoragePhase.preview));

  @override
  Future<void> put(SleepSession session) => Future.error(UnimplementedError());

  @override
  Future<void> remove(String id) => Future.error(UnimplementedError());

  @override
  Future<void> resolveConflict(
    SleepConflict conflict,
    SleepSession? selected,
  ) async {
    chosen = selected;
  }
}
