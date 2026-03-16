import 'dart:async';
import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

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

/// Full-screen page that generates comprehension questions from Chinese text.
class QuestionsPage extends StatefulWidget {
  final String text;

  const QuestionsPage({super.key, required this.text});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();

  AsyncJobStatusResponse? _result;
  bool _isLoading = false;
  String? _error;
  int _questionCount = 5;
  String _streamingText = '';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  // Track user answers (question index → selected option index)
  final Map<int, int> _answers = {};
  bool _showAnswers = false;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    _sseSub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _streamingText = '';
      _answers.clear();
      _showAnswers = false;
    });

    _sseSub = _api
        .questionsStream(
          widget.text,
          questionCount: _questionCount,
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
                  setState(() => _result = status);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprehension Questions'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.psychology,
              color: _thinkingEnabled ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            tooltip: _thinkingEnabled
                ? 'Thinking enabled — tap to disable'
                : 'Thinking disabled — tap to enable',
            onPressed: _toggleThinking,
          ),
          if (_result != null)
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
          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Questions: '),
                Slider(
                  value: _questionCount.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: '$_questionCount',
                  onChanged: (v) => setState(() => _questionCount = v.round()),
                  onChangeEnd: (_) => _load(),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$_questionCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _result != null
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showAnswers = !_showAnswers),
              icon: Icon(
                _showAnswers ? Icons.visibility_off : Icons.visibility,
              ),
              label: Text(_showAnswers ? 'Hide Answers' : 'Show Answers'),
            )
          : null,
    );
  }

  Widget _buildBody() {
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
                  'Generating questions\u2026\nThis may take a moment.',
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

    final data = _result!.result;
    if (data == null) {
      return const Center(child: Text('No data returned.'));
    }

    // Parse questions — backend returns:
    // {questions_list: [{question_prompt, possible_answers: [str,...], correct_answer_index: int}]}
    final questions = _extractQuestions(data);

    if (questions.isEmpty) {
      return const Center(child: Text('No questions generated.'));
    }

    return _buildQuestionsList(questions);
  }

  List<dynamic> _extractQuestions(dynamic data) {
    if (data is Map && data['questions_list'] is List) {
      return data['questions_list'] as List;
    }
    if (data is List) {
      return data;
    }
    if (data is Map && data['questions'] is List) {
      return data['questions'] as List;
    }
    return [];
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

        // Track user selection per question
        final userSelection = _answers[index];

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question header
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

                // Answer options
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
                            : () =>
                                  setState(() => _answers[index] = optionIndex),
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
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade700,
                                  size: 20,
                                ),
                              if (_showAnswers && isSelected && !isCorrect)
                                Icon(
                                  Icons.cancel,
                                  color: Colors.red.shade700,
                                  size: 20,
                                ),
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
