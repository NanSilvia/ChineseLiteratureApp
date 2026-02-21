/// User model for authentication
class UserModel {
  final int? id;
  final String username;
  final String? email;
  final String? token;

  UserModel({this.id, required this.username, this.email, this.token});

  Map<String, dynamic> toMap() {
    return {'id': id, 'username': username, 'email': email, 'token': token};
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      username: map['username'] as String? ?? '',
      email: map['email'] as String?,
      token: map['token'] as String?,
    );
  }

  bool get isLoggedIn => token != null && token!.isNotEmpty;
}
