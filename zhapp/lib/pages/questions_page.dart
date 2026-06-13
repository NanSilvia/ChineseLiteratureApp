import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/api_service.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';
import 'review_history_page.dart';

String? _xmlPartial(String buf, String tag) {
  final open = buf.indexOf('<$tag>');
  if (open == -1) return null;
  final start = open + tag.length + 2;
  final close = buf.indexOf('</$tag>', start);
  return close == -1 ? buf.substring(start) : buf.substring(start, close);
}

List<Map<String, dynamic>> _streamingQuestions(String buf) {
  final questionsBlock = _xmlPartial(buf, 'questions') ?? buf;
  final matches = RegExp(
    r'<question>(.*?)</question>',
    dotAll: true,
  ).allMatches(questionsBlock);

  return matches.map((match) {
    final inner = match.group(1) ?? '';
    final prompt = (_xmlPartial(inner, 'prompt') ?? '').trim();
    final options = RegExp(
      r'<option>(.*?)</option>',
      dotAll: true,
    ).allMatches(inner).map((m) => (m.group(1) ?? '').trim()).toList();
    final answerText = (_xmlPartial(inner, 'answer') ?? '0').trim();
    final answerIndex = int.tryParse(answerText) ?? 0;
    return {
      'question_prompt': prompt,
      'possible_answers': options,
      'correct_answer_index': answerIndex,
    };
  }).toList();
}

// Full-screen page that generates comprehension questions from Chinese text.
class QuestionsPage extends StatefulWidget {
  final String text;
  final int? cardId;
  final bool isReplay;
  final int questionCount;
  final String difficulty;

  const QuestionsPage({
    super.key,
    required this.text,
    this.cardId,
    this.isReplay = false,
    required this.questionCount,
    this.difficulty = 'medium',
  });

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();
  final ApiService _apiService = ApiService();
  late final ConfettiController _confettiCtrl;

  AsyncJobStatusResponse? _result;
  List<Map<String, dynamic>>? _shuffledQuestions;
  bool _isLoading = false;
  String? _error;
  String _streamingText = '';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  // Track user answers (question index → selected option index)
  final Map<int, int> _answers = {};
  bool _showAnswers = false;

  // Celebration state
  bool _showCelebration = false;
  bool _sessionSaved = false;
  int _lastScore = 0;
  int _lastTotal = 0;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 4));
    _thinkingEnabled = _api.thinkingEnabled;
    _load();
  }

  void _toggleThinking() {
    final next = !_thinkingEnabled;
    _api.thinkingEnabled = next;
    setState(() => _thinkingEnabled = next);
    _load(forceRefresh: true);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _confettiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    _sseSub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _shuffledQuestions = null;
      _streamingText = '';
      _answers.clear();
      _showAnswers = false;
      _showCelebration = false;
      _sessionSaved = false;
    });

    _sseSub = _api
        .questionsStream(
          widget.text,
          questionCount: widget.questionCount,
          difficulty: widget.difficulty,
          forceRefresh: forceRefresh,
          enableThinking: _thinkingEnabled,
        )
        .listen(
          (ev) {
            if (!mounted) return;
            if (ev.type == 'token') {
              setState(() => _streamingText += ev.data['t'] as String? ?? '');
            } else if (ev.type == 'result') {
              try {
                final status = AsyncJobStatusResponse.fromMap(ev.data);
                if (status.status == JobStatus.failed) {
                  setState(() {
                    _isLoading = false;
                    _error = status.error ?? 'Question generation failed';
                  });
                } else {
                  final rawQ = _extractQuestions(status.result);
                  setState(() {
                    _result = status;
                    _shuffledQuestions = _applyShuffling(rawQ);
                  });
                }
              } catch (_) {}
            } else if (ev.type == 'done') {
              setState(() => _isLoading = false);
            } else if (ev.type == 'error') {
              setState(() {
                _isLoading = false;
                _error = ev.data['message'] as String? ?? 'Streaming error';
              });
            }
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = e.toString();
              });
            }
          },
          onDone: () {
            if (mounted) setState(() => _isLoading = false);
          },
        );
  }

  List<dynamic> _extractQuestions(dynamic data) {
    if (data is Map && data['questions_list'] is List) {
      return data['questions_list'] as List;
    }
    if (data is List) return data;
    if (data is Map && data['questions'] is List) {
      return data['questions'] as List;
    }
    return [];
  }

  List<Map<String, dynamic>> _applyShuffling(List<dynamic> raw) {
    final processed = raw.map((item) {
      if (item is! Map) return <String, dynamic>{};
      final q = Map<String, dynamic>.from(item);
      final options =
          (q['possible_answers'] as List?)?.map((e) => e.toString()).toList() ??
          [];
      final correctIdx = (q['correct_answer_index'] as int?) ?? 0;
      if (options.isEmpty) return q;

      final indices = List<int>.generate(options.length, (i) => i)..shuffle();
      return {
        ...q,
        'possible_answers': indices.map((i) => options[i]).toList(),
        'correct_answer_index': indices.indexOf(correctIdx),
      };
    }).toList();
    processed.shuffle();
    return processed;
  }

  List<dynamic> get _currentQuestions => _shuffledQuestions ?? [];

  void _revealAnswers() {
    final questions = _currentQuestions;
    if (questions.isEmpty) return;

    final correct = _answers.entries
        .where((e) {
          final q = questions[e.key];
          if (q is! Map) return false;
          return e.value == (q['correct_answer_index'] as int?);
        })
        .length;
    final total = questions.length;

    if (widget.cardId != null && !_sessionSaved) {
      _sessionSaved = true;
      _apiService.saveReviewSession(widget.cardId!, correct, total);
    }

    setState(() {
      _showAnswers = true;
      _showCelebration = true;
      _lastScore = correct;
      _lastTotal = total;
    });
    _confettiCtrl.play();
  }

  String _congratsMessage(double pct) {
    if (pct == 1.0) return '完美！ PERFECT SCORE! 🎊';
    if (pct >= 0.8) return '优秀！ Excellent! 🌟';
    if (pct >= 0.6) return '不错！ Good effort! 💪';
    return '继续努力！ Keep grinding! 🏋️';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReplay ? 'Replay' : 'Comprehension Questions'),
        actions: [
          if (!widget.isReplay)
            IconButton(
              icon: Icon(
                Icons.psychology,
                color: _thinkingEnabled
                    ? null
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              tooltip: _thinkingEnabled
                  ? 'Thinking enabled — tap to disable'
                  : 'Thinking disabled — tap to enable',
              onPressed: _toggleThinking,
            ),
          if (!widget.isReplay && _result != null && !_showCelebration)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Regenerate (bypass cache)',
              onPressed: () => _load(forceRefresh: true),
            ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (!_showCelebration) const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: (_result != null && !_showAnswers && !_showCelebration)
          ? FloatingActionButton.extended(
              onPressed: _revealAnswers,
              icon: const Icon(Icons.visibility),
              label: const Text('Show Answers'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_showCelebration) return _buildCelebration();

    if (_isLoading) {
      final questions = _streamingQuestions(_streamingText);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          if (questions.isNotEmpty)
            Expanded(child: _buildQuestionsList(questions))
          else
            const Expanded(
              child: Center(
                child: Text(
                  'Generating questions…\nThis may take a moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
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

    if (_result == null) {
      return const Center(child: Text('No questions generated yet.'));
    }

    final questions = _currentQuestions;
    if (questions.isEmpty) {
      return const Center(child: Text('No questions generated.'));
    }

    return _buildQuestionsList(questions);
  }

  Widget _buildCelebration() {
    final cs = Theme.of(context).colorScheme;
    final pct = _lastTotal > 0 ? _lastScore / _lastTotal : 0.0;
    final fullStars = (pct * 5).round();

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        ConfettiWidget(
          confettiController: _confettiCtrl,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 40,
          gravity: 0.2,
          colors: [
            cs.primary,
            cs.secondary,
            cs.tertiary,
            Colors.amber,
            Colors.pink,
          ],
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_lastScore / $_lastTotal',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => Icon(
                    i < fullStars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 36,
                  )),
                ),
                const SizedBox(height: 20),
                Text(
                  _congratsMessage(pct),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: () => setState(() => _showCelebration = false),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Review answers'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(220, 48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReviewHistoryPage(),
                    ),
                  ),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('View Study History'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(220, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionsList(List<dynamic> questions) {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final q = questions[index];
        if (q is! Map) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(q.toString()),
            ),
          );
        }

        final qMap = Map<String, dynamic>.from(q);
        final questionText =
            qMap['question_prompt'] as String? ??
            qMap['question'] as String? ??
            'Question ${index + 1}';
        final possibleAnswers =
            (qMap['possible_answers'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            (qMap['options'] as List?)?.map((e) => e.toString()).toList() ??
            [];
        final correctIndex = qMap['correct_answer_index'] as int?;
        final userSelection = _answers[index];

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: cs.primary,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        questionText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (possibleAnswers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...possibleAnswers.asMap().entries.map((entry) {
                    final optionIndex = entry.key;
                    final optionText = entry.value;
                    final isCorrect = correctIndex == optionIndex;
                    final isSelected = userSelection == optionIndex;

                    Color? bgColor;
                    Color? borderColor;
                    if (_showAnswers) {
                      if (isCorrect) {
                        bgColor = Colors.green.shade50;
                        borderColor = Colors.green.shade300;
                      } else if (isSelected && !isCorrect) {
                        bgColor = Colors.red.shade50;
                        borderColor = Colors.red.shade300;
                      }
                    } else if (isSelected) {
                      bgColor = cs.primaryContainer.withValues(alpha: 0.4);
                      borderColor = cs.primary.withValues(alpha: 0.5);
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _showAnswers
                            ? null
                            : () => setState(() => _answers[index] = optionIndex),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor ?? Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: borderColor ?? Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: isSelected
                                    ? cs.primary
                                    : Colors.grey.shade300,
                                child: Text(
                                  String.fromCharCode(65 + optionIndex),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? cs.onPrimary
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  optionText,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              if (_showAnswers && isCorrect)
                                Icon(Icons.check_circle,
                                    color: Colors.green.shade700, size: 20),
                              if (_showAnswers && isSelected && !isCorrect)
                                Icon(Icons.cancel,
                                    color: Colors.red.shade700, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

