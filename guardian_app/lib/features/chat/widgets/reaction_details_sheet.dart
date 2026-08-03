import 'package:flutter/material.dart';
import 'package:guardian_app/l10n/app_localizations.dart';

import '../../../core/models/org_member.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/utils/initials.dart';

/// Ein Reagierender mit aufgelöstem Namen/Avatar.
class _Reactor {
  final String name;
  final String? photoUrl;
  final String emoji;

  const _Reactor({required this.name, this.photoUrl, required this.emoji});
}

/// Zeigt an, wer mit welchem Emoji auf eine Nachricht reagiert hat.
///
/// Rein informativ — das Setzen/Entfernen einer Reaktion läuft weiterhin
/// ausschließlich über das Long-Press-Menü der Nachricht.
class ReactionDetailsSheet extends StatefulWidget {
  /// `Message.reactions` — `Map<uid, emoji>`.
  final Map<String, String> reactions;

  /// Für die Auflösung uid → Name/Avatar. Unbekannte UIDs (z.B. inzwischen
  /// ausgetretene Mitglieder) werden als „Unbekannt" gelistet, zählen aber mit,
  /// damit die Zähler zur Nachricht passen.
  final List<OrgMember> members;

  const ReactionDetailsSheet({
    super.key,
    required this.reactions,
    required this.members,
  });

  @override
  State<ReactionDetailsSheet> createState() => _ReactionDetailsSheetState();
}

class _ReactionDetailsSheetState extends State<ReactionDetailsSheet> {
  /// null = Filter „Alle"
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final memberByUid = {for (final m in widget.members) m.uid: m};
    final reactors = widget.reactions.entries.map((e) {
      final member = memberByUid[e.key];
      return _Reactor(
        name: member?.displayName ?? l.unknownUser,
        photoUrl: member?.photoUrl,
        emoji: e.value,
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Zähler je Emoji, Chips nach Anzahl absteigend
    final counts = <String, int>{};
    for (final r in reactors) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final emojis = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    final visible = _filter == null
        ? reactors
        : reactors.where((r) => r.emoji == _filter).toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ChoiceChip(
                  label: Text(l.reactionsAllCount(reactors.length)),
                  selected: _filter == null,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final emoji in emojis) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('$emoji  ${counts[emoji]}'),
                    selected: _filter == emoji,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = emoji),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final r = visible[i];
                return ListTile(
                  leading: UserAvatar(
                    photoUrl: r.photoUrl,
                    fallbackText:
                        initialsFor(r.name),
                  ),
                  title: Text(r.name),
                  trailing:
                      Text(r.emoji, style: const TextStyle(fontSize: 22)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

