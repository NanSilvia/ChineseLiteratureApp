import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
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

/// Service for API calls with offline handling.
/// Cards, folders, and auth talk to the FastAPI backend over HTTP.
/// Local SQLite is used as a read cache / offline fallback.
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

  /// Same host as TranslationApiService
  static const String _baseUrl = 'http://192.168.1.155:8000';

  //  helpers

  /// Auth headers using the current user's JWT token.
  Map<String, String> _authHeaders(String? token) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// Get the current token from the locally-stored user session.
  Future<String?> _getToken() async {
    final user = await _db.getUser();
    return user?.token;
  }

  /// Invalidate the in-memory cards list cache.
  void _invalidateCardsCache() {
    _cachedCards = null;
    _cachedCardsFolderId = null;
  }

  /// Invalidate **all** in-memory caches.
  void invalidateAll() {
    _invalidateCardsCache();
    _cachedFolders = null;
    _cardByIdCache.clear();
    _cache.removeByPrefix('analysis');
  }

  /// Parse a card from the backend JSON format to [CardModel].
  CardModel _cardFromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as int?,
      title: json['title'] as String?,
      textZh: json['text_zh'] as String? ?? '',
      folderId: json['folder_id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      source: json['source'] as String? ?? 'manual',
    );
  }

  // ==================== CARDS ====================

  /// Fetch all cards from server.
  /// Returns local SQLite data if offline.
  Future<ApiResult<List<CardModel>>> getCards({int? folderId}) async {
    if (_cachedCards != null && _cachedCardsFolderId == folderId) {
      return ApiResult.success(_cachedCards!);
    }

    if (_connectivity.isOffline) {
      final cached = await _db.loadCards(folderId: folderId);
      _cachedCards = cached;
      _cachedCardsFolderId = folderId;
      return ApiResult.success(cached);
    }

    try {
      final token = await _getToken();
      final uri = Uri.parse('$_baseUrl/cards').replace(
        queryParameters: {
          if (folderId != null) 'folder_id': folderId.toString(),
          'page_size': '200',
        },
      );
      final res = await http.get(uri, headers: _authHeaders(token));

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 200) {
        return ApiResult.error('Server error: ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rawCards = body['cards'] as List<dynamic>;
      final cards = rawCards
          .map((e) => _cardFromJson(e as Map<String, dynamic>))
          .toList();

      // Persist to local SQLite for offline use
      await _db.syncCards(cards);

      _cachedCards = cards;
      _cachedCardsFolderId = folderId;
      for (final card in cards) {
        if (card.id != null) _cardByIdCache[card.id!] = card;
      }

      return ApiResult.success(cards);
    } catch (e) {
      // Fall back to local cache on network error
      final cached = await _db.loadCards(folderId: folderId);
      _cachedCards = cached;
      _cachedCardsFolderId = folderId;
      return ApiResult.success(cached);
    }
  }

  /// Fetch a single card by ID.
  Future<ApiResult<CardModel>> getCardById(int id) async {
    if (_cardByIdCache.containsKey(id)) {
      return ApiResult.success(_cardByIdCache[id]!);
    }

    if (_connectivity.isOffline) {
      final cached = await _db.getCardById(id);
      if (cached != null) {
        _cardByIdCache[id] = cached;
        return ApiResult.success(cached);
      }
      return ApiResult.error('Card not available offline.');
    }

    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/cards/$id'),
        headers: _authHeaders(token),
      );

      if (res.statusCode == 404) return ApiResult.error('Card not found');
      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 200) {
        return ApiResult.error('Server error: ${res.statusCode}');
      }

      final card = _cardFromJson(jsonDecode(res.body) as Map<String, dynamic>);
      _cardByIdCache[id] = card;
      return ApiResult.success(card);
    } catch (e) {
      final cached = await _db.getCardById(id);
      if (cached != null) return ApiResult.success(cached);
      return ApiResult.error('Failed to fetch card: $e');
    }
  }

  /// Create a new card on the server.
  Future<ApiResult<CardModel>> createCard({
    String? title,
    required String textZh,
    int? folderId,
    String source = 'manual',
  }) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/cards'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'title': title,
          'text_zh': textZh,
          'folder_id': folderId,
          'source': source,
        }),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 201) {
        return ApiResult.error('Failed to create card: ${res.statusCode}');
      }

      final card = _cardFromJson(jsonDecode(res.body) as Map<String, dynamic>);

      // Also save locally for offline access
      await _db.saveCard(card);
      _invalidateCardsCache();

      return ApiResult.success(card);
    } catch (e) {
      return ApiResult.error('Failed to create card: $e');
    }
  }

  /// Update an existing card on the server.
  Future<ApiResult<CardModel>> updateCard(CardModel card) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final token = await _getToken();
      final res = await http.put(
        Uri.parse('$_baseUrl/cards/${card.id}'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'title': card.title,
          'text_zh': card.textZh,
          'folder_id': card.folderId,
          'source': card.source,
        }),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 200) {
        return ApiResult.error('Failed to update card: ${res.statusCode}');
      }

      final updated = _cardFromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      await _db.updateCard(updated);
      _invalidateCardsCache();
      if (card.id != null) _cardByIdCache.remove(card.id);
      return ApiResult.success(updated);
    } catch (e) {
      return ApiResult.error('Failed to update card: $e');
    }
  }

  /// Delete a card on the server.
  Future<ApiResult<bool>> deleteCard(int id) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final token = await _getToken();
      final res = await http.delete(
        Uri.parse('$_baseUrl/cards/$id'),
        headers: _authHeaders(token),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 204) {
        return ApiResult.error('Failed to delete card: ${res.statusCode}');
      }

      await _db.deleteCard(id);
      _invalidateCardsCache();
      _cardByIdCache.remove(id);
      return ApiResult.success(true);
    } catch (e) {
      return ApiResult.error('Failed to delete card: $e');
    }
  }

  // ==================== FOLDERS ====================

  /// Fetch all folders from server.
  Future<ApiResult<List<FolderModel>>> getFolders() async {
    if (_cachedFolders != null) return ApiResult.success(_cachedFolders!);

    if (_connectivity.isOffline) {
      final cached = await _db.loadFolders();
      _cachedFolders = cached;
      return ApiResult.success(cached);
    }

    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/folders'),
        headers: _authHeaders(token),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 200) {
        return ApiResult.error('Server error: ${res.statusCode}');
      }

      final raw = jsonDecode(res.body) as List<dynamic>;
      final folders = raw.map((e) {
        final m = e as Map<String, dynamic>;
        return FolderModel(id: m['id'] as int?, name: m['name'] as String);
      }).toList();

      await _db.syncFolders(folders);
      _cachedFolders = folders;
      return ApiResult.success(folders);
    } catch (e) {
      final cached = await _db.loadFolders();
      _cachedFolders = cached;
      return ApiResult.success(cached);
    }
  }

  /// Create a new folder on the server.
  Future<ApiResult<FolderModel>> createFolder(String name) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/folders'),
        headers: _authHeaders(token),
        body: jsonEncode({'name': name}),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 201) {
        return ApiResult.error('Failed to create folder: ${res.statusCode}');
      }

      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final folder = FolderModel(
        id: m['id'] as int?,
        name: m['name'] as String,
      );

      await _db.saveFolder(folder);
      _cachedFolders = null;
      return ApiResult.success(folder);
    } catch (e) {
      return ApiResult.error('Failed to create folder: $e');
    }
  }

  // ==================== ANALYSIS (via backend word/analyze) ====================

  /// Analyze Chinese text using the backend's word analysis endpoint.
  Future<ApiResult<Map<String, dynamic>>> analyzeText(String textZh) async {
    final cacheKey = CacheService.makeKey('analysis', textZh);
    final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/word/analyze'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'word': textZh,
          'language': 'chi',
          'include_synonyms': true,
          'include_antonyms': true,
          'include_alternatives': true,
        }),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Session expired — please log in again');
      }
      if (res.statusCode != 200) {
        return ApiResult.error('Analysis failed: ${res.statusCode}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = ApiResult.success({
        'characters': textZh.length,
        'words': textZh.replaceAll(RegExp(r'\s+'), '').length,
        'analysis': data['explanation'] ?? '',
        'synonyms': data['synonyms'] ?? [],
        'antonyms': data['antonyms'] ?? [],
        'alternatives': data['alternative_wordings'] ?? [],
      });

      _cache.put(cacheKey, result, ttl: CacheService.longTtl);
      return result;
    } catch (e) {
      return ApiResult.error('Failed to analyze text: $e');
    }
  }

  // ==================== AUTHENTICATION ====================

  /// Login — calls POST /auth/login and stores tokens locally.
  Future<ApiResult<UserModel>> login(String username, String password) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (res.statusCode == 401) {
        return ApiResult.error('Invalid username or password');
      }
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return ApiResult.error(body['detail'] as String? ?? 'Login failed');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = body['user'] as Map<String, dynamic>;
      final user = UserModel(
        id: userJson['id'] as int?,
        username: userJson['username'] as String? ?? '',
        email: userJson['email'] as String?,
        token: body['access_token'] as String?,
        refreshToken: body['refresh_token'] as String?,
      );

      await _db.saveUser(user);
      return ApiResult.success(user);
    } catch (e) {
      return ApiResult.error('Failed to login: $e');
    }
  }

  /// Register — calls POST /auth/register and stores tokens locally.
  Future<ApiResult<UserModel>> register(
    String username,
    String email,
    String password,
  ) async {
    if (_connectivity.isOffline) return ApiResult.offline();

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email.isNotEmpty ? email : null,
          'password': password,
        }),
      );

      if (res.statusCode == 409) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return ApiResult.error(body['detail'] as String? ?? 'Already exists');
      }
      if (res.statusCode != 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return ApiResult.error(
          body['detail'] as String? ?? 'Registration failed',
        );
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = body['user'] as Map<String, dynamic>;
      final user = UserModel(
        id: userJson['id'] as int?,
        username: userJson['username'] as String? ?? '',
        email: userJson['email'] as String?,
        token: body['access_token'] as String?,
        refreshToken: body['refresh_token'] as String?,
      );

      await _db.saveUser(user);
      return ApiResult.success(user);
    } catch (e) {
      return ApiResult.error('Failed to register: $e');
    }
  }

  /// Logout — revoke server tokens and clear local session.
  Future<ApiResult<bool>> logout() async {
    try {
      final token = await _getToken();
      if (_connectivity.isOnline && token != null) {
        await http.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: _authHeaders(token),
        );
      }
      await _db.clearUser();
      return ApiResult.success(true);
    } catch (e) {
      // Still clear local even if server call fails
      await _db.clearUser();
      return ApiResult.success(true);
    }
  }

  /// Validate the stored token with the server via GET /auth/me.
  Future<ApiResult<UserModel?>> getCurrentUser() async {
    try {
      final user = await _db.getUser();
      if (user == null) return ApiResult.success(null);

      if (_connectivity.isOnline && user.token != null) {
        final res = await http.get(
          Uri.parse('$_baseUrl/auth/me'),
          headers: _authHeaders(user.token),
        );

        if (res.statusCode == 401) {
          // Token expired — try refresh
          final refreshed = await _tryRefreshToken(user);
          if (refreshed != null) return ApiResult.success(refreshed);
          // Refresh failed — clear session
          await _db.clearUser();
          return ApiResult.success(null);
        }
      }

      return ApiResult.success(user);
    } catch (e) {
      // Offline or network error — return cached user
      final user = await _db.getUser();
      return ApiResult.success(user);
    }
  }

  /// Attempt to refresh the access token using the stored refresh token.
  Future<UserModel?> _tryRefreshToken(UserModel user) async {
    if (user.refreshToken == null) return null;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': user.refreshToken}),
      );
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = body['user'] as Map<String, dynamic>;
      final updated = UserModel(
        id: userJson['id'] as int?,
        username: userJson['username'] as String? ?? '',
        email: userJson['email'] as String?,
        token: body['access_token'] as String?,
        refreshToken: body['refresh_token'] as String?,
      );
      await _db.saveUser(updated);
      return updated;
    } catch (_) {
      return null;
    }
  }
}
