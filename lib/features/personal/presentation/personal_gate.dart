import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../sleep/data/firestore_sleep_repository.dart';
import '../data/personal_cloud_client.dart';
import '../data/spark_baby_profiles.dart';
import '../data/spark_family_lite_controller.dart';

/// Rebuilds the repository on every identity change: never keep one user's
/// sleep listeners alive while rendering the next user's private data.
final class PersonalGate extends StatelessWidget {
  const PersonalGate({super.key, required this.client, this.familyLite});
  final PersonalCloudClient client;
  final SparkFamilyLiteController? familyLite;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: client.deletionNotice,
    builder: (context, notice, child) {
      if (notice != null) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(notice, textAlign: TextAlign.center),
                    if (client.auth.currentUser != null) ...[
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () => client.deletionNotice.value = null,
                        child: const Text('Return to journal'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return ValueListenableBuilder<bool>(
        valueListenable: client.deletionInProgress,
        child: child,
        builder: (context, deleting, workspace) {
          if (!deleting) return workspace!;
          // Dispose the repository listeners and disable write controls
          // before any journal erasure begins; never show stale records.
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  liveRegion: true,
                  child: const Text('Deleting private cloud records…'),
                ),
              ),
            ),
          );
        },
      );
    },
    child: StreamBuilder<User?>(
      stream: client.auth.userChanges(),
      initialData: client.auth.currentUser,
      builder: (context, auth) {
        final user = auth.data;
        if (user == null) {
          return _SignedOutScreen(client: client);
        }
        if (familyLite == null) {
          return _PersonalWorkspace(
            key: ValueKey(user.uid),
            client: client,
            uid: user.uid,
            journalOwnerUid: user.uid,
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: familyLite!.membershipBlocked,
          builder: (context, blocked, _) {
            if (blocked) {
              return MaterialApp(
                home: Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_clock_rounded, size: 38),
                            const SizedBox(height: 15),
                            const Text(
                              'Family access needs verification',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22),
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<String?>(
                              valueListenable: familyLite!.notice,
                              builder: (_, message, _) => Text(
                                message ?? 'Checking your family permission…',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () =>
                                  unawaited(familyLite!.refreshMembership()),
                              child: const Text('Retry online'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  unawaited(familyLite!.leaveSharedJournal()),
                              child: const Text('Use my personal journal'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ValueListenableBuilder<String?>(
              valueListenable: familyLite!.selectedOwnerUid,
              builder: (context, _, _) {
                final owner = familyLite!.ownerFor(user.uid);
                return _PersonalWorkspace(
                  key: ValueKey('${user.uid}:$owner'),
                  client: client,
                  uid: user.uid,
                  journalOwnerUid: owner,
                  familyLite: familyLite,
                );
              },
            );
          },
        );
      },
    ),
  );
}

final class _PersonalWorkspace extends StatefulWidget {
  const _PersonalWorkspace({
    super.key,
    required this.client,
    required this.uid,
    required this.journalOwnerUid,
    this.familyLite,
  });
  final PersonalCloudClient client;
  final String uid;
  final String journalOwnerUid;
  final SparkFamilyLiteController? familyLite;

  @override
  State<_PersonalWorkspace> createState() => _PersonalWorkspaceState();
}

final class _PersonalWorkspaceState extends State<_PersonalWorkspace> {
  late final SparkBabyProfiles? _babies = widget.familyLite == null
      ? null
      : SparkBabyProfiles(
          auth: widget.client.auth,
          firestore: widget.client.firestore,
          ownerUid: widget.journalOwnerUid,
        );
  StreamSubscription<List<SparkBabyProfile>>? _babySubscription;
  List<SparkBabyProfile> _profiles = const [SparkBabyProfile.primary];
  FirestoreSleepRepository? _repository;
  String? _selectedBabyId;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (_babies != null) {
      _babySubscription = _babies.watch().listen(
        (values) {
          if (mounted) setState(() => _profiles = values);
        },
        onError: (Object _) {
          if (mounted) {
            setState(
              () => _problem =
                  'The baby list could not be loaded. Reconnect to continue.',
            );
          }
        },
      );
    }
    unawaited(_restoreBaby());
  }

  void _openBaby(String id) {
    final previous = _repository;
    _repository = FirestoreSleepRepository.personal(
      firestore: widget.client.firestore,
      uid: widget.journalOwnerUid,
      actorUid: widget.uid,
      babyId: id,
      writeBlocked: widget.client.deletionInProgress,
    );
    setState(() {
      _selectedBabyId = id;
      _problem = null;
    });
    if (previous != null) unawaited(previous.dispose());
  }

  Future<void> _restoreBaby() async {
    try {
      final id = _babies == null
          ? SparkBabyProfile.primaryId
          : await _babies.restoreSelection(widget.uid);
      if (mounted) _openBaby(id);
    } catch (_) {
      // Never record into Baby 1 if a previously selected baby cannot be
      // validated from the server on this phone.
      if (mounted) {
        setState(
          () => _problem =
              'Could not verify the previously selected baby. '
              'Reconnect or explicitly select Baby 1.',
        );
      }
    }
  }

  Future<void> _selectBaby(String id) async {
    if (_babies == null || id == _selectedBabyId) return;
    if (!_profiles.any((p) => p.id == id)) return;
    try {
      await _babies.saveSelection(widget.uid, id);
      if (mounted) _openBaby(id);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _problem = 'Unable to save baby selection. Reconnect and retry.',
        );
      }
    }
  }

  Future<String?> _requestName(
    BuildContext dialogContext, {
    required String title,
    String initial = '',
  }) async {
    final name = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Baby name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, name.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
    }
  }

  void _tell(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createBaby(BuildContext context) async {
    if (_babies == null || !_babies.canManage) return;
    final name = await _requestName(context, title: 'Add another baby');
    if (name == null) return;
    try {
      final id = await _babies.add(name);
      if (!mounted) return;
      // A server-acknowledged document may be ahead of the snapshots stream.
      setState(
        () => _profiles = [
          ..._profiles.where((profile) => profile.id != id),
          SparkBabyProfile(id: id, name: name.trim()),
        ],
      );
      await _selectBaby(id);
    } catch (_) {
      if (context.mounted) {
        _tell(context, 'Could not add the baby. Check the name and connection.');
      }
    }
  }

  Future<void> _renameBaby(BuildContext context) async {
    final id = _selectedBabyId;
    if (id == null || _babies == null || !_babies.canManage) return;
    final current = _profiles.where((p) => p.id == id).firstOrNull;
    final name = await _requestName(
      context,
      title: 'Rename baby',
      initial: current?.name ?? '',
    );
    if (name == null) return;
    try {
      await _babies.rename(id, name);
    } catch (_) {
      if (context.mounted) {
        _tell(context, 'Could not rename the baby. Check the connection.');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_babySubscription?.cancel() ?? Future<void>.value());
    if (_repository != null) unawaited(_repository!.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_problem != null) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.child_care_rounded, size: 40),
                    const SizedBox(height: 12),
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => unawaited(_restoreBaby()),
                      child: const Text('Retry online'),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_resetToPrimary()),
                      child: const Text('Explicitly select Baby 1'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_repository == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ProviderScope(
      key: ValueKey('${widget.journalOwnerUid}:$_selectedBabyId'),
      overrides: [sleepRepositoryProvider.overrideWithValue(_repository!)],
      child: BabySleepApp(
        personalClient: widget.client,
        sparkFamilyLite: widget.familyLite,
        babyProfiles: _babies == null ? null : _profiles,
        selectedBabyId: _selectedBabyId,
        onBabyChanged: _selectBaby,
        onAddBaby: _babies?.canManage == true ? _createBaby : null,
        onRenameBaby: _babies?.canManage == true ? _renameBaby : null,
      ),
    );
  }

  Future<void> _resetToPrimary() async {
    try {
      await _babies?.saveSelection(widget.uid, SparkBabyProfile.primaryId);
      if (mounted) _openBaby(SparkBabyProfile.primaryId);
    } catch (_) {
      if (mounted) setState(() => _problem = 'Reconnect and try again.');
    }
  }
}

/// A signed-out session may be an account-restoration journey: do not silently
/// create a new anonymous UID and obscure the existing cloud account.
final class _SignedOutScreen extends StatefulWidget {
  const _SignedOutScreen({required this.client});
  final PersonalCloudClient client;

  @override
  State<_SignedOutScreen> createState() => _SignedOutScreenState();
}

final class _SignedOutScreenState extends State<_SignedOutScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } on FirebaseAuthException catch (exception) {
      if (mounted) {
        setState(() => error = 'Could not sign in: ${exception.code}.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not open a private account. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Little Rest · Account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Your little rest, safely saved',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign in to restore your previously synced sleeps, '
                  'or start a new private account. Initial sign-in needs internet.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => _act(() async {
                          await widget.client.auth.signInWithEmailAndPassword(
                            email: email.text.trim(),
                            password: password.text,
                          );
                        }),
                  child: const Text('Restore my account'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _act(() async {
                          await widget.client.auth.signInAnonymously();
                        }),
                  child: const Text('Start a new private account'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
