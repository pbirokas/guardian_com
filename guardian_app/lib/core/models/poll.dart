import 'dart:convert';

class PollOption {
  final String id;
  final String text;

  const PollOption({required this.id, required this.text});

  Map<String, dynamic> toMap() => {'id': id, 'text': text};

  factory PollOption.fromMap(Map<String, dynamic> m) =>
      PollOption(id: m['id'] as String, text: m['text'] as String);
}

class Poll {
  final String id;
  final String convId;
  final String question;
  final List<PollOption> options;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final bool multipleChoice;
  final bool isClosed;
  final bool isAnonymous;
  final DateTime? expiresAt;

  /// optionId → list of voter UIDs
  final Map<String, List<String>> votes;

  const Poll({
    required this.id,
    required this.convId,
    required this.question,
    required this.options,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.multipleChoice = false,
    this.isClosed = false,
    this.isAnonymous = false,
    this.expiresAt,
    this.votes = const {},
  });

  bool hasVoted(String uid) =>
      votes.values.any((voters) => voters.contains(uid));

  bool hasVotedFor(String uid, String optionId) =>
      (votes[optionId] ?? []).contains(uid);

  List<String> votesFor(String optionId) => votes[optionId] ?? [];

  int get totalVoters {
    final all = <String>{};
    for (final voters in votes.values) {
      all.addAll(voters);
    }
    return all.length;
  }

  factory Poll.fromAppwrite(Map<String, dynamic> data) {
    final options = (jsonDecode(data['optionsJson'] as String) as List)
        .map((o) => PollOption.fromMap(Map<String, dynamic>.from(o as Map)))
        .toList();
    final votesJson = data['votesJson'] as String?;
    final votes = (votesJson != null && votesJson.isNotEmpty)
        ? (jsonDecode(votesJson) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])))
        : <String, List<String>>{};
    return Poll(
      id: data[r'$id'] as String,
      convId: data['convId'] as String,
      question: data['question'] as String,
      options: options,
      createdBy: data['createdBy'] as String,
      createdByName: data['createdByName'] as String? ?? '',
      createdAt: DateTime.parse(data['createdAt'] as String).toLocal(),
      multipleChoice: data['multipleChoice'] as bool? ?? false,
      isClosed: data['isClosed'] as bool? ?? false,
      isAnonymous: data['isAnonymous'] as bool? ?? false,
      expiresAt: data['expiresAt'] != null
          ? DateTime.parse(data['expiresAt'] as String).toLocal()
          : null,
      votes: votes,
    );
  }

  Map<String, dynamic> toAppwrite() => {
        'convId': convId,
        'question': question,
        'optionsJson': jsonEncode(options.map((o) => o.toMap()).toList()),
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'multipleChoice': multipleChoice,
        'isClosed': isClosed,
        'isAnonymous': isAnonymous,
        if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
        'votesJson': jsonEncode({for (final o in options) o.id: <String>[]}),
      };
}
