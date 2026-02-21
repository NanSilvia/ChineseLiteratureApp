/// Folder model representing a category for filtering/sorting cards
class FolderModel {
  final int? id;
  final String name;

  FolderModel({this.id, required this.name});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  factory FolderModel.fromMap(Map<String, dynamic> map) {
    return FolderModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
    );
  }

  FolderModel copyWith({int? id, String? name}) {
    return FolderModel(id: id ?? this.id, name: name ?? this.name);
  }
}
