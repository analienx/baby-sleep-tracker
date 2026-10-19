import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
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
    final subtitle =
        '${formatLocalDateTime(context, start)} — '
        '${formatLocalDateTime(context, end)}';
    expect(find.text(subtitle), findsOneWidget);
    expect(tester.takeException(), isNull);
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
