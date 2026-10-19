import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

final class FamilyContext {
  const FamilyContext({required this.familyId, required this.babyId});
  final String familyId;
  final String babyId;
  static FamilyContext? fromData(Map<String, dynamic>? data) {
    if (data == null ||
        data['familyId'] is! String ||
        data['babyId'] is! String) {
      return null;
    }
    return FamilyContext(
      familyId: data['familyId'] as String,
      babyId: data['babyId'] as String,
    );
  }
}

/// A cached family profile is not proof that access has not been revoked.
/// Keep provenance so the UI never implies that offline access was verified.
final class FamilySnapshot {
  const FamilySnapshot({
    required this.family,
    required this.isFromCache,
    this.deletionInProgress = false,
  });
  final FamilyContext? family;
  final bool isFromCache;
  final bool deletionInProgress;
}

/// Family data mutations are exclusively callable Functions; client writes to
/// membership, baby and invitations are forbidden by Firestore Rules.
final class FamilyClient {
  FamilyClient({
    required this.auth,
    required this.firestore,
    required this.functions,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  Stream<FamilySnapshot> watchFamily(String uid) => firestore
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .map(
        (doc) => FamilySnapshot(
          family: FamilyContext.fromData(doc.data()),
          isFromCache: doc.metadata.isFromCache,
          deletionInProgress: doc.data()?['deleting'] == true,
        ),
      );

  Future<FamilyContext?> currentFamily() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await firestore.collection('users').doc(uid).get();
    return FamilyContext.fromData(doc.data());
  }

  Future<void> createFamily(String babyName) async {
    await functions.httpsCallable('createFamily').call<Map<String, dynamic>>({
      'babyName': babyName.trim(),
    });
  }

  Future<void> joinFamily(String code) async {
    await functions.httpsCallable('redeemInvite').call<Map<String, dynamic>>({
      'code': code.trim(),
    });
  }

  Future<({String code, DateTime expiresAt})> createInvite() async {
    final result = await functions
        .httpsCallable('issueInvite')
        .call<Map<String, dynamic>>({});
    final data = result.data;
    return (
      code: data['code'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
    );
  }

  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  Future<void> revokeCaregiver(String uid) async {
    await functions.httpsCallable('revokeMember').call<Map<String, dynamic>>({
      'targetUid': uid,
    });
  }

  /// Removes the household and every nested immutable sleep operation on the
  /// server. It does not delete anyone's Firebase Authentication credentials.
  /// Interrupted deletion remains fenced and can be retried by the owner.
  Future<void> deleteHousehold() async {
    final result = await functions
        .httpsCallable('deleteFamily')
        .call<Map<String, dynamic>>({});
    if (result.data['deleted'] != true) {
      throw StateError('The server did not confirm household deletion.');
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMembers(String familyId) =>
      firestore
          .collection('families')
          .doc(familyId)
          .collection('members')
          .snapshots();

  /// Firebase links the existing anonymous UID; no household data migration.
  /// Existing credentials are NOT silently signed into: that would orphan data.
  Future<void> linkEmailPassword(String email, String password) async {
    final user = auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('Only anonymous accounts can be upgraded here.');
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email.trim(), password: password),
    );
  }

  /// Existing user login is only allowed from the unjoined onboarding state.
  /// Never discard a locally used anonymous family to switch identities.
  Future<void> signInExisting(String email, String password) async {
    if (await currentFamily() != null) {
      throw StateError('This device has a family. Link its account first.');
    }
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  CollectionReference<Map<String, dynamic>> operations(FamilyContext family) =>
      firestore
          .collection('families')
          .doc(family.familyId)
          .collection('babies')
          .doc(family.babyId)
          .collection('operations');
}
