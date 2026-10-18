class Note {
  const Note({
    required this.id,
    required this.date,
    this.initiativeId,
    required this.text,
    required this.createdAt,
  });

  final String id;

  /// Local grouping day, `YYYY-MM-DD`.
  final String date;
  final String? initiativeId;
  final String text;
  final DateTime createdAt;

  Note copyWith({
    String? id,
    String? date,
    String? initiativeId,
    String? text,
    DateTime? createdAt,
    bool clearInitiative = false,
  }) {
    return Note(
      id: id ?? this.id,
      date: date ?? this.date,
      initiativeId:
          clearInitiative ? null : (initiativeId ?? this.initiativeId),
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'].toString(),
        date: json['date']?.toString() ?? '',
        initiativeId: _nullableString(json['initiativeId']),
        text: json['text']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'initiativeId': initiativeId,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static String? _nullableString(Object? value) {
    final text = value?.toString();
    return (text == null || text.isEmpty) ? null : text;
  }
}
