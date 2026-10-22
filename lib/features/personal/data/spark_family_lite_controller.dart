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
  StreamSubscription<User?>? _authSubscription;
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
    _selectedForUid = uid;
    selectedOwnerUid.value = null; // Clear previous user's journal immediately.
    notice.value = null;
    if (uid == null) return;
    final saved = await _prefs.getString('spark-lite-owner-$uid');
    if (saved == null || saved == uid || !_validUid(saved)) return;
    if (auth.currentUser?.emailVerified != true) {
      notice.value = 'Verify your email to restore the shared family journal.';
      return;
    }
    try {
      final grant = await _grants(saved)
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (revision != _revision || auth.currentUser?.uid != uid) return;
      if (!grant.exists || grant.data()?['role'] != 'caregiver') {
        notice.value =
            'Family access is no longer verified. Showing your own journal.';
        return;
      }
      selectedOwnerUid.value = saved;
    } on FirebaseException {
      if (revision == _revision) {
        notice.value =
            'Shared membership could not be verified online. '
            'Showing your own journal until you reconnect.';
      }
    }
  }

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
    // Cloud-confirm membership listing; do not silently count an offline cache.
    final members = await _grants(ownerUid)
        .limit(2)
        .get(const GetOptions(source: Source.server));
    if (members.docs.length >= 1 && !members.docs.any((d) => d.id == uid)) {
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
    notice.value = null;
  }

  Future<void> leaveSharedJournal() async {
    final uid = ownUid;
    await _prefs.remove('spark-lite-owner-$uid');
    _selectedForUid = uid;
    selectedOwnerUid.value = null;
    notice.value = null;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    selectedOwnerUid.dispose();
    notice.dispose();
  }
}
