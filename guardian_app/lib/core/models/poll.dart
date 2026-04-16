import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Poll.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawVotes = Map<String, dynamic>.from(data['votes'] as Map? ?? {});
    return Poll(
      id: doc.id,
      convId: data['convId'] as String,
      question: data['question'] as String,
      options: (data['options'] as List)
          .map((o) => PollOption.fromMap(Map<String, dynamic>.from(o as Map)))
          .toList(),
      createdBy: data['createdBy'] as String,
      createdByName: data['createdByName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      multipleChoice: data['multipleChoice'] as bool? ?? false,
      isClosed: data['isClosed'] as bool? ?? false,
      isAnonymous: data['isAnonymous'] as bool? ?? false,
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      votes: rawVotes.map(
        (optionId, voterList) =>
            MapEntry(optionId, List<String>.from(voterList as List? ?? [])),
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'convId': convId,
        'question': question,
        'options': options.map((o) => o.toMap()).toList(),
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(createdAt),
        'multipleChoice': multipleChoice,
        'isClosed': isClosed,
        'isAnonymous': isAnonymous,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
        // Initialise every option with an empty voter list
        'votes': {for (final o in options) o.id: <String>[]},
      };
}
