import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/relationships_provider.dart';
import '../../organizations/providers/organizations_provider.dart';

/// Modal bottom sheet that gives a quick overview of the user's verified
/// family connections:
///   - Child view  → list of verified parents
///   - Parent view → list of verified children, each with co-parents
///
/// Also shows a badge counter for pending incoming claims and pending
/// org-invite consents.
class FamilyTreeSheet extends ConsumerWidget {
  const FamilyTreeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final appUser = ref.watch(currentAppUserProvider).value;
    final childrenAsync = ref.watch(myChildrenProvider);
    final parentsAsync = ref.watch(myParentsProvider);
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final isChild = appUser?.isChild ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.88,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // ── Handle + title ────────────────────────────────────────────
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.account_tree,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    l.myFamily,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/relationships');
                    },
                    child: Text(l.myRelationships),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (isChild) ...[
                    // ── Child: show verified parents ──
                    _SectionLabel(l.myParents),
                    ...parentsAsync.when(
                      data: (parents) {
                        if (parents.isEmpty) {
                          return [_EmptyHint(l.noParents)];
                        }
                        return parents
                            .map((p) => _PersonTile(
                                  name: p['displayName'] as String? ?? '',
                                  email: p['email'] as String? ?? '',
                                  photoUrl: p['photoUrl'] as String?,
                                  subtitleText: l.verifiedParent,
                                  subtitleIcon: Icons.shield_outlined,
                                ))
                            .toList();
                      },
                      loading: () => [const _LoadingTile()],
                      error: (_, _) => const [],
                    ),
                  ] else ...[
                    // ── Parent: show children with co-parents ──
                    _SectionLabel(l.myChildren),
                    ...childrenAsync.when(
                      data: (children) {
                        if (children.isEmpty) {
                          return [_EmptyHint(l.noChildren)];
                        }
                        return children
                            .map((c) => _ChildWithCoParentsTile(
                                  child: c,
                                  currentUid: currentUid,
                                ))
                            .toList();
                      },
                      loading: () => [const _LoadingTile()],
                      error: (_, _) => const [],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ─── Empty hint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
    );
  }
}

// ─── Loading placeholder ─────────────────────────────────────────────────────

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

// ─── Generic person tile ─────────────────────────────────────────────────────

class _PersonTile extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;
  final String subtitleText;
  final IconData subtitleIcon;

  const _PersonTile({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.subtitleText,
    required this.subtitleIcon,
  });

  @override
  Widget build(BuildContext context) {
    final initials =
        (name.isNotEmpty ? name[0] : (email.isNotEmpty ? email[0] : '?'))
            .toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null ? Text(initials) : null,
      ),
      title: Text(name.isNotEmpty ? name : email),
      subtitle: Row(
        children: [
          Icon(subtitleIcon,
              size: 12,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(subtitleText,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

// ─── Child tile with co-parents ──────────────────────────────────────────────

class _ChildWithCoParentsTile extends StatelessWidget {
  final Map<String, dynamic> child;
  final String currentUid;

  const _ChildWithCoParentsTile({
    required this.child,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = child['displayName'] as String? ?? '';
    final email = child['email'] as String? ?? '';
    final photoUrl = child['photoUrl'] as String?;
    final allParentUids =
        List<String>.from(child['verifiedParentUids'] as List? ?? []);
    final coParentUids =
        allParentUids.where((uid) => uid != currentUid).toList();

    final initials =
        (name.isNotEmpty ? name[0] : (email.isNotEmpty ? email[0] : '?'))
            .toUpperCase();

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        child: photoUrl == null ? Text(initials) : null,
      ),
      title: Text(name.isNotEmpty ? name : email),
      subtitle: coParentUids.isEmpty
          ? Row(
              children: [
                Icon(Icons.person_outlined,
                    size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(l.onlyParent,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600])),
              ],
            )
          : _CoParentsSubtitle(uids: coParentUids, l: l),
    );
  }
}

// ─── Co-parents subtitle row (async) ─────────────────────────────────────────

class _CoParentsSubtitle extends StatelessWidget {
  final List<String> uids;
  final AppLocalizations l;

  const _CoParentsSubtitle({required this.uids, required this.l});

  Future<List<String>> _loadNames() async {
    final db = FirebaseFirestore.instance;
    final docs = await Future.wait(
        uids.map((u) => db.collection('users').doc(u).get()));
    return docs
        .where((d) => d.exists)
        .map((d) =>
            (d.data() as Map<String, dynamic>)['displayName'] as String? ??
            (d.data() as Map<String, dynamic>)['email'] as String? ??
            '?')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _loadNames(),
      builder: (ctx, snap) {
        final names = snap.data;
        final text = names == null
            ? '…'
            : '${l.coParentsLabel}: ${names.join(', ')}';
        return Row(
          children: [
            Icon(Icons.people_outline,
                size: 12,
                color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
