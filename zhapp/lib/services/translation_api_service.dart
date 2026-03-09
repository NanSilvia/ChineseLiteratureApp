import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/translation_models.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'cache_service.dart';

/// Service for calling the Translation Analysis API endpoints.
///
/// All methods return [ApiResult] following the project convention.
/// Async endpoints are polled automatically until completion.
class TranslationApiService {
  static final TranslationApiService _instance =
      TranslationApiService._internal();

  factory TranslationApiService() => _instance;

  TranslationApiService._internal();

  final ConnectivityService _connectivity = ConnectivityService();
  final CacheService _cache = CacheService();

  // Base URL for the Translation Analysis API
  static const String _baseUrl = 'http://192.168.1.155:8000';

  // ─── helpers ───

  Map<String, String> get _headers {
    final token = AuthService().currentUser?.token;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Check a response for auth / rate-limit errors and return an
  /// appropriate [ApiResult] if one applies, otherwise `null`.
  ApiResult<T>? _checkResponse<T>(http.Response res) {
    if (res.statusCode == 401) {
      return ApiResult.error('Session expired — please log in again');
    }
    if (res.statusCode == 429) {
      return ApiResult.error('Rate limit exceeded — please wait and retry');
    }
    return null;
  }

  /// Poll an async job until it completes or fails.
  Future<ApiResult<AsyncJobStatusResponse>> _pollJob(
    String statusPath,
    String jobId, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final uri = Uri.parse('$_baseUrl$statusPath/$jobId');
        final response = await http.get(uri, headers: _headers);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final status = AsyncJobStatusResponse.fromMap(data);

          if (status.status == JobStatus.completed ||
              status.status == JobStatus.failed) {
            return ApiResult.success(status);
          }
        }

        await Future.delayed(interval);
      } catch (e) {
        return ApiResult.error('Polling failed: $e');
      }
    }

    return ApiResult.error('Job timed out');
  }

  //
  // HEALTH
  //

  Future<ApiResult<HealthCheckResponse>> healthCheck() async {
    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return ApiResult.success(
          HealthCheckResponse.fromMap(jsonDecode(res.body)),
        );
      }
      return ApiResult.error('Health check failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Health check error: $e');
    }
  }

  //
  // TRANSLATION (sync)
  //

  Future<ApiResult<TranslationResponse>> translate(
    String text, {
    String schemaName = 'translate',
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('translate', text, schemaName);
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<TranslationResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          TranslationResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/translate'),
        headers: _headers,
        body: jsonEncode({'text': text, 'schema_name': schemaName}),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(TranslationResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.longTtl);
        return result;
      }
      return ApiResult.error('Translation failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Translation error: $e');
    }
  }

  //
  // TRANSLATION (async with polling)
  //

  Future<ApiResult<AsyncJobStatusResponse>> translateAsync(
    String text, {
    String schemaName = 'translate',
  }) async {
    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/translate/async'),
        headers: _headers,
        body: jsonEncode({'text': text, 'schema_name': schemaName}),
      );
      if (res.statusCode == 200) {
        final job = AsyncJobResponse.fromMap(jsonDecode(res.body));
        return _pollJob('/translate/status', job.jobId);
      }
      return ApiResult.error('Async translate failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Async translate error: $e');
    }
  }

  //
  // BATCH TRANSLATION
  //

  Future<ApiResult<List<dynamic>>> batchTranslate(
    List<String> texts, {
    String schemaName = 'translate',
  }) async {
    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final uri = Uri.parse(
        '$_baseUrl/batch/translate',
      ).replace(queryParameters: {'schema_name': schemaName});
      final res = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(texts),
      );
      if (res.statusCode == 200) {
        return ApiResult.success(jsonDecode(res.body) as List<dynamic>);
      }
      return ApiResult.error('Batch translate failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Batch translate error: $e');
    }
  }

  //
  // SUMMARIZATION
  //

  Future<ApiResult<SummarizationResponse>> summarize(
    String text, {
    String language = 'chi',
    String length = 'medium',
    String style = 'neutral',
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey(
      'summarize',
      text,
      language,
      length,
      style,
    );
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<SummarizationResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          SummarizationResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/text/summarize'),
        headers: _headers,
        body: jsonEncode({
          'text': text,
          'language': language,
          'length': length,
          'style': style,
        }),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(SummarizationResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.longTtl);
        return result;
      }
      return ApiResult.error('Summarization failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Summarization error: $e');
    }
  }

  //
  // WORD ANALYSIS
  //

  Future<ApiResult<WordAnalysisResponse>> analyzeWord(
    String word, {
    String language = 'chi',
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('wordAnalysis', word, language);
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<WordAnalysisResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          WordAnalysisResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/word/analyze'),
        headers: _headers,
        body: jsonEncode({
          'word': word,
          'language': language,
          'include_synonyms': true,
          'include_antonyms': true,
          'include_alternatives': true,
        }),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(WordAnalysisResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.longTtl);
        return result;
      }
      return ApiResult.error('Word analysis failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Word analysis error: $e');
    }
  }

  //
  // LINGUISTIC ANALYSIS (async with polling)
  //

  Future<ApiResult<AsyncJobStatusResponse>> analyzeLinguistic(
    String fullText,
    String selectedText, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('linguistic', fullText, selectedText);
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<AsyncJobStatusResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          AsyncJobStatusResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/linguistic/async'),
        headers: _headers,
        body: jsonEncode({
          'full_text': fullText,
          'selected_text': selectedText,
        }),
      );
      if (res.statusCode == 200) {
        final job = AsyncJobResponse.fromMap(jsonDecode(res.body));
        final result = await _pollJob('/linguistic/status', job.jobId);
        if (result.isSuccess && result.data != null) {
          _cache.put(cacheKey, result, ttl: CacheService.longTtl);
          _cache.putJson(
            cacheKey,
            result.data!.toMap(),
            ttl: CacheService.longTtl,
          );
        }
        return result;
      }
      return ApiResult.error('Linguistic analysis failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Linguistic analysis error: $e');
    }
  }

  //
  // QUESTIONS GENERATION (async with polling)
  //

  Future<ApiResult<AsyncJobStatusResponse>> generateQuestions(
    String text, {
    int questionCount = 5,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('questions', text, '$questionCount');
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<AsyncJobStatusResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          AsyncJobStatusResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/questions/async'),
        headers: _headers,
        body: jsonEncode({'text': text, 'question_count': questionCount}),
      );
      if (res.statusCode == 200) {
        final job = AsyncJobResponse.fromMap(jsonDecode(res.body));
        final result = await _pollJob('/questions/status', job.jobId);
        if (result.isSuccess && result.data != null) {
          _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
          _cache.putJson(
            cacheKey,
            result.data!.toMap(),
            ttl: CacheService.defaultTtl,
          );
        }
        return result;
      }
      return ApiResult.error('Question generation failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Question generation error: $e');
    }
  }

  //
  // BOOKS — Search
  //

  Future<ApiResult<BookSearchResponse>> searchBooks(
    String query, {
    int limit = 10,
    String? author,
    String? subject,
    String? language,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey(
      'bookSearch',
      query,
      '$limit',
      author ?? '',
      '${subject ?? ''}|${language ?? ''}',
    );
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<BookSearchResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(BookSearchResponse.fromMap(persisted));
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/books/search'),
        headers: _headers,
        body: jsonEncode({
          'query': query,
          'limit': limit,
          if (author != null) 'author': author,
          if (subject != null) 'subject': subject,
          if (language != null) 'language': language,
        }),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(BookSearchResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.shortTtl);
        return result;
      }
      return ApiResult.error('Book search failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Book search error: $e');
    }
  }

  //
  // BOOKS — Recommend
  //

  Future<ApiResult<BookRecommendationResponse>> recommendBooks(
    String text, {
    int limit = 5,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('bookRecommend', text, '$limit');
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<BookRecommendationResponse>>(
        cacheKey,
      );
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          BookRecommendationResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/books/recommend'),
        headers: _headers,
        body: jsonEncode({'text': text, 'limit': limit}),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(
          BookRecommendationResponse.fromMap(json),
        );
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.defaultTtl);
        return result;
      }
      return ApiResult.error('Book recommend failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Book recommend error: $e');
    }
  }

  //
  // BOOKS — Similar Difficulty
  //

  Future<ApiResult<TextDifficultyResponse>> findSimilarDifficulty(
    String text, {
    String language = 'chi',
    int limit = 5,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey(
      'difficulty',
      text,
      language,
      '$limit',
    );
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<TextDifficultyResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          TextDifficultyResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/books/similar-difficulty'),
        headers: _headers,
        body: jsonEncode({
          'original_text': text,
          'language': language,
          'limit': limit,
        }),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(TextDifficultyResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.defaultTtl);
        return result;
      }
      return ApiResult.error('Similar difficulty failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Similar difficulty error: $e');
    }
  }

  //
  // BOOKS — Research (translate + recommend)
  //

  Future<ApiResult<TextResearchResponse>> researchText(
    String text, {
    int limit = 5,
    String? language,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey(
      'research',
      text,
      '$limit',
      language ?? '',
    );
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<TextResearchResponse>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(
          TextResearchResponse.fromMap(persisted),
        );
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/books/research'),
        headers: _headers,
        body: jsonEncode({
          'original_text': text,
          'limit': limit,
          if (language != null) 'language': language,
        }),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(TextResearchResponse.fromMap(json));
        _cache.put(cacheKey, result, ttl: CacheService.defaultTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.defaultTtl);
        return result;
      }
      return ApiResult.error('Research failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Research error: $e');
    }
  }

  //
  // BOOKS — By Subject
  //

  Future<ApiResult<Map<String, dynamic>>> getBooksBySubject(
    String subject, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('booksBySubject', subject, '$limit');
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(persisted);
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final uri = Uri.parse(
        '$_baseUrl/books/subject/${Uri.encodeComponent(subject)}',
      ).replace(queryParameters: {'limit': '$limit'});
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(json);
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.shortTtl);
        return result;
      }
      return ApiResult.error('Books by subject failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Books by subject error: $e');
    }
  }

  //
  // BOOKS — By Author
  //

  Future<ApiResult<Map<String, dynamic>>> getBooksByAuthor(
    String author, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('booksByAuthor', author, '$limit');
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(persisted);
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final uri = Uri.parse(
        '$_baseUrl/books/author/${Uri.encodeComponent(author)}',
      ).replace(queryParameters: {'limit': '$limit'});
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(json);
        _cache.put(cacheKey, result, ttl: CacheService.shortTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.shortTtl);
        return result;
      }
      return ApiResult.error('Books by author failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Books by author error: $e');
    }
  }

  //
  // BOOKS — Work Details
  //

  Future<ApiResult<Map<String, dynamic>>> getWorkDetails(
    String workId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('workDetails', workId);
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(persisted);
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/books/work/${Uri.encodeComponent(workId)}'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(json);
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.longTtl);
        return result;
      }
      return ApiResult.error('Work details failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Work details error: $e');
    }
  }

  //
  // BOOKS — Author Info
  //

  Future<ApiResult<Map<String, dynamic>>> getAuthorInfo(
    String authorId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = CacheService.makeKey('authorInfo', authorId);
    if (!forceRefresh) {
      final cached = _cache.get<ApiResult<Map<String, dynamic>>>(cacheKey);
      if (cached != null) return cached;
      final persisted = await _cache.getJson(cacheKey);
      if (persisted != null) {
        final result = ApiResult.success(persisted);
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        return result;
      }
    }

    if (_connectivity.isOffline) return ApiResult.offline();
    try {
      final res = await http.get(
        Uri.parse(
          '$_baseUrl/books/author-info/${Uri.encodeComponent(authorId)}',
        ),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final result = ApiResult.success(json);
        _cache.put(cacheKey, result, ttl: CacheService.longTtl);
        _cache.putJson(cacheKey, json, ttl: CacheService.longTtl);
        return result;
      }
      return ApiResult.error('Author info failed: ${res.statusCode}');
    } catch (e) {
      return ApiResult.error('Author info error: $e');
    }
  }
}
