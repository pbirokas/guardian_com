import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduledMessage {
  final String id;
  final String convId;
  final String text;
  final String senderUid;
  final String senderName;
  final DateTime scheduledFor;
  final DateTime createdAt;

  const ScheduledMessage({
    required this.id,
    required this.convId,
    required this.text,
    required this.senderUid,
    required this.senderName,
    required this.scheduledFor,
    required this.createdAt,
  });

  factory ScheduledMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScheduledMessage(
      id: doc.id,
      convId: data['convId'] as String,
      text: data['text'] as String,
      senderUid: data['senderUid'] as String,
      senderName: data['senderName'] as String? ?? '',
      scheduledFor: (data['scheduledFor'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'convId': convId,
        'text': text,
        'senderUid': senderUid,
        'senderName': senderName,
        'scheduledFor': Timestamp.fromDate(scheduledFor),
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
