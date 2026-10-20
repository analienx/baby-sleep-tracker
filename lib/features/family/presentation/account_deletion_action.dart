import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/family_client.dart';

/// Separate from household-data deletion: an account includes Firebase Auth
/// credentials, and a caregiver may delete their identity without erasing
/// another parent's records.
class AccountDeletionAction extends StatefulWidget {
  const AccountDeletionAction({
    super.key,
    required this.client,
    this.isOwner = false,
  });

  final FamilyClient client;
  final bool isOwner;

  @override
  State<AccountDeletionAction> createState() => _AccountDeletionActionState();
}

class _AccountDeletionActionState extends State<AccountDeletionAction> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    final confirmation = TextEditingController();
    final password = TextEditingController();
    final needsPassword = widget.client.auth.currentUser?.isAnonymous == false;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Delete your account permanently?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isOwner
                        ? 'This will delete your sign-in account AND the entire '
                              'household, including every caregiver’s shared sleep '
                              'journal and its edit history. Export first.'
                        : 'Your sign-in credentials and private membership '
                              'will be deleted. Sleep entries you previously '
                              'contributed remain in the family’s shared journal '
                              'with only a pseudonymous editor identifier.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Offline copies already held by other devices cannot '
                    'be remotely erased. This cannot be undone.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmation,
                    autofocus: true,
                    onChanged: (_) => refresh(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE ACCOUNT',
                    ),
                  ),
                  if (needsPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      onChanged: (_) => refresh(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Confirm your password',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    confirmation.text == 'DELETE ACCOUNT' &&
                        (!needsPassword || password.text.isNotEmpty)
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Delete account'),
              ),
            ],
          ),
        ),
      );
      if (approved != true || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await widget.client.deleteAccount(
          password: needsPassword ? password.text : null,
          deleteOwnedHousehold: widget.isOwner,
        );
      } on FirebaseAuthException catch (error) {
        if (mounted) setState(() => _error = error.message ?? error.code);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Could not confirm deletion. Reconnect and retry. If deletion '
                'already started, the server will continue blocking this account.',
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        confirmation.dispose();
        password.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_off_outlined),
        title: const Text('Delete my account'),
        subtitle: const Text('Delete my Firebase sign-in and personal profile'),
        enabled: !_busy,
        onTap: _busy ? null : _confirm,
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}
