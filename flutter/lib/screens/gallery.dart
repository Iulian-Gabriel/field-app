import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../contract/contract.dart' show ReviewStatus;

Widget photoImage(PhotoRow p, {BoxFit fit = BoxFit.cover}) => kIsWeb
    ? Image.network(p.localUri, fit: fit)
    : Image.file(File(p.localUri), fit: fit);

/// Photos that some newer photo replaces.
Set<String> replacedIds(List<PhotoRow> all) =>
    {for (final x in all) if (x.replacesPhotoId != null) x.replacesPhotoId!};

class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.photos});

  final List<PhotoRow> photos; // already newest first

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No photos of this entrance yet. Take the first one.'),
      );
    }
    final replaced = replacedIds(photos);
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final p in photos)
          Semantics(
            button: true,
            label: 'Photo taken ${p.takenAt}'
                '${replaced.contains(p.id) ? ', replaced' : p.reviewStatus == ReviewStatus.retake ? ', retake requested' : ''}',
            child: InkWell(
              onTap: () => context.push('/photos/${p.id}'),
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: photoImage(p)),
                if (replaced.contains(p.id))
                  const _Badge('Replaced', Colors.grey)
                else if (p.reviewStatus == ReviewStatus.retake)
                  const _Badge('Retake', Colors.red),
              ]),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
    ),
  );
}