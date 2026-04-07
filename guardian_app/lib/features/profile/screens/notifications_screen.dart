import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/models/notification_settings.dart';

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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Benachrichtigungen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Benachrichtigungen')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Diese Einstellungen gelten als Standard für alle Organisationen. '
              'Du kannst sie pro Organisation über das Glocken-Symbol anpassen.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const _SectionHeader('Nachrichten'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Neue Nachrichten',
                style: TextStyle(fontSize: 15)),
          ),
          RadioGroup<MessageAlertInterval>(
            groupValue: _settings.newMessagesInterval,
            onChanged: (v) {
              if (v != null) _save(_settings.copyWith(newMessagesInterval: v));
            },
            child: Column(
              children: MessageAlertInterval.values
                  .map((interval) => RadioListTile<MessageAlertInterval>(
                        title: Text(interval.label),
                        value: interval,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ))
                  .toList(),
            ),
          ),
          SwitchListTile(
            title: const Text('Chat-Anfragen'),
            subtitle: const Text('Wenn jemand einen Chat anfragt'),
            value: _settings.chatRequests,
            onChanged: (v) => _save(_settings.copyWith(chatRequests: v)),
          ),
          const Divider(),
          const _SectionHeader('Organisationen'),
          SwitchListTile(
            title: const Text('Einladungen'),
            subtitle: const Text('Bei Einladungen in Organisationen'),
            value: _settings.memberInvites,
            onChanged: (v) => _save(_settings.copyWith(memberInvites: v)),
          ),
          SwitchListTile(
            title: const Text('Org-Änderungen'),
            subtitle: const Text('Bei Änderungen in meinen Organisationen'),
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
