import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../contract/contract.dart';
import '../providers.dart';
import '../route_filter.dart';
import 'status_chip.dart';

const _labels = {null: 'All', 'todo': 'To do', 'done': 'Done', 'skipped': 'Skipped'};

class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({super.key});

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  // Lives in the State: the tab's branch stays mounted while the entrance
  // screen is on top, so the choice survives going there and back.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(fixturesProvider);
    final byId = {for (final e in ref.watch(entrancesProvider).value ?? const <Entrance>[]) e.id: e};
    final route = f.routes.firstWhere((r) => r.workerId == f.me);
    final all = f.stops.where((s) => s.routeId == route.id).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final stops = filterStops(all, _filter);
    return Scaffold(
      appBar: AppBar(title: Text('${route.name} · ${route.date}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String?>(
              showSelectedIcon: false,
              segments: [
                for (final entry in _labels.entries)
                  ButtonSegment<String?>(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: stops.isEmpty
                ? Center(
                child: Text(
                    'No ${_labels[_filter]!.toLowerCase()} stops on this route.'))
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: stops.length,
              itemBuilder: (context, i) {
                final e = byId[stops[i].entranceId];
                if (e == null) return const SizedBox.shrink(); // SQLite not read yet
                return Card(
                  child: ListTile(
                    leading: Text('${stops[i].order}',
                        style: Theme.of(context).textTheme.titleLarge),
                    title: Text('${e.street} ${e.number}'),
                    subtitle: Text(e.entranceName),
                    trailing: Hero(
                        tag: 'status-${e.id}',
                        child: StatusChip(status: e.surveyStatus)),
                    onTap: () => context.push('/entrances/${e.id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}