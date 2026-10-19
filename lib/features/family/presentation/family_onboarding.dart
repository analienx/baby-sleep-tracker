import 'package:flutter/material.dart';

import '../data/family_client.dart';

final class FamilyOnboarding extends StatefulWidget {
  const FamilyOnboarding({super.key, required this.client});
  final FamilyClient client;

  @override
  State<FamilyOnboarding> createState() => _FamilyOnboardingState();
}

final class _FamilyOnboardingState extends State<FamilyOnboarding> {
  final _baby = TextEditingController(text: 'Vincent');
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _baby.dispose();
    _code.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted) setState(() => _info = successMessage);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    return MaterialApp(
      title: 'Little Rest · Family',
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.nights_stay_rounded, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Little Rest',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text('Your family sleep journal, private by default.'),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _baby,
                    maxLength: 50,
                    decoration: const InputDecoration(labelText: 'Baby name'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.client.createFamily(_baby.text),
                          ),
                    child: const Text('Create family'),
                  ),
                  const Divider(height: 40),
                  TextField(
                    controller: _code,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              _run(() => widget.client.joinFamily(_code.text)),
                    child: const Text('Join an existing family'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.isAnonymous == true
                        ? 'Secure your temporary account before joining a family. '
                              'Anonymous accounts cannot be restored after reinstall.'
                        : 'Signed in to a recoverable account.',
                  ),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (minimum 6 characters)',
                    ),
                  ),
                  if (user?.isAnonymous == true)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.client.linkEmailPassword(
                                _email.text,
                                _password.text,
                              ),
                            ),
                      child: const Text('Secure this account'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.client.signInExisting(
                              _email.text,
                              _password.text,
                            ),
                          ),
                    child: const Text('I already have an account — sign in'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.client.resetPassword(_email.text),
                            successMessage: 'If this email is registered, a password reset message has been sent.',
                          ),
                    child: const Text('Forgot password?'),
                  ),
                  if (_info != null) Text(_info!),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        _error!,
                        style: const TextStyle(color: Colors.red),
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
}
