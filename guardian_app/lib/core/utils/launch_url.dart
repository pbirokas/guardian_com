import 'package:url_launcher/url_launcher.dart';

/// Öffentliche Datenschutzerklärung (GitHub Pages, Quelle: privacy_policy.html).
const privacyPolicyUrl =
    'https://pbirokas.github.io/guardian_com/privacy_policy.html';

/// Öffnet [url] extern (Browser bzw. zuständige App). Ungültige URLs werden
/// ignoriert. Gemeinsame Konvention für „im externen Browser öffnen"
/// (`Uri.tryParse` + `LaunchMode.externalApplication`).
Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
