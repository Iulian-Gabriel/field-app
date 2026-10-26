import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../contract/contract.dart' show ReviewStatus;
import '../photos.dart';
import '../providers.dart';
import 'gallery.dart';

class PhotoScreen extends ConsumerWidget {
  const PhotoScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(photoProvider(id)).value;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No such photo.')));
    }
    final all = ref.watch(photosProvider(p.entranceId)).value ?? const [];
    final replaced = replacedIds(all).contains(p.id);
    final retake = p.reviewStatus == ReviewStatus.retake && !replaced;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(aspectRatio: 4 / 3, child: photoImage(p, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          Text('Taken: ${DateTime.parse(p.takenAt).toLocal().toString().substring(0, 19)}'),
          Text(p.lat == null || p.lng == null
              ? 'Position: no position'
              : 'Position: ${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}'),
          Text('Review: ${replaced ? 'replaced by a newer photo' : p.reviewStatus.name}'),
          if (p.reviewStatus == ReviewStatus.retake && p.reviewNote != null)
            Text('Office note: ${p.reviewNote}'),
          const SizedBox(height: 12),
          if (retake)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                try {
                  final done = await takePhoto(context, ref, p.entranceId, replaces: p.id);
                  if (done != null && context.mounted) context.pop();
                } on FormatException catch (e) {
                  if (context.mounted) _say(context, e.message.toString());
                }
              },
              child: const Text('Retake'),
            ),
          const SizedBox(height: 8),
          // Debug: stands in for the office until week 4.
          OutlinedButton(
            onPressed: () => _askNote(context, ref, p.id),
            child: const Text('Debug: mark as retake'),
          ),
        ],
      ),
    );
  }

  Future<void> _askNote(BuildContext context, WidgetRef ref, String photoId) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Why a retake?'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'too dark')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Mark')),
        ],
      ),
    );
    if (note == null) return;
    try {
      await ref.read(databaseProvider).markRetake(photoId, note, ref.read(meProvider));
    } on FormatException catch (e) {
      if (context.mounted) _say(context, e.message.toString()); // P1's message
    }
  }

  void _say(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}