import 'package:flutter/material.dart';
import 'questions_page.dart';

enum _QuizMode { easy, medium, hard, custom }

class QuestionSetupPage extends StatefulWidget {
  final String text;
  final int? cardId;
  final bool isReplay;

  const QuestionSetupPage({
    super.key,
    required this.text,
    this.cardId,
    this.isReplay = false,
  });

  @override
  State<QuestionSetupPage> createState() => _QuestionSetupPageState();
}

class _QuestionSetupPageState extends State<QuestionSetupPage> {
  _QuizMode _mode = _QuizMode.medium;
  int _customCount = 5;
  String _customDifficulty = 'medium';

  int get _resolvedCount => switch (_mode) {
        _QuizMode.easy => 3,
        _QuizMode.medium => 6,
        _QuizMode.hard => 12,
        _QuizMode.custom => _customCount,
      };

  String get _resolvedDifficulty => switch (_mode) {
        _QuizMode.easy => 'easy',
        _QuizMode.medium => 'medium',
        _QuizMode.hard => 'hard',
        _QuizMode.custom => _customDifficulty,
      };

  void _start() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionsPage(
          text: widget.text,
          cardId: widget.cardId,
          questionCount: _resolvedCount,
          difficulty: _resolvedDifficulty,
          isReplay: widget.isReplay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Questions')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TextPreviewCard(text: widget.text),
                const SizedBox(height: 20),
                const Text(
                  'Choose your session',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _ModeCard(
                  emoji: '🌱',
                  title: 'Easy',
                  subtitle: '3 questions · Straightforward topics',
                  selected: _mode == _QuizMode.easy,
                  onTap: () => setState(() => _mode = _QuizMode.easy),
                ),
                const SizedBox(height: 8),
                _ModeCard(
                  emoji: '📖',
                  title: 'Medium',
                  subtitle: '6 questions · Balanced challenge',
                  selected: _mode == _QuizMode.medium,
                  onTap: () => setState(() => _mode = _QuizMode.medium),
                ),
                const SizedBox(height: 8),
                _ModeCard(
                  emoji: '🔥',
                  title: 'Hard',
                  subtitle: '12 questions · Advanced, inference-heavy',
                  selected: _mode == _QuizMode.hard,
                  onTap: () => setState(() => _mode = _QuizMode.hard),
                ),
                const SizedBox(height: 8),
                _ModeCard(
                  emoji: '✏️',
                  title: 'Custom',
                  subtitle: 'You choose the count & difficulty',
                  selected: _mode == _QuizMode.custom,
                  onTap: () => setState(() => _mode = _QuizMode.custom),
                  expansion: _mode == _QuizMode.custom
                      ? _CustomControls(
                          count: _customCount,
                          difficulty: _customDifficulty,
                          onCountChanged: (v) =>
                              setState(() => _customCount = v),
                          onDifficultyChanged: (v) =>
                              setState(() => _customDifficulty = v),
                        )
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewCard extends StatelessWidget {
  final String text;

  const _TextPreviewCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = text.length > 120 ? '${text.substring(0, 120)}…' : text;

    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Text preview',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preview,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? expansion;

  const _ModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.expansion,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 2 : 1,
        ),
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.surface,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: selected ? cs.primary : cs.onSurface,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: cs.primary),
                ],
              ),
              if (expansion != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                expansion!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomControls extends StatelessWidget {
  final int count;
  final String difficulty;
  final ValueChanged<int> onCountChanged;
  final ValueChanged<String> onDifficultyChanged;

  const _CustomControls({
    required this.count,
    required this.difficulty,
    required this.onCountChanged,
    required this.onDifficultyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Questions',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            IconButton.outlined(
              onPressed: count > 3 ? () => onCountChanged(count - 1) : null,
              icon: const Icon(Icons.remove),
              iconSize: 18,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton.outlined(
              onPressed: count < 20 ? () => onCountChanged(count + 1) : null,
              icon: const Icon(Icons.add),
              iconSize: 18,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              'Difficulty',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            for (final d in ['easy', 'medium', 'hard'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(
                    '${d[0].toUpperCase()}${d.substring(1)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: difficulty == d,
                  onSelected: (_) => onDifficultyChanged(d),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
