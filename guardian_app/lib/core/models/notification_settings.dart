enum MessageAlertInterval {
  always,
  hourly,
  daily,
  never;

  String get label => switch (this) {
        MessageAlertInterval.always => 'Jede Nachricht',
        MessageAlertInterval.hourly => 'Max. 1x pro Stunde',
        MessageAlertInterval.daily => 'Max. 1x pro Tag',
        MessageAlertInterval.never => 'Nie',
      };
}

class NotificationSettings {
  final MessageAlertInterval newMessagesInterval;
  final bool chatRequests;
  final bool memberInvites;
  final bool orgUpdates;

  const NotificationSettings({
    this.newMessagesInterval = MessageAlertInterval.always,
    this.chatRequests = true,
    this.memberInvites = true,
    this.orgUpdates = false,
  });

  factory NotificationSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationSettings();
    // Legacy: if old bool field exists, convert it
    final legacyEnabled = map['newMessages'] as bool?;
    final intervalName = map['newMessagesInterval'] as String?;
    final interval = intervalName != null
        ? MessageAlertInterval.values
            .where((e) => e.name == intervalName)
            .firstOrNull ?? MessageAlertInterval.always
        : (legacyEnabled == false
            ? MessageAlertInterval.never
            : MessageAlertInterval.always);
    return NotificationSettings(
      newMessagesInterval: interval,
      chatRequests: map['chatRequests'] as bool? ?? true,
      memberInvites: map['memberInvites'] as bool? ?? true,
      orgUpdates: map['orgUpdates'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'newMessagesInterval': newMessagesInterval.name,
        'chatRequests': chatRequests,
        'memberInvites': memberInvites,
        'orgUpdates': orgUpdates,
      };

  NotificationSettings copyWith({
    MessageAlertInterval? newMessagesInterval,
    bool? chatRequests,
    bool? memberInvites,
    bool? orgUpdates,
  }) =>
      NotificationSettings(
        newMessagesInterval: newMessagesInterval ?? this.newMessagesInterval,
        chatRequests: chatRequests ?? this.chatRequests,
        memberInvites: memberInvites ?? this.memberInvites,
        orgUpdates: orgUpdates ?? this.orgUpdates,
      );
}
