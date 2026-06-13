import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/review_models.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import 'questions_page.dart';

class ReviewHistoryPage extends StatefulWidget {
  const ReviewHistoryPage({super.key});

  @override
  State<ReviewHistoryPage> createState() => _ReviewHistoryPageState();
}

class _ReviewHistoryPageState extends State<ReviewHistoryPage>
    with ConnectivityAware {
  final ApiService _api = ApiService();

  ReviewStats? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ReviewSessionNotifier.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ReviewSessionNotifier.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _api.getReviewStats();
    if (!mounted) return;
    if (result.isOffline) {
      setState(() {
        _isLoading = false;
        _error = 'You are offline. Connect to load your study history.';
      });
      return;
    }
    if (result.error != null) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }
    setState(() {
      _isLoading = false;
      _stats = result.data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: canPop
          ? AppBar(title: const Text('Study Progress'), leading: const BackButton())
          : null,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SizedBox(height: 16),
          _MascotHeader(
            totalSessions: stats.totalSessions,
            streak: stats.currentStreakDays,
          ),
          const SizedBox(height: 20),
          _StatsRow(stats: stats),
          const SizedBox(height: 24),
          if (stats.sessionsByDate.isNotEmpty) ...[
            _SectionLabel(label: 'Last 8 Weeks'),
            const SizedBox(height: 10),
            _ActivityHeatmap(sessionsByDate: stats.sessionsByDate),
            const SizedBox(height: 24),
            _SectionLabel(label: 'Daily Activity (last 14 days)'),
            const SizedBox(height: 10),
            _DailyBarChart(sessionsByDate: stats.sessionsByDate),
            const SizedBox(height: 24),
          ],
          if (stats.cardsReviewed.isNotEmpty) ...[
            _SectionLabel(
              label: 'Cards You\'ve Reviewed',
              subtitle: 'Tap replay to test yourself again',
            ),
            const SizedBox(height: 10),
            ...stats.cardsReviewed.map(
              (c) => _CardReviewTile(summary: c),
            ),
          ] else ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  const Text('🥚', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  Text(
                    'No sessions yet.\nFinish a quiz on any card to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Mascot header ─────────────────────────────────────────────────────────────

class _MascotHeader extends StatelessWidget {
  final int totalSessions;
  final int streak;

  const _MascotHeader({required this.totalSessions, required this.streak});

  static const _levels = [
    (0, '🥚', 'Dormant Egg'),
    (1, '🐣', 'Hatching Scholar'),
    (5, '🐥', 'Fledgling Logographer'),
    (15, '🦅', 'Seasoned Sinophile'),
    (30, '🐉', 'Dragon of the Lexicon'),
    (50, '👑', 'Grand Master of the Hanzi Consortium'),
  ];

  (String, String) get _level {
    (String, String) current = ('🥚', 'Dormant Egg');
    for (final (threshold, emoji, title) in _levels) {
      if (totalSessions >= threshold) current = (emoji, title);
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (emoji, title) = _level;

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 72)),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
        if (streak > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.deepOrange.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(
                  '$streak day streak',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Summary stats row ─────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final ReviewStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Sessions',
          value: '${stats.totalSessions}',
          icon: Icons.quiz_outlined,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Cards',
          value: '${stats.totalCardsReviewed}',
          icon: Icons.library_books_outlined,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Avg Score',
          value: '${(stats.avgScorePct * 100).round()}%',
          icon: Icons.analytics_outlined,
        ),
        const SizedBox(width: 8),
        _StatCard(
          label: 'Streak',
          value: '${stats.currentStreakDays}d',
          icon: Icons.local_fire_department_outlined,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? subtitle;
  const _SectionLabel({required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}

// ── Activity heatmap ──────────────────────────────────────────────────────────

class _ActivityHeatmap extends StatelessWidget {
  final List<DailyActivity> sessionsByDate;
  const _ActivityHeatmap({required this.sessionsByDate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build a map of date → count
    final Map<String, int> countByDate = {
      for (final d in sessionsByDate) d.date: d.count,
    };

    final today = DateTime.now();
    // Generate last 56 days, newest last
    final days = List.generate(56, (i) {
      final d = today.subtract(Duration(days: 55 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });

    final maxCount = countByDate.values.fold(0, (a, b) => a > b ? a : b);

    Color cellColor(int count) {
      if (count == 0) return cs.surfaceContainerHighest;
      if (maxCount == 0) return Colors.green.shade200;
      final intensity = (count / maxCount).clamp(0.15, 1.0);
      return Color.lerp(Colors.green.shade100, Colors.green.shade800, intensity)!;
    }

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: days.map((date) {
        final count = countByDate[date] ?? 0;
        return Tooltip(
          message: count > 0 ? '$date: $count session${count > 1 ? 's' : ''}' : date,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: cellColor(count),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Daily bar chart ───────────────────────────────────────────────────────────

class _DailyBarChart extends StatelessWidget {
  final List<DailyActivity> sessionsByDate;
  const _DailyBarChart({required this.sessionsByDate});

  Color _barColor(double avgPct) {
    if (avgPct >= 0.8) return Colors.green.shade600;
    if (avgPct >= 0.6) return Colors.amber.shade600;
    return Colors.red.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Take last 14 days worth of data
    final today = DateTime.now();
    final last14 = List.generate(14, (i) {
      final d = today.subtract(Duration(days: 13 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });

    final activityMap = {for (final a in sessionsByDate) a.date: a};

    final bars = last14.asMap().entries.map((e) {
      final activity = activityMap[e.value];
      final count = activity?.count.toDouble() ?? 0;
      final avgPct = activity?.avgPct ?? 0.0;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: count,
            color: count > 0 ? _barColor(avgPct) : cs.surfaceContainerHighest,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    final maxY = (activityMap.values.fold(0.0, (a, b) => a > b.count ? a : b.count.toDouble()) + 1).ceilToDouble();

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: bars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, _) => v == v.roundToDouble()
                    ? Text('${v.toInt()}',
                        style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)))
                    : const SizedBox.shrink(),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx % 2 != 0) return const SizedBox.shrink();
                  final date = DateTime.now().subtract(Duration(days: 13 - idx));
                  return Text(
                    '${date.month}/${date.day}',
                    style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.5)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItem: (group, _, rod, __) {
                final date = DateTime.now().subtract(Duration(days: 13 - group.x));
                final label = '${date.month}/${date.day}';
                return BarTooltipItem(
                  '$label\n${rod.toY.toInt()} session${rod.toY.toInt() == 1 ? '' : 's'}',
                  TextStyle(color: cs.onInverseSurface, fontSize: 11),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card review tile ──────────────────────────────────────────────────────────

class _CardReviewTile extends StatelessWidget {
  final CardReviewSummary summary;
  const _CardReviewTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color scoreColor(double pct) {
      if (pct >= 0.8) return Colors.green.shade700;
      if (pct >= 0.6) return Colors.amber.shade700;
      return Colors.red.shade400;
    }

    final lastReviewedStr = _relativeDate(summary.lastReviewed);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Chip(
                        '${summary.sessionCount} session${summary.sessionCount > 1 ? 's' : ''}',
                        cs.secondaryContainer,
                        cs.onSecondaryContainer,
                      ),
                      _Chip(
                        'Best ${(summary.bestPct * 100).round()}%',
                        Colors.green.shade50,
                        Colors.green.shade800,
                      ),
                      _Chip(
                        'Last ${(summary.lastPct * 100).round()}%',
                        scoreColor(summary.lastPct).withValues(alpha: 0.1),
                        scoreColor(summary.lastPct),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastReviewedStr,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionsPage(
                    text: summary.textZh,
                    cardId: summary.cardId,
                    questionCount: 6,
                    difficulty: 'medium',
                    isReplay: true,
                  ),
                ),
              ),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Column(
                children: [
                  Icon(Icons.play_arrow_rounded, size: 22),
                  Text('Replay', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Chip(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

String _relativeDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).round()} weeks ago';
  return '${(diff.inDays / 30).round()} months ago';
}
