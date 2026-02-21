import 'dart:async';
import '../models/card_model.dart';
import '../models/folder_model.dart';
import '../models/user_model.dart';
import 'db_service.dart';
import 'connectivity_service.dart';

/// Result wrapper for API operations
class ApiResult<T> {
  final T? data;
  final String? error;
  final bool isOffline;

  ApiResult.success(this.data) : error = null, isOffline = false;

  ApiResult.error(this.error) : data = null, isOffline = false;

  ApiResult.offline()
    : data = null,
      error = 'No internet connection',
      isOffline = true;

  bool get isSuccess => error == null && !isOffline;
}

/// Service for API calls with offline handling
/// Note: This is a mock implementation. Replace with actual HTTP calls when backend is ready.
class ApiService {
  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  ApiService._internal();

  final DbService _db = DbService();
  final ConnectivityService _connectivity = ConnectivityService();

  // Base URL for API (configure when backend is ready)
  // ignore: unused_field
  static const String _baseUrl = 'http://localhost:3000/api';

  // ==================== CARDS ====================

  /// Fetch all cards from server
  /// Returns cached data if offline
  Future<ApiResult<List<CardModel>>> getCards({int? folderId}) async {
    if (_connectivity.isOffline) {
      // Return cached data when offline
      final cached = await _db.loadCards(folderId: folderId);
      return ApiResult.success(cached);
    }

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(Uri.parse('$_baseUrl/cards'));
      // final data = jsonDecode(response.body) as List;
      // final cards = data.map((e) => CardModel.fromMap(e)).toList();

      // For now, return local data (simulating server response)
      final cards = await _db.loadCards(folderId: folderId);

      // Sort by createdAt descending (most recent first)
      cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return ApiResult.success(cards);
    } catch (e) {
      return ApiResult.error('Failed to fetch cards: $e');
    }
  }

  /// Fetch a single card by ID
  Future<ApiResult<CardModel>> getCardById(int id) async {
    if (_connectivity.isOffline) {
      final cached = await _db.getCardById(id);
      if (cached != null) {
        return ApiResult.success(cached);
      }
      return ApiResult.error('This card is not available offline yet.');
    }

    try {
      // TODO: Replace with actual API call
      // final response = await http.get(Uri.parse('$_baseUrl/card/$id'));
      // final card = CardModel.fromMap(jsonDecode(response.body));

      final card = await _db.getCardById(id);
      if (card == null) {
        return ApiResult.error('Card not found');
      }

      // Cache the card locally
      // await _db.updateCard(card);

      return ApiResult.success(card);
    } catch (e) {
      return ApiResult.error('Failed to fetch card: $e');
    }
  }

  /// Create a new card (ONLINE ONLY)
  Future<ApiResult<CardModel>> createCard({
    String? title,
    required String textZh,
    int? folderId,
    String source = 'manual',
  }) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$_baseUrl/card'),
      //   body: jsonEncode({
      //     'title': title,
      //     'textZh': textZh,
      //     'folderId': folderId,
      //     'source': source,
      //   }),
      // );
      // final card = CardModel.fromMap(jsonDecode(response.body));

      // For now, save locally and simulate server response
      final card = CardModel(
        title: title,
        textZh: textZh,
        folderId: folderId,
        createdAt: DateTime.now(),
        source: source,
      );

      final id = await _db.saveCard(card);
      final savedCard = card.copyWith(id: id);

      return ApiResult.success(savedCard);
    } catch (e) {
      return ApiResult.error('Failed to create card: $e');
    }
  }

  /// Delete a card
  Future<ApiResult<bool>> deleteCard(int id) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      await _db.deleteCard(id);
      return ApiResult.success(true);
    } catch (e) {
      return ApiResult.error('Failed to delete card: $e');
    }
  }

  // ==================== FOLDERS ====================

  /// Fetch all folders/categories
  Future<ApiResult<List<FolderModel>>> getFolders() async {
    if (_connectivity.isOffline) {
      final cached = await _db.loadFolders();
      return ApiResult.success(cached);
    }

    try {
      // TODO: Replace with actual API call
      final folders = await _db.loadFolders();
      return ApiResult.success(folders);
    } catch (e) {
      return ApiResult.error('Failed to fetch folders: $e');
    }
  }

  /// Create a new folder
  Future<ApiResult<FolderModel>> createFolder(String name) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      final folder = FolderModel(name: name);
      final id = await _db.saveFolder(folder);
      return ApiResult.success(folder.copyWith(id: id));
    } catch (e) {
      return ApiResult.error('Failed to create folder: $e');
    }
  }

  // ==================== ANALYSIS (ONLINE ONLY) ====================

  /// Get analysis for a card's Chinese text (ONLINE ONLY)
  Future<ApiResult<Map<String, dynamic>>> analyzeText(String textZh) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$_baseUrl/analyze'),
      //   body: jsonEncode({'textZh': textZh}),
      // );
      // return ApiResult.success(jsonDecode(response.body));

      // Mock analysis result
      await Future.delayed(
        const Duration(seconds: 1),
      ); // Simulate network delay

      return ApiResult.success({
        'characters': textZh.length,
        'words': _countChineseWords(textZh),
        'analysis':
            'Analysis placeholder - connect to backend for real analysis',
      });
    } catch (e) {
      return ApiResult.error('Failed to analyze text: $e');
    }
  }

  int _countChineseWords(String text) {
    // Simple word count for Chinese (characters as proxy)
    return text.replaceAll(RegExp(r'\s+'), '').length;
  }

  // ==================== AUTHENTICATION ====================

  /// Login user
  Future<ApiResult<UserModel>> login(String username, String password) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      // final response = await http.post(
      //   Uri.parse('$_baseUrl/auth/login'),
      //   body: jsonEncode({'username': username, 'password': password}),
      // );

      // Simulate successful login
      await Future.delayed(const Duration(milliseconds: 500));

      final user = UserModel(
        id: 1,
        username: username,
        email: '$username@example.com',
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _db.saveUser(user);
      return ApiResult.success(user);
    } catch (e) {
      return ApiResult.error('Failed to login: $e');
    }
  }

  /// Register new user
  Future<ApiResult<UserModel>> register(
    String username,
    String email,
    String password,
  ) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      await Future.delayed(const Duration(milliseconds: 500));

      final user = UserModel(
        id: 1,
        username: username,
        email: email,
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      );

      await _db.saveUser(user);
      return ApiResult.success(user);
    } catch (e) {
      return ApiResult.error('Failed to register: $e');
    }
  }

  /// Logout user
  Future<ApiResult<bool>> logout() async {
    try {
      // TODO: Replace with actual API call to invalidate token
      await _db.clearUser();
      return ApiResult.success(true);
    } catch (e) {
      return ApiResult.error('Failed to logout: $e');
    }
  }

  /// Get current user
  Future<ApiResult<UserModel?>> getCurrentUser() async {
    try {
      final user = await _db.getUser();

      if (_connectivity.isOnline && user != null) {
        // TODO: Validate token with server
        // final response = await http.get(
        //   Uri.parse('$_baseUrl/auth/me'),
        //   headers: {'Authorization': 'Bearer ${user.token}'},
        // );
      }

      return ApiResult.success(user);
    } catch (e) {
      return ApiResult.error('Failed to get user: $e');
    }
  }
}
