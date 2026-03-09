import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

/// Full-screen page showing word analysis (synonyms, antonyms, etc.).
///
/// Allows the user to type or paste a Chinese word to analyze in context.
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

  @override
  void initState() {
    super.initState();
    _wordController.text = widget.cardText;
  }

  @override
  void dispose() {
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.analyzeWord(word, forceRefresh: forceRefresh);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
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
        title: const Text('Word Analysis'),
        actions: [
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Analyzing word…'),
          ],
        ),
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
