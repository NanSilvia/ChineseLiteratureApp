/// User model for authentication
class UserModel {
  final int? id;
  final String username;
  final String? email;
  final String? token;
  final String? refreshToken;

  UserModel({
    this.id,
    required this.username,
    this.email,
    this.token,
    this.refreshToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'token': token,
      'refreshToken': refreshToken,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      username: map['username'] as String? ?? '',
      email: map['email'] as String?,
      token: map['token'] as String?,
      refreshToken: map['refreshToken'] as String?,
    );
  }

  UserModel copyWith({
    int? id,
    String? username,
    String? email,
    String? token,
    String? refreshToken,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  bool get isLoggedIn => token != null && token!.isNotEmpty;
}
