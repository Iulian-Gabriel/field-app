import 'dart:async';
import 'dart:math' show min;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'auth.dart';
import 'contract/contract.dart';
import 'db/database.dart' show EntranceRow, QueueState;
import 'photo_queue.dart';
import 'providers.dart';
import 'repositories.dart';

/// Server state: my pins as the cloud has them, from the last fetch. The
/// banner watches it; SyncScope copies every new list into SQLite.
/// pullPins asks again: Riverpod throws the old stream away and starts a new one.
final myPinsProvider = StreamProvider<List<Entrance>>(
      (ref) => ref.watch(pinsRepositoryProvider).watchMine(ref.watch(uidProvider)),
);

final outboxProvider = StreamProvider(
      (ref) => ref.watch(databaseProvider).watchOutbox(),
);

/// (week 4) Invitation: the outbox, row by row, live.
final outboxRowsProvider = StreamProvider<List<EntranceRow>>(
      (ref) => ref.watch(databaseProvider).watchOutboxRows(),
);

/// (week 4) Invitation: when we last heard from the cloud. Kept across restarts.
class CloudTimes {
  const CloudTimes({this.pull, this.push});
  final DateTime? pull;
  final DateTime? push;
}

class CloudTimesNotifier extends Notifier<CloudTimes> {
  @override
  CloudTimes build() {
    _load();
    return const CloudTimes();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    DateTime? read(String k) => DateTime.tryParse(p.getString(k) ?? '');
    state = CloudTimes(pull: state.pull ?? read('lastPullAt'), push: state.push ?? read('lastPushAt'));
  }

  Future<void> mark({bool pull = false, bool push = false}) async {
    final now = DateTime.now();
    state = CloudTimes(pull: pull ? now : state.pull, push: push ? now : state.push);
    final p = await SharedPreferences.getInstance();
    if (pull) await p.setString('lastPullAt', now.toIso8601String());
    if (push) await p.setString('lastPushAt', now.toIso8601String());
  }
}

final cloudTimesProvider = NotifierProvider<CloudTimesNotifier, CloudTimes>(CloudTimesNotifier.new);

/// The pull, again: on start, back in the foreground and on "Sync now".
void pullPins(WidgetRef ref) => ref.invalidate(myPinsProvider);

/// Sign out only when nothing waits to be sent. The local database is not
/// per user: the next worker's push would send this one's surveys, the server
/// would refuse them (not theirs) and the pull would delete them. So the
/// worker sends first (or deletes the surveys on purpose, a later feature).
Future<void> signOutIfSent(BuildContext context, WidgetRef ref) async {
  final box = await ref.read(databaseProvider).watchOutbox().first;
  final waiting = box.pending + box.failed;
  // Step 4: the photo queue too (every row not synced yet).
  final queue = (await ref.read(databaseProvider).watchQueue().first).counts;
  final photos = queue.entries.where((q) => q.key != QueueState.synced).fold(0, (n, q) => n + q.value);
  if (waiting == 0 && photos == 0) return signOut();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$waiting survey(s) and $photos photo(s) not sent yet: tap Sync now (or Retry photos), then sign out.'),
  ));
}

var _pushing = false;
var _again = false; // (week 4) a push was asked for while one was running
Timer? _retryTimer; // (week 4) the retry policy's timer
var _autoTries = 0; // (week 4)
WidgetRef? _scopeRef; // (week 4) SyncScope's ref: lives as long as a worker is signed in

/// Errors a retry cannot fix: permission (42501), a check (23514), a missing
/// value (23502), a value of the wrong type (22P02). Everything else is retried.
const _permanent = {'42501', '23514', '23502', '22P02'};

/// What the worker reads: a sentence, not a code.
String sentenceFor(PostgrestException e) => switch (e.code) {
  '42501' => 'This app tried to change something only the office may change. Tell your teacher: it is a bug.',
  '23514' => 'One of the numbers is outside what the form allows.',
  _ => 'The server refused a value of this survey (${e.code}).',
};

/// The outbox push: every pending survey goes to upsert_survey, by the
/// entrance's UUID, with the updatedAt it was saved with. Four outcomes:
/// applied (synced), lost (a newer version won: the phone takes the server's),
/// refused (failed, with a sentence) and no answer (still pending).
/// (week 4) onlyId: push one row. auto: a retry from the policy's timer.
Future<void> pushSurveys(WidgetRef ref, {String? onlyId, bool auto = false}) async {
  if (_pushing) {
    _again = true; // (week 4)
    return;
  }
  _pushing = true;
  if (!auto) _autoTries = 0; // (week 4)
  _retryTimer?.cancel(); // (week 4)
  final db = ref.read(databaseProvider);
  final surveys = ref.read(surveysRepositoryProvider);
  final pins = ref.read(pinsRepositoryProvider);
  final uid = ref.read(uidProvider);
  final times = ref.read(cloudTimesProvider.notifier); // (week 4)
  var transientLeft = false; // (week 4)
  try {
    for (final e in await db.outbox()) {
      if (onlyId != null && e.id != onlyId) continue; // (week 4)
      try {
        if (await surveys.push(surveyDoc(e, uid))) {
          await db.markSent(e.id, e.updatedAt, null); // applied
          times.mark(push: true); // (week 4)
        } else {
          // Lost: nothing changed on the server. Pull that one row: if it is
          // there, its newer values replace the worker's; if not, the pin is no
          // longer mine, and the next pull removes it from the phone.
          final server = await pins.pullOne(e.id);
          if (server?.updatedAt == e.updatedAt) {
            await db.markSent(e.id, e.updatedAt, null); // the same survey, resent: it was there already
          } else if (server != null) {
            await db.takeServerVersion(server, 'A newer change of this entrance was kept: these are its values.');
          } else {
            await db.markSent(e.id, e.updatedAt, null);
            final r = _scopeRef; // (week 4) the long-lived ref, not a screen's
            if (r != null) pullPins(r);
          }
        }
      } on PostgrestException catch (err) {
        if (_permanent.contains(err.code)) {
          await db.markSent(e.id, e.updatedAt, sentenceFor(err)); // refused: failed
        } else {
          await db.markWaiting(e.id, e.updatedAt, 'Could not reach the server: it will try again.');
          transientLeft = true; // (week 4)
        }
      }
    }
  } catch (_) {
    // No answer at all (offline, a timeout): nothing is lost, the rows stay pending.
    transientLeft = true; // (week 4)
  } finally {
    _pushing = false;
  }
  // (week 4) surveys submitted while this push ran
  if (_again) {
    _again = false;
    final again = _scopeRef;
    if (again != null) return pushSurveys(again);
  }
  if (transientLeft) _scheduleRetry(); // (week 4)
}

/// (week 4) The policy (see sync_status_screen.dart): 30 s, doubling, max 10 min, 6 tries.
void _scheduleRetry() {
  if (_autoTries >= 6 || _scopeRef == null) return;
  final seconds = min(30 << _autoTries, 600);
  _autoTries++;
  _retryTimer = Timer(Duration(seconds: seconds), () {
    final ref = _scopeRef;
    if (ref != null) pushSurveys(ref, auto: true);
  });
}

/// Wraps the signed-in app: while it is on screen, the pull runs. Signing out
/// removes it, and Riverpod stops the listener nobody watches any more.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> {
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<List<ConnectivityResult>> _network;
  late final PhotoQueue _queue = ref.read(photoQueueProvider);

  @override
  void initState() {
    super.initState();
    _scopeRef = ref; // (week 4)
    // The push and the pull, at three moments: now (the provider's first
    // fetch), back in the foreground, and when the network comes back. (And on
    // "Sync now"; the push also after a submit.)
    pushSurveys(ref);
    // The photo queue resumes: rows cut off mid-upload go back to pending,
    // photos from before the queue join it, then the worker starts.
    final db = ref.read(databaseProvider);
    db.resumeUploading().then((_) => enqueueLeftovers(db, ref.read(uidProvider))).then((_) => _queue.drain());
    _lifecycle = AppLifecycleListener(onResume: () {
      pushSurveys(ref);
      pullPins(ref);
      _queue.drain();
    });
    _network = Connectivity().onConnectivityChanged.listen((links) {
      if (links.contains(ConnectivityResult.none)) return;
      pushSurveys(ref);
      pullPins(ref);
      _queue.drain();
    });
    // The pull: every list of my pins goes to SQLite, the truth on the
    // phone. listenManual keeps the provider alive while this widget lives.
    ref.listenManual(myPinsProvider, (_, next) {
      final pins = next.value;
      if (pins == null) return;
      ref.read(cloudTimesProvider.notifier).mark(pull: true); // (week 4)
      // An empty answer is also what row level security returns when it hides
      // every row: never read it as "all my pins are gone". (A real "none left"
      // waits for the next pull that brings a pin.)
      if (pins.isNotEmpty) ref.read(databaseProvider).savePins(pins);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _network.cancel();
    _retryTimer?.cancel(); // (week 4)
    _scopeRef = null; // (week 4)
    _queue.stop(); // signed out: no wake-up until someone signs in again
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}