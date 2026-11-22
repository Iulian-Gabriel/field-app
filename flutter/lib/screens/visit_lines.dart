import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contract/contract.dart';
import '../providers.dart';
import '../wire.dart';

/// Exercises 1, 2 and 5 on the entrance screen.
class VisitLines extends ConsumerStatefulWidget {
  const VisitLines({super.key, required this.entrance});

  final Entrance entrance;

  @override
  ConsumerState<VisitLines> createState() => _VisitLinesState();
}

class _VisitLinesState extends ConsumerState<VisitLines> {
  @override
  void initState() {
    super.initState();
    // Remember the visit once, when the screen opens: in SQLite and in the
    // store — after this first frame, since a provider may not change while
    // the widget tree is being built.
    Future(() {
      ref.read(databaseProvider).markOpened(widget.entrance.id);
      ref.read(recentProvider.notifier).open(widget.entrance.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final openedAt = ref.watch(openedAtProvider(widget.entrance.id)).value;
    final small = Theme.of(context).textTheme.bodySmall;
    // Week 5: the dev card can put a value in SQLite the contract refuses
    // (stories = 99). Say so here instead of breaking the whole screen.
    String roundTrip;
    try {
      final json = toWire(widget.entrance);
      final same = toWire(fromWire(json)) == json;
      roundTrip = '${same ? 'Round trip: same JSON ✓' : 'Round trip: DIFFERENT ✗'} · '
          '${json.length} characters, ${(jsonDecode(json) as Map).length} keys';
    } on FormatException catch (e) {
      roundTrip = 'Round trip: not valid for the contract ✗ (${e.message})';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Opened on this phone: ${openedAt == null ? 'never' : DateTime.parse(openedAt).toLocal().toString().substring(0, 19)}',
            style: small),
        Text(roundTrip, style: small?.copyWith(fontFamily: 'monospace')),
      ],
    );
  }
}