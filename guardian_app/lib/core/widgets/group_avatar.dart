import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

bool isStorageTrustedUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'firebasestorage.googleapis.com';
}

class GroupAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;

  const GroupAvatar({super.key, this.imageUrl, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final trusted = imageUrl != null && isStorageTrustedUrl(imageUrl!);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      backgroundImage:
          trusted ? CachedNetworkImageProvider(imageUrl!) : null,
      child: !trusted
          ? Icon(Icons.group,
              size: radius,
              color: Theme.of(context).colorScheme.onSecondaryContainer)
          : null,
    );
  }
}
