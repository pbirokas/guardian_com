import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardian_app/l10n/app_localizations.dart';

import '../../core/providers/app_update_provider.dart';
import '../../core/utils/launch_url.dart';

/// Blockierender Screen, wenn die installierte Version unter der Mindestversion
/// liegt. Kein Zurück möglich — der Nutzer muss aktualisieren.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final status = ref.watch(appUpdateStatusProvider).value;
    final url = status?.targetUrl ?? '';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    l.updateRequiredTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(l.updateRequiredBody, textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: url.isEmpty ? null : () => openExternalUrl(url),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l.updateNowButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
