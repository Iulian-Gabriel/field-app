import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../contract/contract.dart';
import '../providers.dart';
import 'status_chip.dart';

class BuildingScreen extends ConsumerWidget {
  const BuildingScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final building = ref.watch(buildingProvider(id)).value;
    final entrances = [
      for (final e in ref.watch(entrancesProvider).value ?? const <Entrance>[])
        if (e.buildingId == id) e,
    ];
    if (building == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('No such building.')));
    }
    final submitted =
        entrances.where((e) => e.surveyStatus == SurveyStatus.submitted).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Building')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(building.label, style: Theme.of(context).textTheme.headlineSmall),
          if (building.comment != null) Text('Office note: ${building.comment}'),
          const SizedBox(height: 8),
          Text('${entrances.length} entrances · $submitted submitted',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final e in entrances)
            Card(
              child: ListTile(
                title: Text(e.entranceName),
                subtitle: Text('${e.street} ${e.number}'),
                trailing: StatusChip(status: e.surveyStatus),
                onTap: () => context.push('/entrances/${e.id}'),
              ),
            ),
        ],
      ),
    );
  }
}