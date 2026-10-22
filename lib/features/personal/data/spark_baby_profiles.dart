import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Legacy sleep operations deliberately stay in /personalSleep/{owner}/operations.
/// The virtual first baby reads that collection WITHOUT migrating old records.
final class SparkBabyProfile {
  const SparkBabyProfile({required this.id, required this.name});
  static const primaryId = 'primary';
  static const primary = SparkBabyProfile(id: primaryId, name: 'Baby 1');

  final String id;
  final String name;

  bool get isPrimary => id == primaryId;
}

/// Owner-scoped profiles shared by the caregiver using existing Family Lite
/// grants. No account, Firebase project or password is created per child.
final class SparkBabyProfiles {
  SparkBabyProfiles({
    required this.auth,
    required this.firestore,
    required this.ownerUid,
    SharedPreferencesAsync? preferences,
  }) : _prefs = preferences ?? SharedPreferencesAsync();

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final String ownerUid;
  final SharedPreferencesAsync _prefs;

  CollectionReference<Map<String, dynamic>> get collection =>
      firestore.collection('personalSleep').doc(ownerUid).collection('babies');

  bool get canManage => auth.currentUser?.uid == ownerUid;

  String _selectionKey(String actorUid) =>
      'little-rest-selected-baby-v1-$actorUid-$ownerUid';

  Stream<List<SparkBabyProfile>> watch() =>
      collection.snapshots(includeMetadataChanges: true).map((snapshot) {
        var primary = SparkBabyProfile.primary;
        final others = <SparkBabyProfile>[];
        for (final doc in snapshot.docs) {
          final name = doc.data()['name'];
          if (name is! String || name.trim().isEmpty || name.length > 40) {
            continue;
          }
          final profile = SparkBabyProfile(id: doc.id, name: name);
          if (doc.id == SparkBabyProfile.primaryId) {
            primary = profile;
          } else {
            others.add(profile);
          }
        }
        others.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return [primary, ...others];
      });

  Future<String> restoreSelection(String actorUid) async {
    final stored = await _prefs.getString(_selectionKey(actorUid));
    if (stored == null || stored == SparkBabyProfile.primaryId) {
      return SparkBabyProfile.primaryId;
    }
    if (!_validId(stored)) {
      throw StateError('Stored baby ID is invalid. Select your baby again.');
    }
    // Never silently fall back to Baby 1 if this saved child is unavailable.
    // A cold-start after account switch must confirm the same scoped profile
    // before enabling Start/Wake or editing earlier sessions.
    final profile = await collection
        .doc(stored)
        .get(const GetOptions(source: Source.server));
    if (!profile.exists || profile.data()?['name'] is! String) {
      throw StateError(
        'The previously selected baby could not be verified. '
        'Reconnect or explicitly select Baby 1.',
      );
    }
    return stored;
  }

  Future<void> saveSelection(String actorUid, String babyId) async {
    if (babyId != SparkBabyProfile.primaryId && !_validId(babyId)) {
      throw StateError('Invalid baby selection.');
    }
    await _prefs.setString(_selectionKey(actorUid), babyId);
  }

  Future<String> add(String name) async {
    _requireOwner();
    final clean = _checkedName(name);
    final id = const Uuid().v4();
    await collection.doc(id).set({
      'name': clean,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> rename(String id, String name) async {
    _requireOwner();
    if (id != SparkBabyProfile.primaryId && !_validId(id)) {
      throw StateError('Invalid baby ID.');
    }
    final clean = _checkedName(name);
    final ref = collection.doc(id);
    if (id == SparkBabyProfile.primaryId) {
      final existing = await ref.get(const GetOptions(source: Source.server));
      if (!existing.exists) {
        await ref.set({
          'name': clean,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }
    }
    await ref.update({'name': clean});
  }

  void _requireOwner() {
    if (!canManage || auth.currentUser == null) {
      throw StateError('Only the household owner may manage baby profiles.');
    }
  }

  static String _checkedName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 40) {
      throw StateError('Enter a baby name between 1 and 40 characters.');
    }
    return name;
  }

  static bool _validId(String id) =>
      id.length >= 8 &&
      id.length <= 128 &&
      RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);
}
