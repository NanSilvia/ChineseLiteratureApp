import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

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

  // Track user answers (question index → selected option index)
  final Map<int, int> _answers = {};
  bool _showAnswers = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _answers.clear();
      _showAnswers = false;
    });

    final result = await _api.generateQuestions(
      widget.text,
      questionCount: _questionCount,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
          if (_result!.status == JobStatus.failed) {
            _error = _result!.error ?? 'Question generation failed';
            _result = null;
          }
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprehension Questions'),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Regenerate',
              onPressed: _load,
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Generating questions…\nThis may take a moment.'),
          ],
        ),
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
    List<dynamic> questions = [];
    if (data is Map && data['questions_list'] is List) {
      questions = data['questions_list'] as List;
    } else if (data is List) {
      questions = data;
    } else if (data is Map && data['questions'] is List) {
      questions = data['questions'] as List;
    }

    if (questions.isEmpty) {
      return const Center(child: Text('No questions generated.'));
    }

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
