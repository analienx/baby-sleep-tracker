import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/spark_family_lite_controller.dart';

/// Both parents have distinct Firebase Auth accounts. Sharing is authorized
/// by owner-written Firestore grants, not by a secret code or local preference.
final class SparkFamilyLiteScreen extends StatefulWidget {
  const SparkFamilyLiteScreen({super.key, required this.client});

  final SparkFamilyLiteController client;

  @override
  State<SparkFamilyLiteScreen> createState() => _SparkFamilyLiteScreenState();
}

final class _SparkFamilyLiteScreenState extends State<SparkFamilyLiteScreen> {
  final _caregiver = TextEditingController();
  final _owner = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _caregiver.dispose();
    _owner.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Not confirmed by Firebase. Reconnect and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _message = 'ID copied.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.client.auth.currentUser;
    if (auth == null) {
      return const Scaffold(body: Center(child: Text('Sign in first.')));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Family sharing')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ValueListenableBuilder<String?>(
              valueListenable: widget.client.selectedOwnerUid,
              builder: (context, _, _) {
                final journal = widget.client.ownerFor(auth.uid);
                final joined = journal != auth.uid;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 42),
                  children: [
                    Text(
                      'One little journal, two caregivers.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Separate accounts and owner-approved access. '
                      'Your records synchronize through the free Firebase '
                      'Spark project. Nobody needs the other parent’s password.',
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Your caregiver ID',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              auth.uid,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _copy(auth.uid),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy ID'),
                              ),
                            ),
                            Text(
                              auth.emailVerified
                                  ? 'Email verified'
                                  : 'Verify your email under Account & recovery '
                                        'before sharing.',
                              style: TextStyle(
                                color: auth.emailVerified
                                    ? scheme.primary
                                    : scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (joined) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Joined family journal',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              SelectableText('Owner ID: $journal'),
                              const SizedBox(height: 12),
                              const Text(
                                'Leaving here only changes your phone. '
                                'Ask the owner to revoke access permanently.',
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _act(
                                        widget.client.leaveSharedJournal,
                                        'Your personal journal is now active.',
                                      ),
                                child: const Text('Switch to my own journal'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Invite a caregiver',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Have the other parent copy their '
                                'caregiver ID. Verify it together before '
                                'granting access to your records.',
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _caregiver,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Other parent’s caregiver ID',
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _busy || !auth.emailVerified
                                    ? null
                                    : () => _act(
                                        () => widget.client.approveCaregiver(
                                          _caregiver.text,
                                        ),
                                        'Caregiver approved. Share your owner ID.',
                                      ),
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Approve caregiver'),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your owner ID',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SelectableText(auth.uid),
                              TextButton.icon(
                                onPressed: () => _copy(auth.uid),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy owner ID'),
                              ),
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: widget.client.firestore
                                    .collection('personalSleep')
                                    .doc(auth.uid)
                                    .collection('caregivers')
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return const Text(
                                      'Caregivers unavailable. '
                                      'Check connection.',
                                    );
                                  }
                                  final members = snapshot.data?.docs ?? [];
                                  if (members.isEmpty) {
                                    return const Text(
                                      'No approved caregivers.',
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final member in members)
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            'Caregiver: ${member.id}',
                                          ),
                                          subtitle:
                                              snapshot
                                                  .data!
                                                  .metadata
                                                  .isFromCache
                                              ? const Text(
                                                  'Cached — revocation '
                                                  'must reconnect to confirm',
                                                )
                                              : const Text('Approved by owner'),
                                          trailing: IconButton(
                                            tooltip: 'Revoke caregiver',
                                            icon: const Icon(
                                              Icons.person_remove,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _act(
                                                    () => widget.client
                                                        .revokeCaregiver(
                                                          member.id,
                                                        ),
                                                    'Caregiver access revoked on server.',
                                                  ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Join another parent',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'First have the owner approve your '
                                'caregiver ID. Then paste their owner ID here.',
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _owner,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Owner ID',
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _busy || !auth.emailVerified
                                    ? null
                                    : () => _act(
                                        () => widget.client.joinOwner(
                                          _owner.text,
                                        ),
                                        'You are viewing the shared journal.',
                                      ),
                                child: const Text('Join shared journal'),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Existing personal sleep records '
                                'stay in your private journal. They are not '
                                'silently merged or erased.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _failed ? scheme.error : scheme.primary,
                          ),
                        ),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 18),
                    const Text(
                      'When access is revoked, offline copies may '
                      'remain visible on an old device; server reads and '
                      'writes are denied once it reconnects. Do not use '
                      'real infant records until family security QA passes.',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
