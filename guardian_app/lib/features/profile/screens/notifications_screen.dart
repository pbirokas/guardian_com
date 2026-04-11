import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../../../core/models/notification_settings.dart';

String _intervalLabel(MessageAlertInterval interval, AppLocalizations l) =>
    switch (interval) {
      MessageAlertInterval.always => l.intervalAlways,
      MessageAlertInterval.hourly => l.intervalHourly,
      MessageAlertInterval.daily => l.intervalDaily,
      MessageAlertInterval.never => l.intervalNever,
    };

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationSettings _settings = const NotificationSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final map = doc.data()?['notificationSettings'] as Map<String, dynamic>?;
    setState(() {
      _settings = NotificationSettings.fromMap(map);
      _loading = false;
    });
  }

  Future<void> _save(NotificationSettings updated) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _settings = updated);
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'notificationSettings': updated.toMap(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l.notificationsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
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
            groupValue: _settings.newMessagesInterval,
            onChanged: (v) {
              if (v != null) _save(_settings.copyWith(newMessagesInterval: v));
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
            value: _settings.chatRequests,
            onChanged: (v) => _save(_settings.copyWith(chatRequests: v)),
          ),
          const Divider(),
          _SectionHeader(l.organizations),
          SwitchListTile(
            title: Text(l.invitations),
            subtitle: Text(l.invitationsSubtitle),
            value: _settings.memberInvites,
            onChanged: (v) => _save(_settings.copyWith(memberInvites: v)),
          ),
          SwitchListTile(
            title: Text(l.orgChanges),
            subtitle: Text(l.orgChangesSubtitle),
            value: _settings.orgUpdates,
            onChanged: (v) => _save(_settings.copyWith(orgUpdates: v)),
          ),
        ],
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
