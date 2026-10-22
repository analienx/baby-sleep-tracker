import 'package:baby_sleep_tracker/features/personal/data/spark_baby_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SparkBabyProfile.hasNestedOperations', () {
    test('primary baby keeps its journal at the legacy root', () {
      // Regression control: account erasure queried
      // babies/primary/operations for every profile. Firestore Rules deny
      // listing that nested collection (split-journal guard), so the query
      // aborted erasure for any owner who had renamed Baby 1.
      expect(SparkBabyProfile.hasNestedOperations('primary'), isFalse);
      expect(SparkBabyProfile.primary.isPrimary, isTrue);
    });

    test('additional babies nest operations under their profile', () {
      expect(
        SparkBabyProfile.hasNestedOperations(
          '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
        ),
        isTrue,
      );
      const extra = SparkBabyProfile(id: 'child-alpha-20261022', name: 'A');
      expect(extra.isPrimary, isFalse);
    });
  });
}