import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../sleep/data/firestore_sleep_repository.dart';
import '../data/personal_cloud_client.dart';

/// Rebuilds the repository on every identity change: never keep one user's
/// sleep listeners alive while rendering the next user's private data.
final class PersonalGate extends StatelessWidget {
  const PersonalGate({super.key, required this.client});
  final PersonalCloudClient client;

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
                child: Text(notice, textAlign: TextAlign.center),
              ),
            ),
          ),
        );
      }
      return child!;
    },
    child: StreamBuilder<User?>(
      stream: client.auth.userChanges(),
      initialData: client.auth.currentUser,
      builder: (context, auth) {
        final user = auth.data;
        if (user == null) {
          return _SignedOutScreen(client: client);
        }
        return _PersonalWorkspace(
          key: ValueKey(user.uid),
          client: client,
          uid: user.uid,
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
  });
  final PersonalCloudClient client;
  final String uid;

  @override
  State<_PersonalWorkspace> createState() => _PersonalWorkspaceState();
}

final class _PersonalWorkspaceState extends State<_PersonalWorkspace> {
  late final FirestoreSleepRepository repository =
      FirestoreSleepRepository.personal(
        firestore: widget.client.firestore,
        uid: widget.uid,
      );

  @override
  void dispose() {
    unawaited(repository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [sleepRepositoryProvider.overrideWithValue(repository)],
    child: BabySleepApp(personalClient: widget.client),
  );
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
