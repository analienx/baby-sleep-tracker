import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/app/theme.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_ledger.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/history_editor.dart';
import 'package:baby_sleep_tracker/features/sleep/presentation/presentation_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('sleep chart marks exceed 3:1 non-text contrast on both themes', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
    }

    expect(
      contrast(
        SleepPalette.daytimeChart,
        SleepTheme.light().colorScheme.surfaceContainerHighest,
      ),
      greaterThanOrEqualTo(3),
    );
    expect(
      contrast(
        SleepPalette.sage,
        SleepTheme.dark().colorScheme.surfaceContainerHighest,
      ),
      greaterThanOrEqualTo(3),
    );
  });
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

  testWidgets(
    'Settings are reachable, but unimplemented family actions are disabled',
    (tester) async {
      await tester.pumpWidget(appForTest());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings and privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Settings & privacy'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Invite a caregiver'), 200);
      final invite = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Invite a caregiver'),
      );
      expect(invite.enabled, isFalse);
      await tester.scrollUntilVisible(find.text('Share JSON'), 200);
      expect(find.text('Share JSON'), findsOneWidget);
      expect(find.text('Share CSV'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Delete household data'), 200);
      final delete = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Delete household data'),
      );
      expect(delete.enabled, isFalse);
    },
  );

  testWidgets('Trends distinguish zero logs from recorded sleep', (
    tester,
  ) async {
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(appForTest(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('A little story starts here'), findsOneWidget);
    expect(find.text('No entries'), findsOneWidget);

    await repository.put(
      SleepSession(
        id: 'one',
        startedAtUtc: DateTime.utc(2026, 10, 19, 8),
        endedAtUtc: DateTime.utc(2026, 10, 19, 9),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('The last seven days'), findsOneWidget);
    expect(find.text('1h 0m'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('day not yet complete')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Appearance changes to dark and can be restored to system', (
    tester,
  ) async {
    await tester.pumpWidget(appForTest());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings and privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(appForTest());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.byTooltip('Settings and privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow my phone'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  testWidgets(
    'Compact high-text-scale view retains accessible primary action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(appForTest());
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FilledButton, 'Start sleep');
      expect(action, findsOneWidget);
      final rect = tester.getRect(action);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.bottom, lessThan(568 - 76));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

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

    testWidgets('$brightness Trends visual baseline', (tester) async {
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
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/trends_${brightness.name}.png'),
      );
    });

    testWidgets('$brightness Settings visual baseline', (tester) async {
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
      await tester.tap(find.byTooltip('Settings and privacy'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_${brightness.name}.png'),
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
