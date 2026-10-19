import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/family_client.dart';

final class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.client, required this.family});
  final FamilyClient client;
  final FamilyContext family;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

final class _FamilyScreenState extends State<FamilyScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _invite;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await task();
    } on FirebaseAuthException catch (error) {
      if (mounted)
        setState(
          () => _message =
              '${error.code}: ${error.message ?? "Authentication failed"}',
        );
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Our family')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Sleep records are shared only with invited caregivers.'),
          const SizedBox(height: 12),
          Text(
            current?.isAnonymous == true
                ? 'Temporary account — link an email before inviting others or switching phones.'
                : 'Recoverable account: ${current?.email ?? "linked"}',
          ),
          if (current?.isAnonymous == true) ...[
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.client.linkEmailPassword(
                        _email.text,
                        _password.text,
                      ),
                    ),
              child: const Text('Protect my family with email/password'),
            ),
          ],
          const Divider(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt),
            onPressed: _busy || current?.isAnonymous == true
                ? null
                : () => _run(() async {
                    final issued = await widget.client.createInvite();
                    if (mounted) {
                      setState(() => _invite = issued.code);
                    }
                  }),
            label: const Text('Create one-time invitation (24h)'),
          ),
          if (_invite != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Share privately. Anyone holding this code can join once.',
            ),
            SelectableText(_invite!),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: _invite!)),
              label: const Text('Copy invitation code'),
            ),
          ],
          const SizedBox(height: 18),
          Text('Caregivers', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder(
            stream: widget.client.watchMembers(widget.family.familyId),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('Members unavailable.');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final docs = snapshot.data!.docs;
              final ownRole = [
                for (final doc in docs)
                  if (doc.id == current?.uid) doc.data()['role'],
              ];
              final owner = ownRole.contains('owner');
              return Column(
                children: [
                  for (final doc in docs)
                    ListTile(
                      title: Text(
                        doc.id == current?.uid
                            ? 'You (${doc.data()['role']})'
                            : 'Caregiver · ${doc.id.substring(0, doc.id.length < 8 ? doc.id.length : 8)}',
                      ),
                      trailing:
                          owner &&
                              doc.id != current?.uid &&
                              doc.data()['role'] != 'owner'
                          ? IconButton(
                              tooltip: 'Revoke caregiver access',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text(
                                            'Remove caregiver?',
                                          ),
                                          content: const Text(
                                            'Their cloud access ends immediately when online. '
                                            'Previously cached offline data cannot be remotely erased.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await _run(
                                          () => widget.client.revokeCaregiver(
                                            doc.id,
                                          ),
                                        );
                                      }
                                    },
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) SelectableText(_message!),
        ],
      ),
    );
  }
}
