import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../../../core/models/notification_settings.dart';
import '../../auth/providers/auth_provider.dart';
import '../../organizations/providers/organizations_provider.dart';

String _intervalLabel(MessageAlertInterval interval, AppLocalizations l) =>
    switch (interval) {
      MessageAlertInterval.always => l.intervalAlways,
      MessageAlertInterval.hourly => l.intervalHourly,
      MessageAlertInterval.daily => l.intervalDaily,
      MessageAlertInterval.never => l.intervalNever,
    };

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _save(
      WidgetRef ref, NotificationSettings updated, String uid) async {
    await ref.read(authServiceProvider).saveNotificationSettings(uid, updated);
    ref.invalidate(notificationSettingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final uid = ref.watch(authStateProvider).value?.uid;
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return settingsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l.notificationsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: Text(l.notificationsTitle)),
        body: const Center(child: Icon(Icons.error_outline)),
      ),
      data: (settings) => Scaffold(
        appBar: AppBar(title: Text(l.notificationsTitle)),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l.notificationsHint,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            _SectionHeader(l.messages),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(l.newMessages, style: const TextStyle(fontSize: 15)),
            ),
            RadioGroup<MessageAlertInterval>(
              groupValue: settings.newMessagesInterval,
              onChanged: (v) {
                if (v != null && uid != null) {
                  _save(ref, settings.copyWith(newMessagesInterval: v), uid);
                }
              },
              child: Column(
                children: MessageAlertInterval.values
                    .map((interval) => RadioListTile<MessageAlertInterval>(
                          title: Text(_intervalLabel(interval, l)),
                          value: interval,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                        ))
                    .toList(),
              ),
            ),
            SwitchListTile(
              title: Text(l.chatRequests),
              subtitle: Text(l.chatRequestsSubtitle),
              value: settings.chatRequests,
              onChanged: uid == null
                  ? null
                  : (v) => _save(ref, settings.copyWith(chatRequests: v), uid),
            ),
            const Divider(),
            _SectionHeader(l.organizations),
            SwitchListTile(
              title: Text(l.invitations),
              subtitle: Text(l.invitationsSubtitle),
              value: settings.memberInvites,
              onChanged: uid == null
                  ? null
                  : (v) =>
                      _save(ref, settings.copyWith(memberInvites: v), uid),
            ),
            SwitchListTile(
              title: Text(l.orgChanges),
              subtitle: Text(l.orgChangesSubtitle),
              value: settings.orgUpdates,
              onChanged: uid == null
                  ? null
                  : (v) => _save(ref, settings.copyWith(orgUpdates: v), uid),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold)),
    );
  }
}
