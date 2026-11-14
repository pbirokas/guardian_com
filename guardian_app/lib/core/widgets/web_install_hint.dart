import 'package:flutter/material.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/pwa_env.dart';

const _kWebInstallHintDismissed = 'web_install_hint_dismissed';

/// Hinweis für iPhone/iPad-Nutzer im Browser: Safari hat keinen eigenen
/// „Installieren“-Button, die App muss über „Teilen → Zum Home-Bildschirm“
/// hinzugefügt werden (Voraussetzung für Vollbild und später Web Push).
/// Erscheint nur im Apple-Browser, solange die App nicht installiert ist und
/// der Nutzer den Hinweis nicht geschlossen hat. Auf Android/Windows nie.
class WebInstallHint extends StatefulWidget {
  const WebInstallHint({super.key});

  @override
  State<WebInstallHint> createState() => _WebInstallHintState();
}

class _WebInstallHintState extends State<WebInstallHint> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (isAppleMobileBrowser && !isRunningAsInstalledPwa) _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kWebInstallHintDismissed) == true) return;
      if (mounted) setState(() => _visible = true);
    } catch (_) {
      // Privater Modus o. ä.: Hinweis trotzdem zeigen.
      if (mounted) setState(() => _visible = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWebInstallHintDismissed, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_to_home_screen,
                    color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.webInstallHintTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.webInstallHintBody,
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _dismiss,
                child: Text(l.webInstallHintDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
