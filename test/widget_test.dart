import 'dart:async';

import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/app/theme.dart';
import 'package:baby_sleep_tracker/features/personal/data/spark_baby_profiles.dart';
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
import 'package:shared_preferences_platform_interface/types.dart';

import 'support/fake_clock.dart';

Widget appForTest({
  PreviewSleepRepository? repository,
  FakeClock? clock,
  List<SparkBabyProfile>? profiles,
  String? selectedBaby,
  Future<void> Function(String)? onBabyChanged,
}) => ProviderScope(
  overrides: [
    clockProvider.overrideWithValue(
      clock ?? FakeClock(DateTime.utc(2026, 10, 19, 10)),
    ),
    sleepRepositoryProvider.overrideWithValue(
      repository ?? PreviewSleepRepository(),
    ),
  ],
  child: BabySleepApp(
    babyProfiles: profiles,
    selectedBabyId: selectedBaby,
    onBabyChanged: onBabyChanged,
  ),
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
  test('light palette meets readable primary, secondary and body contrast', () {
    double contrast(Color a, Color b) {
      final l1 = a.computeLuminance();
      final l2 = b.computeLuminance();
      return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) /
          (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
    }

    final scheme = SleepTheme.light().colorScheme;
    expect(
      contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.secondary, scheme.onSecondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(7));
    expect(
      contrast(scheme.onSurfaceVariant, scheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('Baby switcher makes the current child explicit', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      appForTest(
        profiles: const [
          SparkBabyProfile.primary,
          SparkBabyProfile(id: 'baby-two-2026', name: 'Baby 2'),
        ],
        selectedBaby: SparkBabyProfile.primaryId,
        onBabyChanged: (id) async {
          selected.add(id);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Baby 1'), findsWidgets);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baby 2').last);
    await tester.pumpAndSettle();
    expect(selected, ['baby-two-2026']);
  });

  testWidgets('Light mode keeps the active sleep panel bright and readable', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(appForTest());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start sleep'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('SLEEPING NOW'), findsOneWidget);
    final card = find
        .ancestor(
          of: find.text('SLEEPING NOW'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        )
        .first;
    final gradient =
        (tester.widget<Container>(card).decoration! as BoxDecoration).gradient!
            as LinearGradient;
    expect(gradient.colors.first, const Color(0xFFE8E0F6));
    expect(gradient.colors.last, const Color(0xFFF1EBFA));
    final timerText = tester.widget<Text>(find.text('00:00:00'));
    expect(timerText.style!.color, SleepTheme.light().colorScheme.onSurface);
    final wake = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Wake up'),
    );
    final wakeBackground = wake.style!.backgroundColor!.resolve({});
    expect(wakeBackground, SleepTheme.light().colorScheme.primary);
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

  testWidgets('Trends show logged days, not misleading empty full-day bars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = PreviewSleepRepository();
    addTearDown(repository.dispose);
    await repository.put(
      SleepSession(
        id: 'thursday',
        startedAtUtc: DateTime.utc(2026, 10, 22, 8),
        endedAtUtc: DateTime.utc(2026, 10, 22, 11, 14),
      ),
    );
    await repository.put(
      SleepSession(
        id: 'friday',
        startedAtUtc: DateTime.utc(2026, 10, 23, 3),
        endedAtUtc: DateTime.utc(2026, 10, 23, 9, 42),
      ),
    );
    await tester.pumpWidget(
      appForTest(
        repository: repository,
        clock: FakeClock(DateTime.utc(2026, 10, 23, 11)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Today with two recorded sessions must fit a 390px phone',
    );
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Trends with two logged days must fit a 390px phone',
    );
    expect(find.text('2 of 7 days with entries'), findsOneWidget);
    expect(find.text('6h 42m'), findsWidgets);
    expect(find.text('3h 14m'), findsWidgets);
    expect(find.textContaining('5 other days have no entries'), findsOneWidget);
    expect(
      find.byType(FractionallySizedBox),
      findsNWidgets(2),
      reason: 'Only logged days should have bars; missing days are unknown.',
    );
    final loggedDayFill = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox && widget.color == SleepPalette.daytimeChart,
    );
    expect(loggedDayFill, findsOneWidget);
    expect(
      tester.getSize(loggedDayFill).height,
      greaterThanOrEqualTo(9),
      reason: 'A chart fill must paint, not collapse to zero height.',
    );
    expect(tester.getSize(loggedDayFill).width, greaterThan(0));
    expect(tester.takeException(), isNull);
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

  testWidgets('Rapid theme taps persist in the same order as the last choice', (
    tester,
  ) async {
    final prefs = _SlowPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    await tester.pumpWidget(appForTest());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings and privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(prefs.startedWrites, 1, reason: 'Second write must be queued');
    prefs.releaseFirst.complete();
    await tester.pumpAndSettle();
    expect(prefs.startedWrites, 2);
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
    final earlierLabel = find.text('Earlier');
    expect(
      tester.widget<Text>(earlierLabel).style?.color,
      Theme.of(tester.element(earlierLabel)).colorScheme.onSurface,
    );
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

  testWidgets('An older disputed nap never disables the current sleep action', (
    tester,
  ) async {
    final disputed = SleepSession(
      id: 'old-nap',
      startedAtUtc: DateTime.utc(2026, 10, 18, 7),
      endedAtUtc: DateTime.utc(2026, 10, 18, 8),
    );
    final conflict = SleepConflict(
      sessionId: disputed.id,
      heads: [
        SleepOperation(
          id: 'old-a',
          actorId: 'one',
          session: disputed,
          recordedAtUtc: DateTime.utc(2026, 10, 18, 9),
        ),
        SleepOperation(
          id: 'old-b',
          actorId: 'two',
          session: disputed.corrected(
            startUtc: DateTime.utc(2026, 10, 18, 7, 5),
            endUtc: DateTime.utc(2026, 10, 18, 8, 5),
          ),
          recordedAtUtc: DateTime.utc(2026, 10, 18, 9),
        ),
      ],
      commonAncestor: null,
    );
    final active = SleepSession(
      id: 'live-nap',
      startedAtUtc: DateTime.utc(2026, 10, 19, 9, 30),
      endedAtUtc: null,
    );
    final repository = _ConflictRepository(conflict, sessions: [active]);
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
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Wake up'),
    );
    expect(action.onPressed, isNotNull);
    expect(find.textContaining('competing edit(s) preserved'), findsOneWidget);
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

base class _SlowPreferences extends InMemorySharedPreferencesAsync {
  _SlowPreferences() : super.empty();

  final Completer<void> releaseFirst = Completer<void>();
  int startedWrites = 0;

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    startedWrites++;
    if (startedWrites == 1) await releaseFirst.future;
    return super.setString(key, value, options);
  }
}

final class _ConflictRepository implements SleepRepository {
  _ConflictRepository(this.conflict, {this.sessions = const []});

  final SleepConflict conflict;
  final List<SleepSession> sessions;
  SleepSession? chosen;

  @override
  Stream<List<SleepSession>> watchSessions() => Stream.value(sessions);

  @override
  Future<List<SleepSession>> readSessions() async => sessions;

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
