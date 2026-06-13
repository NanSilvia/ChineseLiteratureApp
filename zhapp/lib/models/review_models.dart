import 'package:flutter/foundation.dart';

// Singleton notifier — fires whenever a review session is successfully saved.
// ReviewHistoryPage subscribes to reload its stats automatically.
class ReviewSessionNotifier extends ChangeNotifier {
  static final ReviewSessionNotifier instance = ReviewSessionNotifier._();
  ReviewSessionNotifier._();

  void notifySessionSaved() => notifyListeners();
}

class ReviewSession {
  final int id;
  final int cardId;
  final int score;
  final int totalQuestions;
  final double pct;
  final DateTime completedAt;

  const ReviewSession({
    required this.id,
    required this.cardId,
    required this.score,
    required this.totalQuestions,
    required this.pct,
    required this.completedAt,
  });

  factory ReviewSession.fromMap(Map<String, dynamic> m) => ReviewSession(
        id: m['id'] as int,
        cardId: m['card_id'] as int,
        score: m['score'] as int,
        totalQuestions: m['total_questions'] as int,
        pct: (m['pct'] as num).toDouble(),
        completedAt: DateTime.parse(m['completed_at'] as String),
      );
}

class DailyActivity {
  final String date;
  final int count;
  final double avgPct;

  const DailyActivity({
    required this.date,
    required this.count,
    required this.avgPct,
  });

  factory DailyActivity.fromMap(Map<String, dynamic> m) => DailyActivity(
        date: m['date'] as String,
        count: m['count'] as int,
        avgPct: (m['avg_pct'] as num).toDouble(),
      );
}

class CardReviewSummary {
  final int cardId;
  final String? title;
  final String textPreview;
  final String textZh;
  final int sessionCount;
  final double bestPct;
  final double lastPct;
  final DateTime lastReviewed;

  const CardReviewSummary({
    required this.cardId,
    this.title,
    required this.textPreview,
    required this.textZh,
    required this.sessionCount,
    required this.bestPct,
    required this.lastPct,
    required this.lastReviewed,
  });

  String get displayTitle => (title != null && title!.trim().isNotEmpty)
      ? title!
      : textPreview;

  factory CardReviewSummary.fromMap(Map<String, dynamic> m) => CardReviewSummary(
        cardId: m['card_id'] as int,
        title: m['title'] as String?,
        textPreview: m['text_preview'] as String? ?? '',
        textZh: m['text_zh'] as String? ?? '',
        sessionCount: m['session_count'] as int,
        bestPct: (m['best_pct'] as num).toDouble(),
        lastPct: (m['last_pct'] as num).toDouble(),
        lastReviewed: DateTime.parse(m['last_reviewed'] as String),
      );
}

class ReviewStats {
  final int totalSessions;
  final int totalCardsReviewed;
  final double avgScorePct;
  final int currentStreakDays;
  final List<DailyActivity> sessionsByDate;
  final List<CardReviewSummary> cardsReviewed;

  const ReviewStats({
    required this.totalSessions,
    required this.totalCardsReviewed,
    required this.avgScorePct,
    required this.currentStreakDays,
    required this.sessionsByDate,
    required this.cardsReviewed,
  });

  factory ReviewStats.fromMap(Map<String, dynamic> m) => ReviewStats(
        totalSessions: m['total_sessions'] as int,
        totalCardsReviewed: m['total_cards_reviewed'] as int,
        avgScorePct: (m['avg_score_pct'] as num).toDouble(),
        currentStreakDays: m['current_streak_days'] as int,
        sessionsByDate: (m['sessions_by_date'] as List)
            .map((e) => DailyActivity.fromMap(e as Map<String, dynamic>))
            .toList(),
        cardsReviewed: (m['cards_reviewed'] as List)
            .map((e) => CardReviewSummary.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}
