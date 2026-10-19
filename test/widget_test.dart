import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
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
