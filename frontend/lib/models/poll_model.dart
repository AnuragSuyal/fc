class PollModel {
  final String id;
  final String question;
  final List<PollOption> options;
  final bool isMultipleChoice;
  final int totalVotes;
  final DateTime expiresAt;
  final String createdBy;
  final DateTime createdAt;

  PollModel({
    required this.id,
    required this.question,
    required this.options,
    required this.isMultipleChoice,
    required this.totalVotes,
    required this.expiresAt,
    required this.createdBy,
    required this.createdAt,
  });

  factory PollModel.fromJson(Map<String, dynamic> json) {
    return PollModel(
      id: json['_id'] ?? '',
      question: json['question'] ?? '',
      options: (json['options'] as List? ?? [])
          .map((o) => PollOption.fromJson(o))
          .toList(),
      isMultipleChoice: json['isMultipleChoice'] ?? false,
      totalVotes: json['totalVotes'] ?? 0,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now().add(const Duration(hours: 1)),
      createdBy: json['createdBy'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class PollOption {
  final String id;
  final String text;
  int votes;

  PollOption({
    required this.id,
    required this.text,
    this.votes = 0,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['_id'] ?? '',
      text: json['text'] ?? '',
      votes: json['votes'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'text': text,
      'votes': votes,
    };
  }
}






