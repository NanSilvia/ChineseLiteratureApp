import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'db_service.dart';
import 'cache_service.dart';
import 'api_service.dart';

/// Service to manage authentication state
/// Provides a centralized way to check login status and user data
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  final DbService _db = DbService();
  UserModel? _currentUser;
  bool _isInitialized = false;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _currentUser!.isLoggedIn;
  bool get isLoggedOut => !isLoggedIn;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  int? get currentUserId => _currentUser?.id;

  /// Initialize auth state on app start
  Future<void> init() async {
    if (_isInitialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      _currentUser = await _db.getCurrentUser();

      // If we have a token, verify with server
      if (_currentUser != null && _currentUser!.isLoggedIn) {
        // TODO: Call GET /auth/me to verify token
        // For now, assume token is valid if it exists
      }
    } catch (e) {
      print('Auth init error: $e');
      _currentUser = null;
    }

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  /// Login user
  Future<String?> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Replace with actual API call
      // For now, simulate login
      final user = UserModel(
        id: 1,
        username: username,
        email: '$username@example.com',
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _db.saveUser(user);
      _currentUser = user;

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Login failed: $e';
    }
  }

  /// Register new user
  Future<String?> register(
    String username,
    String email,
    String password,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Replace with actual API call
      // For now, simulate registration
      final user = UserModel(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        username: username,
        email: email,
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _db.saveUser(user);
      _currentUser = user;

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Registration failed: $e';
    }
  }

  /// Logout current user
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Clear user-specific cached data
      if (_currentUser?.id != null) {
        await _db.clearUserData(_currentUser!.id!);
      }

      // Clear all in-memory caches
      CacheService().clear();
      ApiService().invalidateAll();

      // Clear persistent annotation cache
      await _db.clearAllCache();

      await _db.deleteUser();
      _currentUser = null;
    } catch (e) {
      print('Logout error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}

/// Widget for screens that require authentication
/// Shows locked state with "Go to Settings" button when logged out
class AuthGate extends StatelessWidget {
  final Widget child;
  final String message;
  final VoidCallback? onGoToSettings;

  const AuthGate({
    super.key,
    required this.child,
    this.message = 'Please log in to access this feature.',
    this.onGoToSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService(),
      builder: (context, _) {
        final auth = AuthService();

        if (!auth.isInitialized || auth.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (auth.isLoggedOut) {
          return _LockedStateView(
            message: message,
            onGoToSettings: onGoToSettings,
          );
        }

        return child;
      },
    );
  }
}

class _LockedStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onGoToSettings;

  const _LockedStateView({required this.message, this.onGoToSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onGoToSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
