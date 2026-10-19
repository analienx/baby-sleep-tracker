import 'package:baby_sleep_tracker/features/family/data/family_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cached membership keeps cache provenance and does not imply verification',
    () {
      const stale = FamilySnapshot(
        family: FamilyContext(familyId: 'family', babyId: 'baby'),
        isFromCache: true,
      );
      expect(stale.family?.familyId, 'family');
      expect(stale.isFromCache, isTrue);
      expect(FamilyContext.fromData(null), isNull);
      expect(FamilyContext.fromData({'familyId': 'only'}), isNull);
      expect(
        FamilyContext.fromData({'familyId': 'family', 'babyId': 'baby'})
            ?.babyId,
        'baby',
      );
    },
  );
}
