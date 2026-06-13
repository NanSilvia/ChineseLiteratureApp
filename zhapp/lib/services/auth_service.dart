import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'db_service.dart';
import 'cache_service.dart';
import 'api_service.dart';

// Service to manage authentication state
// Provides a centralized way to check login status and user data
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

  final ApiService _api = ApiService();

  // Initialize auth state on app start.
  // Validates the stored token with the server via GET /auth/me.
  Future<void> init() async {
    if (_isInitialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.getCurrentUser();
      // Don't overwrite if login() already ran while we were awaiting
      if (_currentUser == null) {
        _currentUser = result.data;
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      // Only clear if nothing else set it
      if (_currentUser == null) {
        _currentUser = null;
      }
    }

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  // Login with real backend call.
  // Returns null on success, or an error message string on failure.
  Future<String?> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.login(username, password);

      if (result.isSuccess && result.data != null) {
        _currentUser = result.data;
        _isInitialized = true;
        _isLoading = false;
        notifyListeners();
        return null; // success
      }

      _isLoading = false;
      notifyListeners();
      return result.error ?? 'Login failed';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Login failed: $e';
    }
  }

  // Register with real backend call.
  // Returns null on success, or an error message string on failure.
  Future<String?> register(
    String username,
    String email,
    String password,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.register(username, email, password);

      if (result.isSuccess && result.data != null) {
        _currentUser = result.data;
        _isInitialized = true;
        _isLoading = false;
        notifyListeners();
        return null; // success
      }

      _isLoading = false;
      notifyListeners();
      return result.error ?? 'Registration failed';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Registration failed: $e';
    }
  }

  // Logout — revoke server tokens, clear local data.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Call server logout (revokes refresh tokens) then clear local session
      await _api.logout();

      // Clear all in-memory caches
      CacheService().clear();
      _api.invalidateAll();

      // Clear ALL local data — cards, folders, annotation cache
      await _db.clearAllLocalData();

      _currentUser = null;
    } catch (e) {
      debugPrint('Logout error: $e');
      // Ensure user is cleared even if server call fails
      _currentUser = null;
    }

    _isLoading = false;
    notifyListeners();
  }
}

// Widget for screens that require authentication
// Shows locked state with "Go to Settings" button when logged out
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
