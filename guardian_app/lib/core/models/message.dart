import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final String? imageUrl;
  final String? audioUrl;
  final int? audioDurationMs;
  final String? pollId;

  const Message({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.imageUrl,
    this.audioUrl,
    this.audioDurationMs,
    this.pollId,
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      id: doc.id,
      senderUid: data['senderUid'] as String,
      senderName: data['senderName'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      imageUrl: data['imageUrl'] as String?,
      audioUrl: data['audioUrl'] as String?,
      audioDurationMs: data['audioDurationMs'] as int?,
      pollId: data['pollId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'sentAt': Timestamp.fromDate(sentAt),
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (audioDurationMs != null) 'audioDurationMs': audioDurationMs,
        if (pollId != null) 'pollId': pollId,
      };
}
