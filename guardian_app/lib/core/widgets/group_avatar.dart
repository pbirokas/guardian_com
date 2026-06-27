import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../appwrite_client.dart';

class GroupAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;

  /// Optionales lokales Bild (z.B. frisch ausgewähltes Foto), das Vorrang vor
  /// [imageUrl] hat. Üblicherweise ein `MemoryImage`.
  final ImageProvider? overrideImage;

  const GroupAvatar(
      {super.key, this.imageUrl, this.radius = 20, this.overrideImage});

  @override
  Widget build(BuildContext context) {
    final trusted = imageUrl != null && isTrustedStorageHost(imageUrl!);
    final image =
        overrideImage ?? (trusted ? CachedNetworkImageProvider(imageUrl!) : null);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      // foregroundImage + onForegroundImageError: schlägt der Bild-Load fehl
      // (z.B. HTTP 402), bleibt das Gruppen-Icon (child) sichtbar statt zu crashen.
      foregroundImage: image,
      onForegroundImageError: image != null ? (_, _) {} : null,
      child: Icon(Icons.group,
          size: radius,
          color: Theme.of(context).colorScheme.onSecondaryContainer),
    );
  }
}
