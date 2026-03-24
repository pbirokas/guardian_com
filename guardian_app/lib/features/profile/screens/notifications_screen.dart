import 'package:flutter/material.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _newMessages = true;
  bool _chatRequests = true;
  bool _memberInvites = true;
  bool _orgUpdates = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benachrichtigungen')),
      body: ListView(
        children: [
          const _SectionHeader('Nachrichten'),
          SwitchListTile(
            title: const Text('Neue Nachrichten'),
            subtitle: const Text('Bei jeder neuen Chat-Nachricht'),
            value: _newMessages,
            onChanged: (v) => setState(() => _newMessages = v),
          ),
          SwitchListTile(
            title: const Text('Chat-Anfragen'),
            subtitle: const Text('Wenn jemand einen Chat anfragt'),
            value: _chatRequests,
            onChanged: (v) => setState(() => _chatRequests = v),
          ),
          const Divider(),
          const _SectionHeader('Organisationen'),
          SwitchListTile(
            title: const Text('Einladungen'),
            subtitle: const Text('Bei Einladungen in Organisationen'),
            value: _memberInvites,
            onChanged: (v) => setState(() => _memberInvites = v),
          ),
          SwitchListTile(
            title: const Text('Org-Änderungen'),
            subtitle: const Text('Bei Änderungen in meinen Organisationen'),
            value: _orgUpdates,
            onChanged: (v) => setState(() => _orgUpdates = v),
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
