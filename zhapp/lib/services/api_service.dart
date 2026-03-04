import 'dart:async';
import '../models/card_model.dart';
import '../models/folder_model.dart';
import '../models/user_model.dart';
import 'db_service.dart';
import 'connectivity_service.dart';
import 'cache_service.dart';

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
  final CacheService _cache = CacheService();

  // In-memory card/folder caches — invalidated on mutations
  List<CardModel>? _cachedCards;
  int? _cachedCardsFolderId;
  List<FolderModel>? _cachedFolders;
  final Map<int, CardModel> _cardByIdCache = {};

  // Base URL for API (configure when backend is ready)
  // ignore: unused_field
  static const String _baseUrl = 'http://localhost:3000/api';

  /// Invalidate the in-memory cards list cache.
  /// Called after any card mutation (create, update, delete).
  void _invalidateCardsCache() {
    _cachedCards = null;
    _cachedCardsFolderId = null;
  }

  /// Invalidate **all** in-memory caches.
  /// Useful on logout, or when CardNotifier fires from external sources.
  void invalidateAll() {
    _invalidateCardsCache();
    _cachedFolders = null;
    _cardByIdCache.clear();
    _cache.removeByPrefix('analysis');
  }

  // ==================== CARDS ====================

  /// Fetch all cards from server
  /// Returns cached data if offline
  Future<ApiResult<List<CardModel>>> getCards({int? folderId}) async {
    // Return in-memory cache if available and same folder filter
    if (_cachedCards != null && _cachedCardsFolderId == folderId) {
      return ApiResult.success(_cachedCards!);
    }

    if (_connectivity.isOffline) {
      // Return cached data when offline
      final cached = await _db.loadCards(folderId: folderId);
      _cachedCards = cached;
      _cachedCardsFolderId = folderId;
      return ApiResult.success(cached);
    }

    try {
      // TODO: Replace with actual API call
      final cards = await _db.loadCards(folderId: folderId);

      // Sort by createdAt descending (most recent first)
      cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Update in-memory cache
      _cachedCards = cards;
      _cachedCardsFolderId = folderId;

      // Also populate the by-ID cache
      for (final card in cards) {
        if (card.id != null) _cardByIdCache[card.id!] = card;
      }

      return ApiResult.success(cards);
    } catch (e) {
      return ApiResult.error('Failed to fetch cards: $e');
    }
  }

  /// Fetch a single card by ID (with in-memory cache)
  Future<ApiResult<CardModel>> getCardById(int id) async {
    // Check in-memory by-ID cache first
    if (_cardByIdCache.containsKey(id)) {
      return ApiResult.success(_cardByIdCache[id]!);
    }

    if (_connectivity.isOffline) {
      final cached = await _db.getCardById(id);
      if (cached != null) {
        _cardByIdCache[id] = cached;
        return ApiResult.success(cached);
      }
      return ApiResult.error('This card is not available offline yet.');
    }

    try {
      // TODO: Replace with actual API call
      final card = await _db.getCardById(id);
      if (card == null) {
        return ApiResult.error('Card not found');
      }

      _cardByIdCache[id] = card;
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

      // Invalidate cards list cache so next getCards() re-fetches
      _invalidateCardsCache();

      return ApiResult.success(savedCard);
    } catch (e) {
      return ApiResult.error('Failed to create card: $e');
    }
  }

  /// Update an existing card (ONLINE ONLY)
  Future<ApiResult<CardModel>> updateCard(CardModel card) async {
    if (_connectivity.isOffline) {
      return ApiResult.offline();
    }

    try {
      // TODO: Replace with actual API call
      final updated = card.copyWith(updatedAt: DateTime.now());
      await _db.updateCard(updated);

      // Invalidate caches
      _invalidateCardsCache();
      if (card.id != null) _cardByIdCache.remove(card.id);

      return ApiResult.success(updated);
    } catch (e) {
      return ApiResult.error('Failed to update card: $e');
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

      // Invalidate caches
      _invalidateCardsCache();
      _cardByIdCache.remove(id);

      return ApiResult.success(true);
    } catch (e) {
      return ApiResult.error('Failed to delete card: $e');
    }
  }

  // ==================== FOLDERS ====================

  /// Fetch all folders/categories (with in-memory cache)
  Future<ApiResult<List<FolderModel>>> getFolders() async {
    if (_cachedFolders != null) {
      return ApiResult.success(_cachedFolders!);
    }

    if (_connectivity.isOffline) {
      final cached = await _db.loadFolders();
      _cachedFolders = cached;
      return ApiResult.success(cached);
    }

    try {
      // TODO: Replace with actual API call
      final folders = await _db.loadFolders();
      _cachedFolders = folders;
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

      // Invalidate folders cache
      _cachedFolders = null;

      return ApiResult.success(folder.copyWith(id: id));
    } catch (e) {
      return ApiResult.error('Failed to create folder: $e');
    }
  }

  // ==================== ANALYSIS (ONLINE ONLY) ====================

  /// Get analysis for a card's Chinese text (ONLINE ONLY, cached)
  Future<ApiResult<Map<String, dynamic>>> analyzeText(String textZh) async {
    final cacheKey = CacheService.makeKey('analysis', textZh);
    final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

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

      final result = ApiResult.success({
        'characters': textZh.length,
        'words': _countChineseWords(textZh),
        'analysis':
            'Analysis placeholder - connect to backend for real analysis',
      });

      _cache.put(cacheKey, result, ttl: CacheService.longTtl);
      return result;
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
