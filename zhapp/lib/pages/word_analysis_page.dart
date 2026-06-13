import 'dart:async';
import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

// Streaming XML parse helpers (file-level, used only within this file)

String? _xmlPartial(String buf, String tag) {
  final open = buf.indexOf('<$tag>');
  if (open == -1) return null;
  final start = open + tag.length + 2;
  final close = buf.indexOf('</$tag>', start);
  return close == -1 ? buf.substring(start) : buf.substring(start, close);
}

List<String> _xmlItems(String buf, String parentTag) {
  final block = _xmlPartial(buf, parentTag);
  if (block == null) return [];
  return RegExp(
    r'<item>(.*?)</item>',
    dotAll: true,
  ).allMatches(block).map((m) => m.group(1)!.trim()).toList();
}

// Full-screen page showing word analysis (synonyms, antonyms, etc.).
///
// Allows the user to type or paste a Chinese word to analyze in context.
class WordAnalysisPage extends StatefulWidget {
  final String cardText;

  const WordAnalysisPage({super.key, required this.cardText});

  @override
  State<WordAnalysisPage> createState() => _WordAnalysisPageState();
}

class _WordAnalysisPageState extends State<WordAnalysisPage>
    with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();
  final TextEditingController _wordController = TextEditingController();

  WordAnalysisResponse? _result;
  bool _isLoading = false;
  String? _error;
  String _streamingText = '';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _wordController.text = widget.cardText;
    _thinkingEnabled = _api.thinkingEnabled;
  }

  void _toggleThinking() {
    final next = !_thinkingEnabled;
    _api.thinkingEnabled = next;
    setState(() => _thinkingEnabled = next);
    _analyze(forceRefresh: true);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a word to analyze')));
      return;
    }

    _sseSub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _streamingText = '';
    });

    _sseSub = _api
        .analyzeWordStream(
          word,
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
                setState(() => _result = WordAnalysisResponse.fromMap(ev.data));
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
            if (mounted)
              setState(() {
                _isLoading = false;
                _error = e.toString();
              });
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
        title: const Text('Word Analysis'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.psychology,
              color: _thinkingEnabled
                  ? null
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            tooltip: _thinkingEnabled
                ? 'Thinking enabled — tap to disable'
                : 'Thinking disabled — tap to enable',
            onPressed: _toggleThinking,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (bypass cache)',
            onPressed: _isLoading ? null : () => _analyze(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Input bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wordController,
                    decoration: InputDecoration(
                      labelText: 'Chinese word',
                      hintText: 'e.g. 高兴',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _wordController.clear();
                          setState(() {
                            _result = null;
                            _error = null;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) => _analyze(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _analyze,
                  icon: const Icon(Icons.search),
                  label: const Text('Analyze'),
                ),
              ],
            ),
          ),

          const Divider(height: 24),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      final cs = Theme.of(context).colorScheme;
      final buf = _streamingText;
      final synonyms = _xmlItems(buf, 'synonyms');
      final antonyms = _xmlItems(buf, 'antonyms');
      final alternatives = _xmlItems(buf, 'alternative_wordings');
      final usageExamples = _xmlItems(buf, 'usage_examples');
      final explanation = _xmlPartial(buf, 'explanation');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Word being analyzed — always shown immediately
                  Center(
                    child: Text(
                      _wordController.text.trim(),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (synonyms.isEmpty &&
                      antonyms.isEmpty &&
                      alternatives.isEmpty &&
                      usageExamples.isEmpty &&
                      explanation == null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Analyzing\u2026',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),

                  // Explanation (free text, streams live)
                  if (explanation != null && explanation.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        explanation.trim(),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (synonyms.isNotEmpty)
                    _streamingTagSection(
                      'Synonyms',
                      synonyms,
                      Colors.green,
                      cs,
                    ),
                  if (antonyms.isNotEmpty)
                    _streamingTagSection('Antonyms', antonyms, Colors.red, cs),
                  if (alternatives.isNotEmpty)
                    _streamingTagSection(
                      'Alternative Wordings',
                      alternatives,
                      Colors.orange,
                      cs,
                    ),

                  if (usageExamples.isNotEmpty) ...[
                    Text(
                      'Usage Examples',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...usageExamples.map(
                      (ex) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📝 ', style: TextStyle(fontSize: 14)),
                            Expanded(
                              child: SelectableText(
                                ex,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_result == null) {
      return const Center(
        child: Text(
          'Enter a Chinese word above to see\nsynonyms, antonyms, and more.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Word header
          Center(
            child: Text(
              _result!.word,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // Explanation
          if (_result!.explanation != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _result!.explanation!,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Synonyms
          if (_result!.synonyms.isNotEmpty)
            _tagSection('Synonyms', _result!.synonyms, Colors.green),

          // Antonyms
          if (_result!.antonyms.isNotEmpty)
            _tagSection('Antonyms', _result!.antonyms, Colors.red),

          // Alternatives
          if (_result!.alternativeWordings.isNotEmpty)
            _tagSection(
              'Alternative Wordings',
              _result!.alternativeWordings,
              Colors.orange,
            ),

          // Usage examples
          if (_result!.usageExamples.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Usage Examples',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._result!.usageExamples.map(
              (ex) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📝 ', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Text(
                        ex,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _streamingTagSection(
    String title,
    List<String> items,
    Color color,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.map((item) {
              return Chip(
                label: Text(item),
                backgroundColor: color.withValues(alpha: 0.12),
                side: BorderSide(color: color.withValues(alpha: 0.4)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _tagSection(String title, List<String> items, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.map((item) {
              return Chip(
                label: Text(item),
                backgroundColor: color.withValues(alpha: 0.12),
                side: BorderSide(color: color.withValues(alpha: 0.4)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
