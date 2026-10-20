import 'package:flutter/material.dart';

import '../data/family_client.dart';

class AccountVerificationAction extends StatefulWidget {
  const AccountVerificationAction({super.key, required this.client});
  final FamilyClient client;

  @override
  State<AccountVerificationAction> createState() =>
      _AccountVerificationActionState();
}

class _AccountVerificationActionState extends State<AccountVerificationAction> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() call, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await call();
      if (mounted) setState(() => _message = success);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not verify this email right now. Try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    if (user == null || user.isAnonymous || user.emailVerified) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verify your email before inviting or joining a family.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          widget.client.sendVerificationEmail,
                          'Verification email sent. Check your inbox.',
                        ),
                  child: const Text('Resend email'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          widget.client.refreshEmailVerification,
                          'Email status checked.',
                        ),
                  child: const Text('I have verified'),
                ),
              ],
            ),
            if (_message != null) Text(_message!),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
