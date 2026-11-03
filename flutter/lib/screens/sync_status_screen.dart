// Retry policy: a refusal by the rules (permission-denied) is never retried automatically, because the same survey gets the same answer; any other failure is retried after 30 s, then 1, 2, 4, 8 and 10 minutes, and after six tries the app waits for the network to come back, the app to reopen, or the worker to tap Retry.
// This is not a loop: every wait is at least 30 s and grows, the number of tries is capped, and permanent refusals are not retried at all, so a dead server or a moved pin cannot drain the battery or the Firestore quota.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../session.dart'; // connectivityProvider (wherever map_screen gets it)
import '../sync.dart';

/// A Firestore error code, said the way a worker understands it, with what to do.
String errorText(String? code) => switch (code) {
  'permission-denied' =>
  'The office moved this entrance to another worker, so the cloud refused your survey. '
      'Ask the office to give it back, or to collect your survey from this phone.',
  'unavailable' || 'deadline-exceeded' =>
  'The cloud could not be reached. The app will try again by itself; you can also tap Retry.',
  'unauthenticated' => 'You are signed out. Sign in again, then tap Retry.',
  'invalid-argument' =>
  'Something in this survey is not valid for the cloud. Open it, check the answers and submit again.',
  null => '',
  _ => 'The cloud did not accept this survey ($code). Tap Retry; if it keeps failing, tell the office.',
};

class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(outboxRowsProvider);
    final times = ref.watch(cloudTimesProvider);
    final links = ref.watch(connectivityProvider).value ?? const [ConnectivityResult.other];
    final online = !links.contains(ConnectivityResult.none);
    final list = rows.value ?? const <EntranceRow>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Sync status')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: list.isEmpty ? null : () => pushSurveys(ref),
            child: const Text('Retry all'),
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Everything is in the cloud: nothing is waiting to be sent.'),
          )
        else
          for (final r in list)
            Card(
              child: ListTile(
                title: Text('${r.street} ${r.number}, ${r.entranceName}'),
                subtitle: Text([
                  'submitted ${_short(r.surveyedAt ?? r.updatedAt)} · ${r.syncState.name}',
                  if (r.syncState.name == 'failed') errorText(r.lastError),
                ].join('\n')),
                trailing: r.syncState.name == 'failed'
                    ? TextButton(onPressed: () => pushSurveys(ref, onlyId: r.id), child: const Text('Retry'))
                    : null,
              ),
            ),
        const Divider(height: 32),
        Text('Last pull from the cloud: ${_when(times.pull)}'),
        Text('Last push to the cloud: ${_when(times.push)}'),
        Text(online
            ? 'This device is online.'
            : 'This device is offline: surveys wait here until the network is back.'),
      ]),
    );
  }
}

String _short(String iso) => DateTime.parse(iso).toLocal().toString().substring(0, 16);
String _when(DateTime? t) => t == null ? 'not yet' : t.toLocal().toString().substring(0, 19);