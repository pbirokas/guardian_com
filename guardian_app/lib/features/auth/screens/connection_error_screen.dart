import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

/// Wird gezeigt, wenn der Server beim Start nicht erreichbar ist (kein Netz /
/// Server offline) — im Gegensatz zu einer wirklich ungültigen Session (401),
/// die zum Login führt. Die Anmeldung/der Session-Check wird erst erneut
/// versucht, wenn wieder eine Verbindung besteht (automatisch) oder der Nutzer
/// „Erneut versuchen" tippt. Die bestehende Session bleibt dabei erhalten.
class ConnectionErrorScreen extends ConsumerWidget {
  const ConnectionErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Auto-Retry: sobald die Verbindung zurückkehrt, den Session-Check erneut
    // anstoßen. Der Router leitet nach Erfolg passend weiter.
    ref.listen(connectivityProvider, (prev, next) {
      if (next.value == true) {
        ref.invalidate(authStateProvider);
      }
    });

    final retrying = ref.watch(authStateProvider).isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 64, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 24),
                Text(
                  l.noConnection,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l.connectionErrorMessage,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (retrying)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(authStateProvider),
                    icon: const Icon(Icons.refresh),
                    label: Text(l.connectionRetry),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
