import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Neutraler Ladescreen, der während des Session-Checks beim App-Start gezeigt
/// wird — damit nicht kurzzeitig der Login erscheint, bevor feststeht, ob der
/// Nutzer angemeldet ist (bzw. der Server erreichbar ist).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.appTitle,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
