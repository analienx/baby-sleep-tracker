import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No-Functions Spark sharing. An owner's grant is the ONLY server-side
/// authority; the saved journal pointer is a convenience, NEVER an ACL.
final class SparkFamilyLiteController {
  SparkFamilyLiteController({
    required this.auth,
    required this.firestore,
    SharedPreferencesAsync? preferences,
  }) : _prefs = preferences ?? SharedPreferencesAsync();

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final SharedPreferencesAsync _prefs;
  final ValueNotifier<String?> selectedOwnerUid = ValueNotifier(null);
  final ValueNotifier<String?> notice = ValueNotifier(null);
  // A previously joined family must not silently become a writable personal
  // journal if membership cannot be verified after process restart.
  final ValueNotifier<bool> membershipBlocked = ValueNotifier(false);
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _grantSubscription;
  int _revision = 0;
  String? _selectedForUid;

  String get ownUid =>
      auth.currentUser?.uid ??
      (throw StateError('Sign in before managing a family.'));

  String ownerFor(String signedInUid) {
    if (auth.currentUser?.uid != signedInUid ||
        _selectedForUid != signedInUid) {
      return signedInUid;
    }
    return selectedOwnerUid.value ?? signedInUid;
  }

  CollectionReference<Map<String, dynamic>> _grants(String ownerUid) =>
      firestore
          .collection('personalSleep')
          .doc(ownerUid)
          .collection('caregivers');

  Future<void> initialize() async {
    await _restore(auth.currentUser?.uid);
    _authSubscription = auth.authStateChanges().listen(
      (user) => unawaited(_restore(user?.uid)),
    );
  }

  Future<void> _restore(String? uid) async {
    final revision = ++_revision;
    await _grantSubscription?.cancel();
    if (revision != _revision) return;
    _grantSubscription = null;
    membershipBlocked.value = true;
    _selectedForUid = uid;
    selectedOwnerUid.value = null; // Fence the previous user's identity.
    notice.value = null;
    if (uid == null) {
      membershipBlocked.value = false;
      return;
    }
    final saved = await _prefs.getString('spark-lite-owner-$uid');
    if (revision != _revision || auth.currentUser?.uid != uid) return;
    if (saved == null || saved == uid || !_validUid(saved)) {
      membershipBlocked.value = false;
      return;
    }
    if (auth.currentUser?.emailVerified != true) {
      notice.value = 'Verify your email to resume the family journal.';
      return;
    }
    try {
      final grant = await _grants(saved)
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (revision != _revision || auth.currentUser?.uid != uid) return;
      if (!grant.exists || grant.data()?['role'] != 'caregiver') {
        notice.value =
            'Family access was revoked. You may switch back '
            'to your own private journal.';
        return;
      }
      selectedOwnerUid.value = saved;
      membershipBlocked.value = false;
      _watchGrant(saved, uid);
    } on FirebaseException {
      if (revision == _revision) {
        notice.value =
            'Could not verify family membership online. '
            'Reconnect to continue; no records will be written elsewhere.';
      }
    }
  }

  void _watchGrant(String owner, String caregiver) {
    unawaited(_grantSubscription?.cancel());
    _grantSubscription = _grants(owner)
        .doc(caregiver)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (grant) {
            if (auth.currentUser?.uid != caregiver ||
                selectedOwnerUid.value != owner)
              return;
            // A cached event is NOT evidence of revocation. Queued offline edits
            // still require later server authorization before being called synced.
            if (grant.metadata.isFromCache) {
              return;
            }
            if (!grant.exists || grant.data()?['role'] != 'caregiver') {
              membershipBlocked.value = true;
              notice.value =
                  'The owner revoked your access. '
                  'Shared records are no longer available.';
            }
          },
          onError: (_) {
            membershipBlocked.value = true;
            notice.value =
                'Family permission could not be verified. Reconnect.';
          },
        );
  }

  Future<void> refreshMembership() => _restore(auth.currentUser?.uid);

  static bool _validUid(String uid) =>
      uid.length >= 8 &&
      uid.length <= 128 &&
      RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(uid);

  void _requireVerified() {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      throw StateError(
        'Protect this account and verify its email before sharing.',
      );
    }
  }

  Future<void> approveCaregiver(String caregiverUid) async {
    _requireVerified();
    final ownerUid = ownUid;
    final uid = caregiverUid.trim();
    if (!_validUid(uid) || uid == ownerUid) {
      throw StateError('Enter the other parent’s complete caregiver ID.');
    }
    if (ownerFor(ownerUid) != ownerUid) {
      throw StateError('Only your own journal can grant caregiver access.');
    }
    // Permanent marker also protects this shared journal from deletion by
    // old personal-only app versions (which lack cross-device write fences).
    final marker = firestore
        .collection('personalSleep')
        .doc(ownerUid)
        .collection('sharing')
        .doc('state');
    final existingMarker = await marker.get(
      const GetOptions(source: Source.server),
    );
    if (!existingMarker.exists) {
      await marker.set({
        'enabled': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    // Cloud-confirm membership listing; do not silently count an offline cache.
    final members = await _grants(ownerUid)
        .limit(2)
        .get(const GetOptions(source: Source.server));
    if (members.docs.isNotEmpty && !members.docs.any((d) => d.id == uid)) {
      throw StateError('Family Lite currently supports one other caregiver.');
    }
    await _grants(ownerUid).doc(uid).set({
      'uid': uid,
      'role': 'caregiver',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> revokeCaregiver(String caregiverUid) async {
    _requireVerified();
    if (ownerFor(ownUid) != ownUid) {
      throw StateError('Only the journal owner can revoke a caregiver.');
    }
    // Revoke the server grant, never merely hide the person in the UI.
    await _grants(ownUid).doc(caregiverUid).delete();
  }

  Future<void> joinOwner(String ownerUidInput) async {
    _requireVerified();
    final uid = ownUid;
    final ownerUid = ownerUidInput.trim();
    if (!_validUid(ownerUid) || ownerUid == uid) {
      throw StateError('Enter the other parent’s complete owner ID.');
    }
    final grant = await _grants(ownerUid)
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!grant.exists || grant.data()?['role'] != 'caregiver') {
      throw StateError('This owner has not approved your caregiver ID.');
    }
    await _prefs.setString('spark-lite-owner-$uid', ownerUid);
    _selectedForUid = uid;
    selectedOwnerUid.value = ownerUid;
    membershipBlocked.value = false;
    notice.value = null;
    _watchGrant(ownerUid, uid);
  }

  Future<void> leaveSharedJournal() async {
    final uid = ownUid;
    await _prefs.remove('spark-lite-owner-$uid');
    await _grantSubscription?.cancel();
    _grantSubscription = null;
    _selectedForUid = uid;
    selectedOwnerUid.value = null;
    membershipBlocked.value = false;
    notice.value = null;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _grantSubscription?.cancel();
    membershipBlocked.dispose();
    selectedOwnerUid.dispose();
    notice.dispose();
  }
}
