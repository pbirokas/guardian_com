import 'dart:convert';

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
  final String? fileUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final DateTime? editedAt;
  final bool isArchived;
  final String? archivedByUid;
  final String? archivedByName;
  final String? replyToId;
  final String? replyToSenderName;
  final String? replyToText;
  final Map<String, String> reactions;
  final String type; // 'user' | 'system'
  final String? systemEvent; // 'memberAdded' | 'memberRemoved'
  final String? systemActorName;
  final String? systemTargetName;
  final bool isGif;
  final DateTime? deletedAt;
  final String? deletedBy;

  bool get isDeleted => deletedAt != null;

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
    this.fileUrl,
    this.fileName,
    this.fileSizeBytes,
    this.editedAt,
    this.isArchived = false,
    this.archivedByUid,
    this.archivedByName,
    this.replyToId,
    this.replyToSenderName,
    this.replyToText,
    this.reactions = const {},
    this.type = 'user',
    this.systemEvent,
    this.systemActorName,
    this.systemTargetName,
    this.isGif = false,
    this.deletedAt,
    this.deletedBy,
  });

  factory Message.fromAppwrite(Map<String, dynamic> data) {
    final reactJson = data['reactionsJson'] as String?;
    final reactions = (reactJson != null && reactJson.isNotEmpty)
        ? Map<String, String>.from(jsonDecode(reactJson) as Map)
        : <String, String>{};
    return Message(
      id: data[r'$id'] as String,
      senderUid: data['senderUid'] as String,
      senderName: data['senderName'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: DateTime.parse(data['sentAt'] as String).toLocal(),
      imageUrl: data['imageUrl'] as String?,
      audioUrl: data['audioUrl'] as String?,
      audioDurationMs: data['audioDurationMs'] as int?,
      pollId: data['pollId'] as String?,
      fileUrl: data['fileUrl'] as String?,
      fileName: data['fileName'] as String?,
      fileSizeBytes: data['fileSizeBytes'] as int?,
      editedAt: data['editedAt'] != null
          ? DateTime.parse(data['editedAt'] as String).toLocal()
          : null,
      isArchived: data['isArchived'] as bool? ?? false,
      archivedByUid: data['archivedByUid'] as String?,
      archivedByName: data['archivedByName'] as String?,
      replyToId: data['replyToId'] as String?,
      replyToSenderName: data['replyToSenderName'] as String?,
      replyToText: data['replyToText'] as String?,
      reactions: reactions,
      type: data['type'] as String? ?? 'user',
      systemEvent: data['systemEvent'] as String?,
      systemActorName: data['systemActorName'] as String?,
      systemTargetName: data['systemTargetName'] as String?,
      isGif: data['isGif'] as bool? ?? false,
      deletedAt: data['deletedAt'] != null
          ? DateTime.parse(data['deletedAt'] as String).toLocal()
          : null,
      deletedBy: data['deletedBy'] as String?,
    );
  }

  Map<String, dynamic> toAppwrite() => {
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'type': type,
        if (systemEvent != null) 'systemEvent': systemEvent,
        if (systemActorName != null) 'systemActorName': systemActorName,
        if (systemTargetName != null) 'systemTargetName': systemTargetName,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (audioDurationMs != null) 'audioDurationMs': audioDurationMs,
        if (pollId != null) 'pollId': pollId,
        if (fileUrl != null) 'fileUrl': fileUrl,
        if (fileName != null) 'fileName': fileName,
        if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
        if (editedAt != null) 'editedAt': editedAt!.toUtc().toIso8601String(),
        'isArchived': isArchived,
        if (archivedByUid != null) 'archivedByUid': archivedByUid,
        if (archivedByName != null) 'archivedByName': archivedByName,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
        if (replyToText != null) 'replyToText': replyToText,
        if (isGif) 'isGif': true,
        if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
        if (deletedBy != null) 'deletedBy': deletedBy,
        'reactionsJson': jsonEncode(reactions),
      };
}
