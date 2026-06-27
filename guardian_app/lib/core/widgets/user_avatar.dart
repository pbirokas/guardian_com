import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Avatar für einen Nutzer mit robustem Fehler-Fallback.
///
/// Zeigt das Profilbild aus [photoUrl] (oder ein lokal gewähltes
/// [overrideImage]), fällt aber bei fehlendem ODER nicht ladbarem Bild
/// (HTTP 402/404, Netzwerkfehler, gelöschte Datei) automatisch auf
/// [fallbackText] (Initialen) zurück — ohne die App zum Absturz zu bringen.
///
/// Technik: Das Bild läuft als [CircleAvatar.foregroundImage], die Initialen
/// liegen als [CircleAvatar.child] dahinter. Lädt das Bild, überdeckt es die
/// Initialen; schlägt der Load fehl, fängt [CircleAvatar.onForegroundImageError]
/// den Fehler ab und die Initialen bleiben sichtbar. Ein roher `NetworkImage`
/// als `backgroundImage` ohne Error-Handler führte hier zuvor zu Fatal-Crashes
/// (z.B. HTTP 402 von Firebase Storage nach Ablauf des Gratis-Kontingents).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.fallbackText,
    this.radius,
    this.backgroundColor,
    this.foregroundColor,
    this.textStyle,
    this.overrideImage,
  });

  /// URL des Profilbilds. `null`/leer → es werden direkt die Initialen gezeigt.
  final String? photoUrl;

  /// Anzuzeigender Text (Initialen), wenn kein Bild verfügbar ist oder der
  /// Bild-Load fehlschlägt.
  final String fallbackText;

  final double? radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TextStyle? textStyle;

  /// Optionales lokales Bild (z.B. frisch ausgewähltes Foto), das Vorrang vor
  /// [photoUrl] hat. Üblicherweise ein `MemoryImage`.
  final ImageProvider? overrideImage;

  @override
  Widget build(BuildContext context) {
    final hasUrl = photoUrl != null && photoUrl!.isNotEmpty;
    final ImageProvider? image = overrideImage ??
        (hasUrl ? CachedNetworkImageProvider(photoUrl!) : null);
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      foregroundImage: image,
      // Fängt Bild-Ladefehler ab, damit ein fehlgeschlagenes Bild nicht die
      // App crasht — die Initialen (child) bleiben dann sichtbar.
      onForegroundImageError: image != null ? (_, _) {} : null,
      child: Text(fallbackText, style: textStyle),
    );
  }
}
