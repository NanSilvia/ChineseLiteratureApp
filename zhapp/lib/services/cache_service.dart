import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A single cache entry with expiration tracking.
class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry(this.data, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Generic in-memory cache with TTL support.
///
/// Usage:
/// ```dart
/// final cache = CacheService();
/// cache.put('key', myData, ttl: Duration(minutes: 30));
/// final cached = cache.get<MyType>('key');
/// ```
///
/// The cache is a singleton shared across the entire app. Use [namespace]
/// prefixes in keys to separate different domains:
/// ```dart
/// cache.put('translation:$hash', result);
/// cache.put('annotation:$hash', result);
/// cache.put('cards:all', cardsList);
/// ```
class CacheService {
  static final CacheService _instance = CacheService._internal();

  factory CacheService() => _instance;

  CacheService._internal();

  final Map<String, _CacheEntry<dynamic>> _cache = {};

  /// Default TTL for cache entries.
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Short TTL for frequently-changing data (book search, health checks).
  static const Duration shortTtl = Duration(minutes: 5);

  /// Long TTL for rarely-changing data (annotations, translations).
  static const Duration longTtl = Duration(hours: 2);

  /// Permanent TTL — effectively never expires (for MandarinSpot annotations
  /// which are deterministic for the same input).
  static const Duration permanentTtl = Duration(days: 365);

  // ─── Core API ───

  /// Store a value in the cache.
  void put<T>(String key, T data, {Duration ttl = defaultTtl}) {
    _cache[key] = _CacheEntry<T>(data, DateTime.now().add(ttl));
  }

  /// Retrieve a cached value, or `null` if missing/expired.
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T;
  }

  /// Check whether a non-expired entry exists for [key].
  bool has(String key) => get<dynamic>(key) != null;

  /// Remove a single entry.
  void remove(String key) => _cache.remove(key);

  /// Remove all entries whose key starts with [prefix].
  void removeByPrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clear **everything** in the cache.
  void clear() => _cache.clear();

  /// Number of live (non-expired) entries.
  int get size {
    _evictExpired();
    return _cache.length;
  }

  /// Evict all expired entries (housekeeping).
  void _evictExpired() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  // ─── Statistics ───

  /// Returns a snapshot of cache stats for debugging.
  Map<String, dynamic> get stats {
    _evictExpired();
    final namespaces = <String, int>{};
    for (final key in _cache.keys) {
      final ns = key.contains(':') ? key.split(':').first : '_root';
      namespaces[ns] = (namespaces[ns] ?? 0) + 1;
    }
    return {'totalEntries': _cache.length, 'namespaces': namespaces};
  }

  // ─── Key helpers ───

  /// Generate a deterministic cache key by hashing the input parameters.
  /// Accepts any number of parts that are joined and SHA-1 hashed.
  ///
  /// ```dart
  /// final key = CacheService.makeKey('translation', text, schema);
  /// ```
  static String makeKey(
    String namespace, [
    String part1 = '',
    String part2 = '',
    String part3 = '',
    String part4 = '',
    String part5 = '',
  ]) {
    final raw = '$part1|$part2|$part3|$part4|$part5';
    final hash = sha1.convert(utf8.encode(raw)).toString();
    return '$namespace:$hash';
  }
}
