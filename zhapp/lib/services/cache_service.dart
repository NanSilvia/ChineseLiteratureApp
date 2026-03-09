import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'db_service.dart';

/// A single cache entry with expiration tracking.
class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry(this.data, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Two-tier cache: fast in-memory L1 + persistent SQLite L2.
///
/// L1 (in-memory) stores typed Dart objects for zero-cost lookups within a
/// session. L2 (SQLite `annotation_cache` table) survives app restarts.
///
/// Only JSON-serializable data written via [putJson] is persisted. Typed
/// objects stored via [put] live only in L1.
class CacheService {
  static final CacheService _instance = CacheService._internal();

  factory CacheService() => _instance;

  CacheService._internal();

  final Map<String, _CacheEntry<dynamic>> _cache = {};
  final DbService _db = DbService();

  /// Default TTL for cache entries.
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Short TTL for frequently-changing data (book search, health checks).
  static const Duration shortTtl = Duration(minutes: 5);

  /// Long TTL for rarely-changing data (annotations, translations).
  static const Duration longTtl = Duration(hours: 2);

  /// Permanent TTL — effectively never expires (for MandarinSpot annotations
  /// which are deterministic for the same input).
  static const Duration permanentTtl = Duration(days: 365);

  // ─── L1 (in-memory) Core API ───

  /// Store a value in the in-memory cache only.
  void put<T>(String key, T data, {Duration ttl = defaultTtl}) {
    _cache[key] = _CacheEntry<T>(data, DateTime.now().add(ttl));
  }

  /// Retrieve a value from the in-memory cache.
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T;
  }

  // ─── L2 (SQLite) persistent JSON cache ───

  /// Store raw JSON in both L1 and SQLite.
  /// [namespace] is extracted from the first segment of [key] (before ':').
  Future<void> putJson(
    String key,
    Map<String, dynamic> json, {
    Duration ttl = defaultTtl,
  }) async {
    final expiresAt = DateTime.now().add(ttl);
    // L1
    _cache[key] = _CacheEntry<Map<String, dynamic>>(json, expiresAt);
    // L2 — fire-and-forget write to SQLite
    final namespace = key.contains(':') ? key.split(':').first : '_root';
    _db.putCache(key, namespace, json, expiresAt: expiresAt);
  }

  /// Retrieve raw JSON: check L1 first, then fall back to SQLite.
  Future<Map<String, dynamic>?> getJson(String key) async {
    // L1 check
    final entry = _cache[key];
    if (entry != null) {
      if (entry.isExpired) {
        _cache.remove(key);
      } else {
        return entry.data as Map<String, dynamic>;
      }
    }
    // L2 fallback
    final dbData = await _db.getCache(key);
    if (dbData == null) return null;
    final json = dbData as Map<String, dynamic>;
    // Promote back to L1
    _cache[key] = _CacheEntry<Map<String, dynamic>>(
      json,
      DateTime.now().add(longTtl),
    );
    return json;
  }

  /// Check whether a non-expired entry exists for [key].
  bool has(String key) => get<dynamic>(key) != null;

  /// Remove a single entry from both L1 and L2.
  void remove(String key) {
    _cache.remove(key);
    _db.clearCacheByKey(key);
  }

  /// Remove all entries whose key starts with [prefix] from L1.
  void removeByPrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clear **everything** from both L1 and L2.
  void clear() {
    _cache.clear();
    _db.clearAllCache();
  }

  /// Number of live (non-expired) entries in L1.
  int get size {
    _evictExpired();
    return _cache.length;
  }

  /// Evict all expired entries (housekeeping).
  void _evictExpired() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  // ─── Statistics ───

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
