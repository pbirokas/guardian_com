import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// A single topic shown as an expandable tile inside [HelpSheet].
class HelpTopic {
  final IconData icon;
  final String title;
  final String body;

  const HelpTopic({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// A modal bottom sheet that explains a screen's features.
///
/// Shows a list of [topics] as collapsible [ExpansionTile]s.
/// When [onStartTour] is provided a "Tour starten" button appears in the
/// header — tapping it closes the sheet and triggers the step-by-step tour.
class HelpSheet extends StatelessWidget {
  final String screenTitle;
  final List<HelpTopic> topics;

  /// Called when the user taps "Tour starten".
  /// The caller is responsible for closing the sheet first.
  final VoidCallback? onStartTour;

  const HelpSheet({
    super.key,
    required this.screenTitle,
    required this.topics,
    this.onStartTour,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Column(
        children: [
          // ── Handle ────────────────────────────────────────────────────────
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Header: title + tour button ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.help_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    screenTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (onStartTour != null)
                  FilledButton.icon(
                    onPressed: onStartTour,
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: Text(l.helpTourButton),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── Topics list ───────────────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              children: topics
                  .map(
                    (topic) => ExpansionTile(
                      leading: Icon(topic.icon, color: colorScheme.primary),
                      title: Text(
                        topic.title,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            topic.body,
                            style: TextStyle(
                              color: Colors.grey[700],
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        ), // Column
      ), // Material
    );
  }
}
