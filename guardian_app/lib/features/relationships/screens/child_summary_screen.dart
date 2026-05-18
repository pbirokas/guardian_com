import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/child_summary.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/relationships_provider.dart';

class ChildSummaryScreen extends ConsumerStatefulWidget {
  final String childUid;
  final String childName;

  const ChildSummaryScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  ConsumerState<ChildSummaryScreen> createState() => _ChildSummaryScreenState();
}

class _ChildSummaryScreenState extends ConsumerState<ChildSummaryScreen> {
  String _period = '7d';
  ChildSummary? _summary;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await ref
          .read(parentClaimServiceProvider)
          .getChildSummary(widget.childUid, _period, forceRefresh: forceRefresh);
      if (mounted) setState(() { _summary = summary; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.childSummaryTitle),
            Text(
              widget.childName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        toolbarHeight: kToolbarHeight + 12,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(forceRefresh: true),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: '24h', label: Text(l.summaryPeriod24h)),
                ButtonSegment(value: '7d', label: Text(l.summaryPeriod7d)),
              ],
              selected: {_period},
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(l)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.summaryError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    final summary = _summary!;
    if (summary.orgs.isEmpty) {
      return Center(
        child: Text(l.summaryNoActivity, style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            l.summaryGeneratedAt(
                DateFormat('dd.MM.yyyy HH:mm').format(summary.generatedAt)),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final org in summary.orgs) _OrgCard(org: org, l: l),
      ],
    );
  }
}

class _OrgCard extends StatelessWidget {
  final ChildSummaryOrg org;
  final AppLocalizations l;

  const _OrgCard({required this.org, required this.l});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastActive = org.lastActive;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.corporate_fare_outlined),
        title: Text(org.orgName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: lastActive != null
            ? Text(
                l.summaryLastActive(
                    DateFormat('dd.MM. HH:mm').format(lastActive)),
                style: const TextStyle(fontSize: 12),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.arrow_upward,
                  label: l.summarySent(org.sentCount),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.arrow_downward,
                  label: l.summaryReceived(org.receivedCount),
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          for (final chat in org.chats)
            ListTile(
              dense: true,
              leading: Icon(
                chat.isGroup ? Icons.group_outlined : Icons.person_outline,
                size: 20,
              ),
              title: Text(chat.chatName,
                  style: const TextStyle(fontSize: 14)),
              subtitle: chat.lastActive != null
                  ? Text(
                      l.summaryLastActive(DateFormat('dd.MM. HH:mm')
                          .format(chat.lastActive!)),
                      style: const TextStyle(fontSize: 11),
                    )
                  : null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '↑ ${chat.sentCount}',
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.primary),
                  ),
                  Text(
                    '↓ ${chat.receivedCount}',
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.secondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 13, color: color)),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}
