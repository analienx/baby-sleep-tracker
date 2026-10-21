import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/personal_cloud_client.dart';

/// Recoverable personal-only Firebase account for the no-billing Spark stage.
/// Invitations and family deletion remain protected behind server callables.
final class PersonalAccountScreen extends StatefulWidget {
  const PersonalAccountScreen({super.key, required this.client});
  final PersonalCloudClient client;

  @override
  State<PersonalAccountScreen> createState() => _PersonalAccountScreenState();
}

final class _PersonalAccountScreenState extends State<PersonalAccountScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? message;
  bool error = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _work(Future<void> Function() task, String success) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = false;
      message = null;
    });
    try {
      await task();
      if (mounted) setState(() => message = success);
    } on FirebaseAuthException catch (exception) {
      if (mounted) {
        setState(() {
          error = true;
          message =
              'Firebase could not finish: ${exception.code}. Check the email and connection.';
        });
      }
    } on StateError catch (exception) {
      if (mounted) {
        setState(() {
          error = true;
          message = exception.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = true;
          message =
              'Action not confirmed. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = TextEditingController();
    final passwordConfirm = TextEditingController();
    final user = widget.client.auth.currentUser;
    if (user == null) return;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Permanently delete your account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently erases all sleep revisions '
                'from your private cloud and deletes the login. '
                'Copies you exported cannot be recalled. '
                'Stay online until deletion finishes.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirm,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
              ),
              if (!user.isAnonymous)
                TextField(
                  controller: passwordConfirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current account password',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, confirm.text.trim() == 'DELETE');
              },
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      await _work(
        () => widget.client.deleteAccount(password: passwordConfirm.text),
        'Cloud account and records erased.',
      );
    } finally {
      confirm.dispose();
      passwordConfirm.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your private cloud')),
    body: SafeArea(
      child: StreamBuilder<User?>(
        stream: widget.client.auth.userChanges(),
        initialData: widget.client.auth.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return const Center(child: Text('Account closed or signed out.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 38),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Private Firebase sync',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            user.isAnonymous
                                ? 'Saved to this device and its private cloud account. '
                                      'Add email recovery before changing phones or uninstalling.'
                                : 'Your records are tied to ${user.email ?? 'your email account'}. '
                                      'Sign in with this email on a new phone to restore synced history.',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            user.isAnonymous
                                ? 'Recovery: Not enabled'
                                : user.emailVerified
                                ? 'Recovery: Email verified'
                                : 'Recovery: Email verification pending',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            user.isAnonymous
                                ? 'Protect or restore an account'
                                : 'Email verification and recovery',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if (user.isAnonymous) ...[
                            TextField(
                              controller: email,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                              ),
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: password,
                              decoration: const InputDecoration(
                                labelText: 'Password (12 or more characters)',
                              ),
                              obscureText: true,
                              autofillHints: const [AutofillHints.newPassword],
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => _work(
                                      () => widget.client.linkEmailPassword(
                                        email.text,
                                        password.text,
                                      ),
                                      'Account protected. Check your email for verification.',
                                    ),
                              child: const Text(
                                'Protect my existing sleep records',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _work(
                                      () => widget.client.signInExisting(
                                        email.text,
                                        password.text,
                                      ),
                                      'Existing account restored.',
                                    ),
                              child: const Text(
                                'Sign in to an existing account',
                              ),
                            ),
                            const Text(
                              'Switching accounts is blocked if this anonymous '
                              'account already contains records. Protect it first.',
                            ),
                          ] else ...[
                            Text(
                              'Signed in: ${user.email ?? 'email not available'}',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _work(
                                      widget.client.sendVerificationEmail,
                                      'Verification email sent.',
                                    ),
                              child: const Text('Send verification email'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _work(
                                      widget.client.refreshVerification,
                                      'Email status refreshed.',
                                    ),
                              child: const Text('Refresh verification status'),
                            ),
                            TextButton(
                              onPressed: busy || user.email == null
                                  ? null
                                  : () => _work(
                                      () => widget.client.resetPassword(
                                        user.email!,
                                      ),
                                      'Password reset email requested.',
                                    ),
                              child: const Text('Send password reset email'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        message!,
                        style: TextStyle(
                          color: error
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Privacy and deletion',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'This stage stores one private sleep journal '
                            'per account. Caregiver invitations are disabled '
                            'until the independently reviewed family backend is available.',
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: busy ? null : _confirmDelete,
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text(
                              'Erase my cloud data and account',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
