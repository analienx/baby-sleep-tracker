import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Spark-compatible, private-per-UID storage. No client-side family
/// membership or invitation mutations are permitted.
final class PersonalCloudClient {
  PersonalCloudClient({
    required this.auth,
    required this.firestore,
    this.familyLiteEnabled = false,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final bool familyLiteEnabled;
  final ValueNotifier<String?> deletionNotice = ValueNotifier(null);
  // While deleting, unmount the sleep workspace to prevent local UI writes
  // racing with self-erasure. Other devices still require server fencing.
  final ValueNotifier<bool> deletionInProgress = ValueNotifier(false);

  CollectionReference<Map<String, dynamic>> operations(String uid) =>
      firestore.collection('personalSleep').doc(uid).collection('operations');

  Future<void> linkEmailPassword(String email, String password) async {
    final user = auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError(
        'This account is already protected, or you are signed out.',
      );
    }
    if (password.length < 12) {
      throw StateError('Use a password of at least 12 characters.');
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email.trim(), password: password),
    );
    await auth.currentUser?.sendEmailVerification();
  }

  Future<void> sendVerificationEmail() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Protect your account with email first.');
    }
    await user.sendEmailVerification();
  }

  Future<void> refreshVerification() async {
    await auth.currentUser?.reload();
    await auth.currentUser?.getIdToken(true);
  }

  Future<void> resetPassword(String email) async {
    await auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Refuses to abandon any records from an anonymous account. Server reads
  /// are required: an offline/missing cache must never be mistaken for empty.
  Future<void> signInExisting(String email, String password) async {
    final previous = auth.currentUser;
    if (previous != null) {
      if (!previous.isAnonymous) {
        throw StateError('This device is already signed into an account.');
      }
      final docs = operations(previous.uid).limit(1);
      try {
        final cached = await docs.get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty || cached.metadata.hasPendingWrites) {
          throw StateError(
            'This device has sleep records. Protect this account first; switching would orphan them.',
          );
        }
        final confirmed = await docs.get(
          const GetOptions(source: Source.server),
        );
        if (confirmed.docs.isNotEmpty) {
          throw StateError(
            'This account already has cloud sleep records. Protect it instead of switching.',
          );
        }
      } on FirebaseException {
        throw StateError(
          'Reconnect to verify the empty account before switching identities.',
        );
      }
    }
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Explicitly erases the owner's private operation journal online before
  /// deleting their Firebase Auth identity. Failures preserve the identity
  /// for retry; never call Auth.delete while any operation remains on-server.
  Future<void> deleteAccount({String? password}) async {
    if (deletionInProgress.value) {
      throw StateError('Account deletion is already in progress.');
    }
    deletionInProgress.value = true;
    try {
      await _deleteAccountOnline(password: password);
    } catch (_) {
      // The account view was intentionally unmounted during erasure, so its
      // local error snackbar cannot survive. Preserve a recoverable notice.
      deletionNotice.value ??=
          'Account deletion could not be verified. Some records may already '
          'be erased. Reconnect and retry from Account.';
      rethrow;
    } finally {
      deletionInProgress.value = false;
    }
  }

  Future<void> _deleteAccountOnline({String? password}) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('You must be signed in.');
    if (!user.isAnonymous) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw StateError('Enter your account password to confirm deletion.');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      await user.getIdToken(true);
    }

    // Refuse deletion while an offline operation is still queued. Otherwise
    // the Auth user might disappear before the queued write is acknowledged.
    await firestore.waitForPendingWrites().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError(
        'Pending offline edits must sync before account deletion. Reconnect and retry.',
      ),
    );

    if (familyLiteEnabled) {
      // Server-acknowledged irreversible fence prevents other devices from
      // appending while this owner is erasing their journal.
      final root = firestore.collection('personalSleep').doc(user.uid);
      final fence = root.collection('control').doc('state');
      final existing = await fence.get(const GetOptions(source: Source.server));
      if (!existing.exists) {
        await fence.set({
          'deleting': true,
          'requestedAt': FieldValue.serverTimestamp(),
        });
      }
      // A revoked member cannot read/write the cloud journal. Delete every
      // grant before deleting operations; own Auth removal is always last.
      final grants = root.collection('caregivers');
      while (true) {
        final page = await grants
            .limit(100)
            .get(const GetOptions(source: Source.server));
        if (page.docs.isEmpty) break;
        final batch = firestore.batch();
        for (final member in page.docs) {
          batch.delete(member.reference);
        }
        await batch.commit();
      }
      final verified = await grants
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (verified.docs.isNotEmpty) {
        throw StateError('Caregiver revocation could not be verified.');
      }
    }

    if (familyLiteEnabled) {
      // Each additional baby has its own immutable journal. Erase child
      // operations before the profile; erasing only the legacy root would
      // leave child data behind after removing the Auth identity.
      final babies = firestore
          .collection('personalSleep')
          .doc(user.uid)
          .collection('babies');
      while (true) {
        final profiles = await babies
            .limit(50)
            .get(const GetOptions(source: Source.server));
        if (profiles.docs.isEmpty) break;
        for (final baby in profiles.docs) {
          final childOps = baby.reference.collection('operations');
          while (true) {
            final page = await childOps
                .limit(200)
                .get(const GetOptions(source: Source.server));
            if (page.docs.isEmpty) break;
            final batch = firestore.batch();
            for (final operation in page.docs) {
              batch.delete(operation.reference);
            }
            await batch.commit();
          }
          await baby.reference.delete();
        }
      }
      final leftovers = await babies
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (leftovers.docs.isNotEmpty) {
        throw StateError('Baby profile erasure not verified.');
      }
    }

    final path = operations(user.uid);
    while (true) {
      final page = await path
          .limit(200)
          .get(const GetOptions(source: Source.server));
      if (page.docs.isEmpty) break;
      final batch = firestore.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    final remaining = await path
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (remaining.docs.isNotEmpty) {
      throw StateError(
        'Cloud erasure could not be verified. Try again online.',
      );
    }

    await user.delete();
    try {
      await auth.signOut();
    } finally {
      // Firestore caches can include old private data even after sign-out.
      // A failed clear must be prominently disclosed, not silently ignored.
      try {
        await firestore.terminate();
        await firestore.clearPersistence();
        deletionNotice.value =
            'Account and cloud sleep records deleted. Local cache cleared. '
            'Close and reopen Little Rest before creating a new account.';
      } catch (_) {
        deletionNotice.value =
            'Cloud records and account deleted, but this device cache could '
            'not be verified empty. Clear the app data before handing this '
            'phone to someone else.';
      }
    }
  }
}
