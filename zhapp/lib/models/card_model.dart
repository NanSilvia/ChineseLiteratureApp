// Card model representing a learning item with Chinese text
class CardModel {
  final int? id;
  final String? title;
  final String textZh;
  final int? folderId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String source; // 'ocr' or 'manual'

  CardModel({
    this.id,
    this.title,
    required this.textZh,
    this.folderId,
    required this.createdAt,
    this.updatedAt,
    this.source = 'manual',
  });

  // First 100 characters of Chinese text for preview
  String get previewTextZh {
    if (textZh.length <= 100) return textZh;
    return '${textZh.substring(0, 100)}...';
  }

  // Display title with preview logic
  // If title exists and is not empty -> show title
  // Otherwise -> null (caller should use previewTextZh)
  String? get displayTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'textZh': textZh,
      'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'source': source,
    };
  }

  factory CardModel.fromMap(Map<String, dynamic> map) {
    return CardModel(
      id: map['id'] as int?,
      title: map['title'] as String?,
      textZh: map['textZh'] as String? ?? '',
      folderId: map['folderId'] as int?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      source: map['source'] as String? ?? 'manual',
    );
  }

  CardModel copyWith({
    int? id,
    String? title,
    String? textZh,
    int? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? source,
  }) {
    return CardModel(
      id: id ?? this.id,
      title: title ?? this.title,
      textZh: textZh ?? this.textZh,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
    );
  }
}
