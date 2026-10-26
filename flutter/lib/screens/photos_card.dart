import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photos.dart';
import '../providers.dart';
import 'gallery.dart';

class PhotosCard extends ConsumerStatefulWidget {
  const PhotosCard({super.key, required this.entranceId});

  final String entranceId;

  @override
  ConsumerState<PhotosCard> createState() => _PhotosCardState();
}

class _PhotosCardState extends ConsumerState<PhotosCard> {
  ExifSummary? _exif;
  bool _busy = false;

  Future<void> _run(Future<ExifSummary?> Function() action) async {
    setState(() => _busy = true);
    try {
      final summary = await action();
      if (summary != null && mounted) setState(() => _exif = summary);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(photosProvider(widget.entranceId)).value ?? const [];
    final muted = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Photos (${list.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : () => _run(() => takePhoto(context, ref, widget.entranceId)),
                  child: const Text('Take a photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : () => _run(() => pickPhoto(ref, widget.entranceId)),
                  child: const Text('From the gallery'),
                ),
              ),
            ]),
            if (_exif case final x?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Last file's EXIF: ${x.camera ?? 'no camera name'} · ${x.shotAt ?? 'no time'} · "
                      "GPS in EXIF: ${x.gpsInExif ? 'yes' : 'no'}",
                  style: muted,
                ),
              ),
            const SizedBox(height: 8),
            PhotoGrid(photos: list),
          ],
        ),
      ),
    );
  }
}