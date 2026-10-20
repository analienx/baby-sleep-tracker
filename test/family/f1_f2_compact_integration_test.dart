import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/family/data/family_client.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'F1 compact sleep action stays reachable with F2 family navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);

      // This exercises the four-tab family shell without contacting Firebase.
      // The sleep action is the F1 layout and the extra Family tab comes from F2.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepRepositoryProvider.overrideWithValue(repository)],
          child: const BabySleepApp(
            family: FamilyContext(familyId: 'family', babyId: 'baby'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      final primary = find.widgetWithText(FilledButton, 'Start sleep');
      expect(primary, findsOneWidget);
      final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(tester.getRect(primary).bottom, lessThan(navTop));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Every little rest.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
