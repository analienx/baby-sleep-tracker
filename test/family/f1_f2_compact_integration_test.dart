import 'package:baby_sleep_tracker/app/app.dart';
import 'package:baby_sleep_tracker/app/providers.dart';
import 'package:baby_sleep_tracker/features/family/data/family_client.dart';
import 'package:baby_sleep_tracker/features/sleep/data/preview_sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
    'F1 compact sleep action stays reachable after F2 family integration',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = PreviewSleepRepository();
      addTearDown(repository.dispose);

      // The Family management route is reached from Settings, not a fourth
      // bottom destination. This verifies the compact three-tab navigation
      // with F2 family context, without contacting Firebase.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepRepositoryProvider.overrideWithValue(repository)],
          child: const BabySleepApp(
            family: FamilyContext(familyId: 'family', babyId: 'baby'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(3));
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
