import 'dart:async';
import 'dart:io' show File;
import 'dart:math' show min;

//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'contract/contract.dart';
import 'db/database.dart';
import 'providers.dart';
import 'repositories.dart';


/// Server state: my pins as the cloud has them, live (one Firestore listener).
/// The banner watches it; SyncScope copies every new list into SQLite.
final myPinsProvider = StreamProvider<List<Entrance>>(
      (ref) => ref.watch(pinsRepositoryProvider).watchMine(ref.watch(uidProvider)),
);

final outboxProvider = StreamProvider(
      (ref) => ref.watch(databaseProvider).watchOutbox(),
    );
/// Invitation: the outbox, row by row, live.
final outboxRowsProvider = StreamProvider<List<EntranceRow>>(
      (ref) => ref.watch(databaseProvider).watchOutboxRows(),
);

/// Invitation: when we last heard from the cloud. Kept across restarts.
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
    // Keep anything marked while we were loading.
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
/// Exercise 2: the newest survey the cloud has from me.
final lastSentProvider = StreamProvider<Map<String, dynamic>?>(
      (ref) => ref.watch(surveysRepositoryProvider).watchLastSent(ref.watch(uidProvider)).handleError(
        (Object e) {
      debugPrint('$e'); // failed-precondition: the message holds the link that creates the index
      throw e;
    },
  ),
);


var _pushing = false;
var _again = false; // a push was asked for while one was running
Timer? _retryTimer;
var _autoTries = 0;
WidgetRef? _scopeRef; // SyncScope's ref: lives as long as a worker is signed in

/// Refusals that sending again cannot fix: never retried automatically.
const _permanent = {'permission-denied', 'invalid-argument'};

/// The outbox push. onlyId: retry one row. auto: a retry from the timer.
/// Anything else (a person, the network back, the app resumed) resets the policy.
Future<void> pushSurveys(WidgetRef ref, {String? onlyId, bool auto = false}) async {
  if (_pushing) {
    _again = true; // run once more when this push finishes
    return;
  }
  _pushing = true;
  if (!auto) _autoTries = 0;
  _retryTimer?.cancel();
  final db = ref.read(databaseProvider);
  final surveys = ref.read(surveysRepositoryProvider);
  final uid = ref.read(uidProvider);
  final times = ref.read(cloudTimesProvider.notifier);
  var transientLeft = false;
  try {
    for (final e in await db.outbox()) {
      if (onlyId != null && e.id != onlyId) continue;
      try {
        await surveys.push(surveyDoc(e, uid));
        await db.markSent(e.id, e.updatedAt, null);
        times.mark(push: true);
      } on FirebaseException catch (err) {
        // permission-denied: the rules refused it (the pin is no longer mine).
        await db.markSent(e.id, e.updatedAt, err.code);
        if (!_permanent.contains(err.code)) transientLeft = true;
      }
    }
    // Step 11 (optional): the photos, when the project has Storage.
    if (const bool.fromEnvironment('UPLOAD_PHOTOS')) await _pushPhotos(db, uid);
  } finally {
    _pushing = false;
  }
  if (_again) {
    _again = false;
    final again = _scopeRef;
    if (again != null) return pushSurveys(again); // surveys submitted meanwhile
  }
  if (transientLeft) _scheduleRetry();
}

/// The policy (see sync_status_screen.dart): 30 s, doubling, max 10 min, 6 tries.
void _scheduleRetry() {
  if (_autoTries >= 6 || _scopeRef == null) return;
  final seconds = min(30 << _autoTries, 600);
  _autoTries++;
  _retryTimer = Timer(Duration(seconds: seconds), () {
    final ref = _scopeRef;
    if (ref != null) pushSurveys(ref, auto: true);
  });
}

/// Every photo not uploaded yet goes to photos/{uid}/{entranceId}/{photoId}.jpg.
Future<void> _pushPhotos(AppDatabase db, String uid) async {
    for (final p in await db.photosToUpload()) {
      final file = FirebaseStorage.instance.ref('photos/$uid/${p.entranceId}/${p.id}.jpg');
      final meta = SettableMetadata(contentType: 'image/jpeg');
      try {
        if (p.localUri.startsWith('data:')) {
          // The web keeps the photo as a data: URI (week 3).
          await file.putString(p.localUri, format: PutStringFormat.dataUrl, metadata: meta);
        } else {
          await file.putFile(File(p.localUri), meta);
        }
        await db.markPhoto(p.id, remoteUrl: await file.getDownloadURL());
      } on FirebaseException catch (err) {
        await db.markPhoto(p.id, error: err.code);
      }
    }
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
  @override
  void initState() {
    super.initState();
    _scopeRef = ref;
        // The push, at three moments: now, back in the foreground, and when the
        // network comes back. (And on "Sync now", and after a submit.)
        pushSurveys(ref);
        _lifecycle = AppLifecycleListener(onResume: () => pushSurveys(ref));
        _network = Connectivity().onConnectivityChanged.listen((links) {
            if (!links.contains(ConnectivityResult.none)) pushSurveys(ref);
          });
    // The pull: every snapshot of my pins goes to SQLite, the truth on the
    // phone. listenManual keeps the listener alive while this widget lives.
    ref.listenManual(myPinsProvider, (_, next) {
      final pins = next.value;
      if (pins != null) {
        ref.read(databaseProvider).savePins(pins);
        ref.read(cloudTimesProvider.notifier).mark(pull: true);
      }
    }, fireImmediately: true);
  }

      @override
      void dispose() {
          _lifecycle.dispose();
          _network.cancel();
          _retryTimer?.cancel();
          _scopeRef = null;
          super.dispose();
        }


  @override
  Widget build(BuildContext context) => widget.child;
}