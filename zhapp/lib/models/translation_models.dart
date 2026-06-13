// Models for the Translation Analysis API endpoints (openapi.json)

String _extractXmlTag(String text, String tag) {
  final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(text);
  return match?.group(1)?.trim() ?? '';
}

String _stripXmlTags(String text) {
  return text.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

dynamic _sanitizeTranslationValue(dynamic value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final translatedText = map['translated_text'];
    if (translatedText is String && translatedText.contains('<')) {
      final extracted = _extractXmlTag(translatedText, 'translated_text');
      map['translated_text'] = extracted.isNotEmpty
          ? extracted
          : _stripXmlTags(translatedText);
    }
    return map;
  }

  if (value is String && value.contains('<')) {
    final extracted = _extractXmlTag(value, 'translated_text');
    return extracted.isNotEmpty ? extracted : _stripXmlTags(value);
  }

  return value;
}

//  Translation

class TranslationRequest {
  final String text;
  final String schemaName;

  TranslationRequest({required this.text, this.schemaName = 'translate'});

  Map<String, dynamic> toMap() => {'text': text, 'schema_name': schemaName};
}

class DictionaryEntry {
  final String sourceTerm;
  final String romanized;
  final List<String> suggestions;

  DictionaryEntry({
    required this.sourceTerm,
    required this.romanized,
    required this.suggestions,
  });

  factory DictionaryEntry.fromMap(Map<String, dynamic> map) {
    return DictionaryEntry(
      sourceTerm: map['source_term'] as String? ?? '',
      romanized: map['romanized'] as String? ?? '',
      suggestions: List<String>.from(map['suggestions'] ?? []),
    );
  }
}

class TranslationResponse {
  final String inputText;
  final Map<String, dynamic> translations;
  final List<DictionaryEntry>? dictionaryEntries;

  TranslationResponse({
    required this.inputText,
    required this.translations,
    this.dictionaryEntries,
  });

  factory TranslationResponse.fromMap(Map<String, dynamic> map) {
    final rawTranslations = Map<String, dynamic>.from(
      map['translations'] as Map? ?? {},
    );

    return TranslationResponse(
      inputText: map['input_text'] as String? ?? '',
      translations: rawTranslations.map(
        (key, value) => MapEntry(key, _sanitizeTranslationValue(value)),
      ),
      dictionaryEntries: (map['dictionary_entries'] as List?)
          ?.map((e) => DictionaryEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // Combined translation text from all models
  String get combinedTranslation {
    if (translations.isEmpty) return '';
    final first = translations.values.first;
    if (first is Map<String, dynamic>) {
      return first['translated_text'] as String? ?? '';
    }
    return _sanitizeTranslationValue(first)?.toString() ?? '';
  }
}

//  Summarization

class SummarizationRequest {
  final String text;
  final String language;
  final String length;
  final String style;

  SummarizationRequest({
    required this.text,
    this.language = 'chi',
    this.length = 'medium',
    this.style = 'neutral',
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'language': language,
    'length': length,
    'style': style,
  };
}

class SummarizationResponse {
  final String originalText;
  final String summary;
  final String language;
  final String length;
  final String style;
  final List<String> keyPoints;
  final int wordCountOriginal;
  final int wordCountSummary;

  SummarizationResponse({
    required this.originalText,
    required this.summary,
    required this.language,
    required this.length,
    required this.style,
    required this.keyPoints,
    required this.wordCountOriginal,
    required this.wordCountSummary,
  });

  factory SummarizationResponse.fromMap(Map<String, dynamic> map) {
    return SummarizationResponse(
      originalText: map['original_text'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      language: map['language'] as String? ?? '',
      length: map['length'] as String? ?? '',
      style: map['style'] as String? ?? '',
      keyPoints: List<String>.from(map['key_points'] ?? []),
      wordCountOriginal: map['word_count_original'] as int? ?? 0,
      wordCountSummary: map['word_count_summary'] as int? ?? 0,
    );
  }
}

//  Word Analysis

class WordAnalysisRequest {
  final String word;
  final String? context;
  final String language;
  final bool includeSynonyms;
  final bool includeAntonyms;
  final bool includeAlternatives;

  WordAnalysisRequest({
    required this.word,
    this.context,
    this.language = 'chi',
    this.includeSynonyms = true,
    this.includeAntonyms = true,
    this.includeAlternatives = true,
  });

  Map<String, dynamic> toMap() => {
    'word': word,
    if (context != null) 'context': context,
    'language': language,
    'include_synonyms': includeSynonyms,
    'include_antonyms': includeAntonyms,
    'include_alternatives': includeAlternatives,
  };
}

class WordAnalysisResponse {
  final String word;
  final String? context;
  final String language;
  final List<String> synonyms;
  final List<String> antonyms;
  final List<String> alternativeWordings;
  final List<String> usageExamples;
  final String? explanation;

  WordAnalysisResponse({
    required this.word,
    this.context,
    required this.language,
    required this.synonyms,
    required this.antonyms,
    required this.alternativeWordings,
    required this.usageExamples,
    this.explanation,
  });

  factory WordAnalysisResponse.fromMap(Map<String, dynamic> map) {
    return WordAnalysisResponse(
      word: map['word'] as String? ?? '',
      context: map['context'] as String?,
      language: map['language'] as String? ?? '',
      synonyms: List<String>.from(map['synonyms'] ?? []),
      antonyms: List<String>.from(map['antonyms'] ?? []),
      alternativeWordings: List<String>.from(map['alternative_wordings'] ?? []),
      usageExamples: List<String>.from(map['usage_examples'] ?? []),
      explanation: map['explanation'] as String?,
    );
  }
}

//  Async Jobs

enum JobStatus { pending, processing, completed, failed }

JobStatus jobStatusFromString(String s) {
  switch (s) {
    case 'pending':
      return JobStatus.pending;
    case 'processing':
      return JobStatus.processing;
    case 'completed':
      return JobStatus.completed;
    case 'failed':
      return JobStatus.failed;
    default:
      return JobStatus.pending;
  }
}

class AsyncJobResponse {
  final String jobId;
  final JobStatus status;
  final String message;

  AsyncJobResponse({
    required this.jobId,
    required this.status,
    required this.message,
  });

  factory AsyncJobResponse.fromMap(Map<String, dynamic> map) {
    return AsyncJobResponse(
      jobId: map['job_id'] as String? ?? '',
      status: jobStatusFromString(map['status'] as String? ?? 'pending'),
      message: map['message'] as String? ?? '',
    );
  }
}

class AsyncJobStatusResponse {
  final String jobId;
  final JobStatus status;
  final String? progress;
  final dynamic result;
  final String? error;
  final String? createdAt;
  final String? completedAt;

  AsyncJobStatusResponse({
    required this.jobId,
    required this.status,
    this.progress,
    this.result,
    this.error,
    this.createdAt,
    this.completedAt,
  });

  factory AsyncJobStatusResponse.fromMap(Map<String, dynamic> map) {
    return AsyncJobStatusResponse(
      jobId: map['job_id'] as String? ?? '',
      status: jobStatusFromString(map['status'] as String? ?? 'pending'),
      progress: map['progress'] as String?,
      result: map['result'],
      error: map['error'] as String?,
      createdAt: map['created_at'] as String?,
      completedAt: map['completed_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'job_id': jobId,
    'status': status.name,
    'progress': progress,
    'result': result,
    'error': error,
    'created_at': createdAt,
    'completed_at': completedAt,
  };
}

//  Linguistic Analysis

class LinguisticRequest {
  final String fullText;
  final String selectedText;

  LinguisticRequest({required this.fullText, required this.selectedText});

  Map<String, dynamic> toMap() => {
    'full_text': fullText,
    'selected_text': selectedText,
  };
}

//  Questions Generation

class QuestionsRequest {
  final String text;
  final int questionCount;

  QuestionsRequest({required this.text, this.questionCount = 5});

  Map<String, dynamic> toMap() => {
    'text': text,
    'question_count': questionCount,
  };
}

//  Book Models

class BookSummary {
  final String title;
  final List<String> authors;
  final int? firstPublishYear;
  final String? isbn;
  final List<String> subjects;
  final List<String> publishers;
  final List<String> language;
  final int? numberOfPages;
  final String? openlibraryKey;
  final int? coverId;
  final bool hasFulltext;

  BookSummary({
    required this.title,
    this.authors = const [],
    this.firstPublishYear,
    this.isbn,
    this.subjects = const [],
    this.publishers = const [],
    this.language = const [],
    this.numberOfPages,
    this.openlibraryKey,
    this.coverId,
    this.hasFulltext = false,
  });

  factory BookSummary.fromMap(Map<String, dynamic> map) {
    return BookSummary(
      title: map['title'] as String? ?? 'Unknown Title',
      authors: List<String>.from(map['authors'] ?? []),
      firstPublishYear: map['first_publish_year'] as int?,
      isbn: map['isbn'] as String?,
      subjects: List<String>.from(map['subjects'] ?? []),
      publishers: List<String>.from(map['publishers'] ?? []),
      language: List<String>.from(map['language'] ?? []),
      numberOfPages: map['number_of_pages'] as int?,
      openlibraryKey: map['openlibrary_key'] as String?,
      coverId: map['cover_id'] as int?,
      hasFulltext: map['has_fulltext'] as bool? ?? false,
    );
  }

  String? get coverUrl {
    if (coverId == null) return null;
    return 'https://covers.openlibrary.org/b/id/$coverId-M.jpg';
  }
}

class BookSearchRequest {
  final String query;
  final int limit;
  final String? author;
  final String? subject;
  final String? place;
  final String? person;
  final String? language;

  BookSearchRequest({
    required this.query,
    this.limit = 10,
    this.author,
    this.subject,
    this.place,
    this.person,
    this.language,
  });

  Map<String, dynamic> toMap() => {
    'query': query,
    'limit': limit,
    if (author != null) 'author': author,
    if (subject != null) 'subject': subject,
    if (place != null) 'place': place,
    if (person != null) 'person': person,
    if (language != null) 'language': language,
  };
}

class BookSearchResponse {
  final String query;
  final int numFound;
  final List<BookSummary> results;

  BookSearchResponse({
    required this.query,
    required this.numFound,
    required this.results,
  });

  factory BookSearchResponse.fromMap(Map<String, dynamic> map) {
    return BookSearchResponse(
      query: map['query'] as String? ?? '',
      numFound: map['num_found'] as int? ?? 0,
      results:
          (map['results'] as List?)
              ?.map((e) => BookSummary.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class BookRecommendationRequest {
  final String text;
  final int limit;
  final bool preferDiverseAuthors;

  BookRecommendationRequest({
    required this.text,
    this.limit = 5,
    this.preferDiverseAuthors = true,
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'limit': limit,
    'prefer_diverse_authors': preferDiverseAuthors,
  };
}

class BookRecommendationResponse {
  final int textLength;
  final List<String> keywords;
  final int numFound;
  final List<BookSummary> recommendations;

  BookRecommendationResponse({
    required this.textLength,
    required this.keywords,
    required this.numFound,
    required this.recommendations,
  });

  factory BookRecommendationResponse.fromMap(Map<String, dynamic> map) {
    return BookRecommendationResponse(
      textLength: map['text_length'] as int? ?? 0,
      keywords: List<String>.from(map['keywords'] ?? []),
      numFound: map['num_found'] as int? ?? 0,
      recommendations:
          (map['recommendations'] as List?)
              ?.map((e) => BookSummary.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class TextDifficultyMetrics {
  final int characterCount;
  final int uniqueCharacters;
  final int wordCount;
  final double avgWordLength;
  final double complexityScore;
  final String difficultyLevel;
  final int? hskLevel;
  final String? vocabularyComplexity;
  final String? grammarComplexity;
  final int? estimatedStudyHours;

  TextDifficultyMetrics({
    required this.characterCount,
    required this.uniqueCharacters,
    required this.wordCount,
    required this.avgWordLength,
    required this.complexityScore,
    required this.difficultyLevel,
    this.hskLevel,
    this.vocabularyComplexity,
    this.grammarComplexity,
    this.estimatedStudyHours,
  });

  factory TextDifficultyMetrics.fromMap(Map<String, dynamic> map) {
    return TextDifficultyMetrics(
      characterCount: map['character_count'] as int? ?? 0,
      uniqueCharacters: map['unique_characters'] as int? ?? 0,
      wordCount: map['word_count'] as int? ?? 0,
      avgWordLength: (map['avg_word_length'] as num?)?.toDouble() ?? 0,
      complexityScore: (map['complexity_score'] as num?)?.toDouble() ?? 0,
      difficultyLevel: map['difficulty_level'] as String? ?? 'unknown',
      hskLevel: map['hsk_level'] as int?,
      vocabularyComplexity: map['vocabulary_complexity'] as String?,
      grammarComplexity: map['grammar_complexity'] as String?,
      estimatedStudyHours: map['estimated_study_hours'] as int?,
    );
  }
}

class TextDifficultyRequest {
  final String originalText;
  final String language;
  final int limit;

  TextDifficultyRequest({
    required this.originalText,
    this.language = 'chi',
    this.limit = 5,
  });

  Map<String, dynamic> toMap() => {
    'original_text': originalText,
    'language': language,
    'limit': limit,
  };
}

class SimilarTextResult {
  final String title;
  final List<String> authors;
  final String? textPreview;
  final TextDifficultyMetrics difficultyMetrics;
  final String openlibraryKey;
  final List<String> language;
  final List<String> subjects;

  SimilarTextResult({
    required this.title,
    required this.authors,
    this.textPreview,
    required this.difficultyMetrics,
    required this.openlibraryKey,
    required this.language,
    required this.subjects,
  });

  factory SimilarTextResult.fromMap(Map<String, dynamic> map) {
    return SimilarTextResult(
      title: map['title'] as String? ?? '',
      authors: List<String>.from(map['authors'] ?? []),
      textPreview: map['text_preview'] as String?,
      difficultyMetrics: TextDifficultyMetrics.fromMap(
        map['difficulty_metrics'] as Map<String, dynamic>? ?? {},
      ),
      openlibraryKey: map['openlibrary_key'] as String? ?? '',
      language: List<String>.from(map['language'] ?? []),
      subjects: List<String>.from(map['subjects'] ?? []),
    );
  }
}

class TextDifficultyResponse {
  final String originalText;
  final TextDifficultyMetrics difficultyMetrics;
  final List<SimilarTextResult> similarTexts;
  final int numFound;

  TextDifficultyResponse({
    required this.originalText,
    required this.difficultyMetrics,
    required this.similarTexts,
    required this.numFound,
  });

  factory TextDifficultyResponse.fromMap(Map<String, dynamic> map) {
    return TextDifficultyResponse(
      originalText: map['original_text'] as String? ?? '',
      difficultyMetrics: TextDifficultyMetrics.fromMap(
        map['difficulty_metrics'] as Map<String, dynamic>? ?? {},
      ),
      similarTexts:
          (map['similar_texts'] as List?)
              ?.map((e) => SimilarTextResult.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      numFound: map['num_found'] as int? ?? 0,
    );
  }
}

class TextResearchRequest {
  final String originalText;
  final String? translatedText;
  final int limit;
  final String? language;

  TextResearchRequest({
    required this.originalText,
    this.translatedText,
    this.limit = 5,
    this.language,
  });

  Map<String, dynamic> toMap() => {
    'original_text': originalText,
    if (translatedText != null) 'translated_text': translatedText,
    'limit': limit,
    if (language != null) 'language': language,
  };
}

class TextResearchResponse {
  final String originalText;
  final String translatedText;
  final List<String> keywords;
  final List<BookSummary> bookRecommendations;
  final int numBooksFound;

  TextResearchResponse({
    required this.originalText,
    required this.translatedText,
    required this.keywords,
    required this.bookRecommendations,
    required this.numBooksFound,
  });

  factory TextResearchResponse.fromMap(Map<String, dynamic> map) {
    return TextResearchResponse(
      originalText: map['original_text'] as String? ?? '',
      translatedText: map['translated_text'] as String? ?? '',
      keywords: List<String>.from(map['keywords'] ?? []),
      bookRecommendations:
          (map['book_recommendations'] as List?)
              ?.map((e) => BookSummary.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      numBooksFound: map['num_books_found'] as int? ?? 0,
    );
  }
}

//  Health Check

class HealthCheckResponse {
  final String status;
  final String message;
  final bool? ollamaConnected;
  final List<String>? modelsAvailable;

  HealthCheckResponse({
    required this.status,
    required this.message,
    this.ollamaConnected,
    this.modelsAvailable,
  });

  factory HealthCheckResponse.fromMap(Map<String, dynamic> map) {
    return HealthCheckResponse(
      status: map['status'] as String? ?? '',
      message: map['message'] as String? ?? '',
      ollamaConnected: map['ollama_connected'] as bool?,
      modelsAvailable: (map['models_available'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}
