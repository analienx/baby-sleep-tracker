import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../sleep/data/firestore_sleep_repository.dart';
import '../data/family_client.dart';
import 'family_onboarding.dart';

/// Rebinds every sleep listener to the current verified identity and family.
/// No repository or active in-memory action crosses an auth/membership switch.
final class FamilyGate extends StatelessWidget {
  const FamilyGate({super.key, required this.client});
  final FamilyClient client;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: client.auth.userChanges(),
    initialData: client.auth.currentUser,
    builder: (context, authSnapshot) {
      final user = authSnapshot.data;
      if (user == null) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => client.auth.signInAnonymously(),
                child: const Text('Start a new private session'),
              ),
            ),
          ),
        );
      }
      return StreamBuilder<FamilySnapshot>(
        key: ValueKey(user.uid),
        stream: client.watchFamily(user.uid),
        builder: (context, familySnapshot) {
          if (familySnapshot.hasError) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Family access unavailable: ${familySnapshot.error}',
                    ),
                  ),
                ),
              ),
            );
          }
          if (familySnapshot.connectionState == ConnectionState.waiting) {
            return const MaterialApp(
              home: Scaffold(body: Center(child: CircularProgressIndicator())),
            );
          }
          final presence = familySnapshot.data;
          final family = presence?.family;
          if (presence?.deletionInProgress == true) {
            return _HouseholdDeletionPending(client: client);
          }
          if (family == null && presence?.isFromCache == true) {
            return const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Checking family access. Reconnect to the internet '
                      'before creating or joining a family.',
                    ),
                  ),
                ),
              ),
            );
          }
          if (family == null) return FamilyOnboarding(client: client);
          return _FamilyWorkspace(
            key: ValueKey('${user.uid}/${family.familyId}/${family.babyId}'),
            client: client,
            family: family,
            isFromCache: presence!.isFromCache,
            uid: user.uid,
          );
        },
      );
    },
  );
}

/// Owners retain their signed-in account and a retry button while a large
/// household is being removed. The server fences all family reads/writes
/// as soon as the deletion flag is committed.
final class _HouseholdDeletionPending extends StatefulWidget {
  const _HouseholdDeletionPending({required this.client});
  final FamilyClient client;

  @override
  State<_HouseholdDeletionPending> createState() =>
      _HouseholdDeletionPendingState();
}

final class _HouseholdDeletionPendingState
    extends State<_HouseholdDeletionPending> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.deleteHousehold();
      // The owner's profile listener takes us back to onboarding.
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Cloud cleanup could not be confirmed. Reconnect and retry. '
              'Household access remains blocked until deletion completes.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Deleting household')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_bottom_rounded, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'The household is locked while its cloud records, '
                  'invitations, and edit history are permanently removed. '
                  'This may take a little while.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _retry,
                  child: Text(
                    _busy ? 'Removing…' : 'Resume or verify deletion',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _FamilyWorkspace extends StatefulWidget {
  const _FamilyWorkspace({
    super.key,
    required this.client,
    required this.family,
    required this.isFromCache,
    required this.uid,
  });
  final FamilyClient client;
  final FamilyContext family;
  final bool isFromCache;
  final String uid;

  @override
  State<_FamilyWorkspace> createState() => _FamilyWorkspaceState();
}

final class _FamilyWorkspaceState extends State<_FamilyWorkspace> {
  late final FirestoreSleepRepository repository =
      FirestoreSleepRepository.family(
        firestore: widget.client.firestore,
        familyId: widget.family.familyId,
        babyId: widget.family.babyId,
        actorId: widget.uid,
      );

  @override
  void dispose() {
    unawaited(repository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [sleepRepositoryProvider.overrideWithValue(repository)],
    child: BabySleepApp(
      familyClient: widget.client,
      family: widget.family,
      familyFromCache: widget.isFromCache,
    ),
  );
}
