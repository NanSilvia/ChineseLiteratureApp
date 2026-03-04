import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../services/cache_service.dart';
import '../services/db_service.dart';

/// MandarinSpot Annotator - Dart wrapper for Chinese text annotation
///
/// This library provides a simple API to annotate Chinese characters with their
/// pronunciation and definitions, using the MandarinSpot API.
///
/// Usage:
/// ```dart
/// final annotator = MandarinAnnotator();
/// final annotations = await annotator.annotate("你好");
/// for (var ann in annotations) {
///   print('${ann["character"]}: ${ann["pinyin"]}');
/// }
/// ```

class MandarinAnnotator {
  static const int _cjkStart = 0x4E00; // 19968
  static const int _cjkEnd = 0x9FFF; // 40879

  final String apiUrl;
  final Map<String, dynamic> dictionary = {};
  final CacheService _cache = CacheService();
  final DbService _db = DbService();

  MandarinAnnotator({this.apiUrl = "https://api.mandarinspot.com"});

  /// Check if a character is CJK (Chinese, Japanese, Korean)
  bool _isCjkCharacter(String ch) {
    if (ch.isEmpty) return false;
    int charCode = ch.codeUnitAt(0);
    return charCode >= _cjkStart && charCode <= _cjkEnd;
  }

  /// Extract all CJK characters from text
  List<String> extractCjkCharacters(String text) {
    return text.split('').where((ch) => _isCjkCharacter(ch)).toList();
  }

  /// Find all continuous CJK character segments in text
  /// Returns list of [isCjk, startIndex, endIndex]
  List<Map<String, dynamic>> findCjkSegments(String text) {
    List<Map<String, dynamic>> segments = [];
    int i = 0;

    while (i < text.length) {
      bool isCjk = _isCjkCharacter(text[i]);
      int j = i + 1;

      while (j < text.length && _isCjkCharacter(text[j]) == isCjk) {
        j++;
      }

      segments.add({'isCjk': isCjk, 'start': i, 'end': j});
      i = j;
    }

    return segments;
  }

  /// Convert number to base-32 string (like JavaScript Number.toString(32))
  String _toBase32(int num) {
    if (num == 0) return '0';
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    String result = '';
    bool isNegative = num < 0;
    num = num.abs();

    while (num > 0) {
      result = chars[num % 32] + result;
      num ~/= 32;
    }

    return isNegative ? '-$result' : result;
  }

  /// Encode UTF-8 compatible format
  List<String> _encodeUtf8(List<String> arr) {
    List<String> result = [];
    for (String s in arr) {
      String encoded = '';
      for (int i = 0; i < s.length; i++) {
        int charCode = s.codeUnitAt(i);
        encoded += String.fromCharCode(224 | (15 & (charCode >> 12)));
        encoded += String.fromCharCode(128 | (63 & (charCode >> 6)));
        encoded += String.fromCharCode(128 | (63 & charCode));
      }
      result.add(encoded);
    }
    return result;
  }

  /// Generate SHA-1 hash of message
  String _sha1Hash(String msg) {
    return sha1.convert(utf8.encode(msg)).toString();
  }

  /// Make HTTP request
  Future<Map<String, dynamic>> _httpRequest(
    String method,
    String url,
    Map<String, String> params,
  ) async {
    try {
      http.Response response;

      if (method == 'GET') {
        String queryString = params.entries
            .map(
              (e) =>
                  '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
            )
            .join('&');
        String finalUrl = queryString.isNotEmpty ? '$url?$queryString' : url;
        response = await http.get(Uri.parse(finalUrl));
      } else {
        String body = params.entries
            .map(
              (e) =>
                  '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
            )
            .join('&');
        response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        );
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get definitions for CJK characters (with client-side cache)
  Future<Map<String, dynamic>> getDefinitions(
    List<String> characters, {
    String phoneticType = 'pinyin',
  }) async {
    // Build a deterministic cache key from input
    String charStr = characters.join('');
    final cacheKey = CacheService.makeKey('defs', charStr, phoneticType);

    // Return from in-memory cache if available
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    // Send raw characters
    String hashInput = _encodeUtf8(characters).join(',') + phoneticType;
    String cacheHash = _sha1Hash(hashInput);

    // Try server-side cache first
    try {
      String cacheUrl = '$apiUrl/cache/$cacheHash';
      final result = await _httpRequest('GET', cacheUrl, {});
      _cache.put(cacheKey, result, ttl: CacheService.permanentTtl);
      return result;
    } catch (_) {
      // Cache miss, fetch from API
    }

    // Fetch from API
    String defUrl = '$apiUrl/getdefs';
    Map<String, String> params = {'str': charStr, 'phs': phoneticType};
    final result = await _httpRequest('POST', defUrl, params);
    _cache.put(cacheKey, result, ttl: CacheService.permanentTtl);
    return result;
  }

  /// Format character-level annotations
  List<Map<String, dynamic>> _formatAnnotations(
    Map<String, dynamic> defData,
    String text,
    List<String> cjkChars,
  ) {
    List<Map<String, dynamic>> annotations = [];
    Map<String, dynamic> defs = defData['defs'] ?? {};

    for (String char in cjkChars) {
      if (defs.containsKey(char)) {
        var defInfo = defs[char] as List;
        annotations.add({
          'character': char,
          'index': text.indexOf(char),
          'pinyin': defInfo.isNotEmpty ? defInfo[0] : [],
          'simplified': defInfo.length > 1 ? defInfo[1] : [],
          'traditional': defInfo.length > 2 ? defInfo[2] : char,
          'definitions': defInfo.length > 1 ? defInfo[1] : [],
        });
      }
    }

    return annotations;
  }

  /// Create word-level annotations using MandarinSpot's segmentation
  List<Map<String, dynamic>> _createWordAnnotations(
    String text,
    List<String> cjkChars,
    Map<String, dynamic> defData,
  ) {
    List<Map<String, dynamic>> words = [];
    Map<String, dynamic> defs = defData['defs'] ?? {};
    List<dynamic> segData = defData['seg'] ?? [];

    int charIndex = 0;

    for (var segStr in segData) {
      if (segStr == null || (segStr is String && segStr.isEmpty)) continue;

      for (int i = 0; i < (segStr as String).length; i++) {
        String segChar = segStr[i];
        int charWidth;

        try {
          charWidth = int.parse(segChar, radix: 32);
        } catch (_) {
          charWidth = 1;
        }

        // Collect characters for this word
        List<String> wordChars = [];
        for (int j = 0; j < charWidth; j++) {
          if (charIndex < cjkChars.length) {
            wordChars.add(cjkChars[charIndex]);
            charIndex++;
          }
        }

        if (wordChars.isNotEmpty) {
          String wordText = wordChars.join('');

          Map<String, dynamic> wordAnnotation;

          if (defs.containsKey(wordText)) {
            // Multi-character word found in defs
            var defInfo = defs[wordText] as List;
            List<dynamic> pinyin = defInfo.length > 0 ? defInfo[0] : [];
            List<dynamic> definitions = defInfo.length > 1 ? defInfo[1] : [];
            String traditional = defInfo.length > 2 ? defInfo[2] : wordText;

            List<String> pinyinList = pinyin.cast<String>();
            List<String> definitionsList = definitions.cast<String>();

            // Create definitions_full: each definition with its pinyin as prefix
            List<String> definitionsFullList = [];
            String pinyinFirst = pinyinList.isNotEmpty
                ? pinyinList[0]
                : wordText;
            for (String def in definitionsList) {
              definitionsFullList.add('$pinyinFirst/$def');
            }

            String pinyinStr = pinyinList.join(' ');

            wordAnnotation = {
              'word': wordText,
              'pinyin': pinyinStr,
              'pinyin_list': pinyinList,
              'definitions': definitionsList,
              'definitions_full': definitionsFullList,
              'character_count': wordChars.length,
              'characters': wordChars,
              'details': [
                {
                  'character': wordText,
                  'pinyin': pinyin,
                  'definitions': definitions,
                  'traditional': traditional,
                },
              ],
            };
          } else {
            // Fall back to individual character lookup
            List<String> pinyinList = [];
            List<String> definitionsList = [];
            List<String> definitionsFullList = [];
            List<Map<String, dynamic>> charDetails = [];

            for (String char in wordChars) {
              if (defs.containsKey(char)) {
                var defInfo = defs[char] as List;
                List<dynamic> pinyin = defInfo.length > 0 ? defInfo[0] : [];
                List<dynamic> definitions = defInfo.length > 1
                    ? defInfo[1]
                    : [];
                String traditional = defInfo.length > 2 ? defInfo[2] : char;

                String pinyinFirst = pinyin.isNotEmpty
                    ? (pinyin[0] as String)
                    : char;
                pinyinList.add(pinyinFirst);

                if (definitions.isNotEmpty) {
                  List<String> defs_str = definitions.cast<String>();
                  definitionsList.addAll(defs_str);
                  // Add to definitions_full with pinyin prefix for each definition
                  for (String def in defs_str) {
                    definitionsFullList.add('$pinyinFirst/$def');
                  }
                }

                charDetails.add({
                  'character': char,
                  'pinyin': pinyin,
                  'definitions': definitions,
                  'traditional': traditional,
                });
              }
            }

            String pinyinStr = pinyinList.join(' ');

            wordAnnotation = {
              'word': wordText,
              'pinyin': pinyinStr,
              'pinyin_list': pinyinList,
              'definitions': definitionsList,
              'definitions_full': definitionsFullList,
              'character_count': wordChars.length,
              'characters': wordChars,
              'details': charDetails,
            };
          }

          words.add(wordAnnotation);
        }
      }
    }

    return words;
  }

  /// Annotate a single CJK segment independently.
  /// Each segment is sent to the API separately so the segmenter
  /// never creates words that span across non-CJK gaps in the original text.
  Future<List<Map<String, dynamic>>> _annotateSegment(
    List<String> cjkChars,
    String phoneticType,
    bool asWords,
  ) async {
    try {
      Map<String, dynamic> data = await getDefinitions(
        cjkChars,
        phoneticType: phoneticType,
      );

      String segmentText = cjkChars.join('');
      if (asWords) {
        return _createWordAnnotations(segmentText, cjkChars, data);
      } else {
        return _formatAnnotations(data, segmentText, cjkChars);
      }
    } catch (e) {
      // Fallback: return each character as an unannotated word
      return cjkChars
          .map(
            (char) => <String, dynamic>{
              'word': char,
              'pinyin': '',
              'pinyin_list': <String>[],
              'definitions': <String>[],
              'definitions_full': <String>[],
              'character_count': 1,
              'characters': [char],
              'details': <Map<String, dynamic>>[],
            },
          )
          .toList();
    }
  }

  /// Annotate Chinese text (with full-result caching)
  ///
  /// Args:
  ///   text: Chinese text to annotate
  ///   phoneticType: Type of phonetic (pinyin, cantonese, etc)
  ///   asWords: If true, use word-level segmentation; if false, return individual characters
  ///
  /// Returns:
  ///   List of annotations
  Future<List<Map<String, dynamic>>> annotate(
    String text, {
    String phoneticType = 'pinyin',
    bool asWords = true,
  }) async {
    // Check full-annotation cache first (in-memory)
    final cacheKey = CacheService.makeKey(
      'annotate',
      text,
      phoneticType,
      asWords.toString(),
    );
    final cached = _cache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    // Check persistent SQLite cache (survives app restart)
    try {
      final persisted = await _db.getCache(cacheKey);
      if (persisted != null) {
        final restored = (persisted as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cache.put(cacheKey, restored, ttl: CacheService.permanentTtl);
        return restored;
      }
    } catch (_) {
      // SQLite miss or decode error — continue to API
    }

    List<Map<String, dynamic>> segments = findCjkSegments(text);

    // Process each CJK segment independently so the API never creates
    // words that span across non-CJK boundaries (punctuation, spaces, etc.).
    // Without this, all CJK chars get concatenated into one string, the API
    // segments them as continuous prose, and cross-boundary words like "好学"
    // can't be found by indexOf in the original text — causing all subsequent
    // annotations to silently disappear.
    List<Future<List<Map<String, dynamic>>>> futures = [];

    for (var segment in segments) {
      if (segment['isCjk'] != true) continue;

      int start = segment['start'] as int;
      int end = segment['end'] as int;
      String segmentText = text.substring(start, end);
      List<String> segmentChars = segmentText.split('').toList();

      if (segmentChars.isEmpty) continue;

      futures.add(_annotateSegment(segmentChars, phoneticType, asWords));
    }

    if (futures.isEmpty) return [];

    List<List<Map<String, dynamic>>> results = await Future.wait(futures);
    final annotations = results.expand((list) => list).toList();

    // Store in cache — annotations are deterministic, so use permanent TTL
    _cache.put(cacheKey, annotations, ttl: CacheService.permanentTtl);

    // Also persist to SQLite for cross-session caching
    try {
      await _db.putCache(cacheKey, 'annotate', annotations);
    } catch (_) {
      // Non-critical — in-memory cache is still populated
    }

    return annotations;
  }
}
