import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recase/recase.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

/// Full-screen page showing translation result for a card's Chinese text.
class TranslationResultPage extends StatefulWidget {
  final String text;

  const TranslationResultPage({super.key, required this.text});

  @override
  State<TranslationResultPage> createState() => _TranslationResultPageState();
}

class _TranslationResultPageState extends State<TranslationResultPage>
    with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();

  TranslationResponse? _result;
  bool _isLoading = true;
  String? _error;
  String _schemaName = 'translate';

  final List<String> _schemas = ['translate', 'simple', 'detailed'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.translate(
      widget.text,
      schemaName: _schemaName,
      forceRefresh: forceRefresh,
    );

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (bypass cache)',
            onPressed: _isLoading ? null : () => _load(forceRefresh: true),
          ),
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy translation',
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _result!.combinedTranslation),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Translation copied')),
                );
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            const OfflineBanner(),
            // Schema picker
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: _schemas
                      .map((s) => ButtonSegment(value: s, label: Text(s)))
                      .toList(),
                  selected: {_schemaName},
                  onSelectionChanged: (v) {
                    setState(() => _schemaName = v.first);
                    _load();
                  },
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Translating…'),
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

    if (_result == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Original text
          _sectionHeader('Original Text'),
          _card(
            child: SelectableText(
              _result!.inputText,
              style: const TextStyle(fontSize: 18, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),

          // Translations per model
          ..._result!.translations.entries.map((e) {
            final data = e.value;
            if (data is Map<String, dynamic>) {
              return _buildTranslationData(data, e.key, cs);
            }
            // Simple string fallback
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                child: SelectableText(
                  data.toString(),
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            );
          }),

          // Dictionary entries
          if (_result!.dictionaryEntries != null &&
              _result!.dictionaryEntries!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Dictionary'),
            ..._result!.dictionaryEntries!.map(
              (d) => _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          d.sourceTerm,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          d.romanized,
                          style: TextStyle(fontSize: 14, color: cs.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...d.suggestions.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• $s'),
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

  /// Renders a single model's translation data based on actual backend shape.
  ///
  /// Schema shapes from backend:
  /// - "translate": {translated_text, explanations: [[part, explanation], ...]}
  /// - "simple":    {translated_text}
  /// - "detailed":  {translated_text, grammatical_analysis: [[s,e],...],
  ///                 challenging_phrases: [[p,e],...], cultural_context,
  ///                 stylistic_notes, alternative_interpretations: [...]}
  Widget _buildTranslationData(
    Map<String, dynamic> data,
    String modelName,
    ColorScheme cs,
  ) {
    final translatedText = data['translated_text'] as String? ?? '';

    // Explanations list — "translate" schema
    final explanations =
        data['explanations'] as List? ??
        data['explainations_list'] as List? ??
        [];

    // Detailed schema fields
    final grammaticalAnalysis = data['grammatical_analysis'] as List? ?? [];
    final challengingPhrases = data['challenging_phrases'] as List? ?? [];
    final culturalContext = data['cultural_context'] as String?;
    final stylisticNotes = data['stylistic_notes'] as String?;
    final altInterpretations =
        data['alternative_interpretations'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Translation
          _sectionHeader('Translation'),
          _card(
            child: SelectableText(
              translatedText,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
          ),

          // Explanations (translate schema) — [[part, explanation], ...]
          if (explanations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Explanations'),
            ...explanations.map((item) {
              if (item is List && item.length >= 2) {
                return _explanationTile(
                  item[0].toString(),
                  item[1].toString(),
                  cs,
                );
              }
              return const SizedBox.shrink();
            }),
          ],

          // Grammatical Analysis (detailed schema)
          if (grammaticalAnalysis.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Grammatical Analysis'),
            ...grammaticalAnalysis.map((item) {
              if (item is List && item.length >= 2) {
                return _explanationTile(
                  item[0].toString().titleCase,
                  item[1].toString(),
                  cs,
                );
              }
              return const SizedBox.shrink();
            }),
          ],

          // Challenging Phrases (detailed schema)
          if (challengingPhrases.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Challenging Phrases'),
            ...challengingPhrases.map((item) {
              if (item is List && item.length >= 2) {
                return _explanationTile(
                  item[0].toString().titleCase,
                  item[1].toString(),
                  cs,
                );
              }
              return const SizedBox.shrink();
            }),
          ],

          // Cultural Context (detailed schema)
          if (culturalContext != null && culturalContext.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Cultural Context'),
            _card(
              child: SelectableText(
                culturalContext,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ],

          // Stylistic Notes (detailed schema)
          if (stylisticNotes != null && stylisticNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Stylistic Notes'),
            _card(
              child: SelectableText(
                stylisticNotes,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ],

          // Alternative Interpretations (detailed schema)
          if (altInterpretations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Alternative Interpretations'),
            ...altInterpretations.map(
              (alt) => Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        alt.toString(),
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

  /// Renders a [part, explanation] tuple as an expandable tile.
  Widget _explanationTile(String part, String explanation, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const Border(),
        title: Text(
          part,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
        children: [
          SelectableText(
            explanation,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: child,
  );
}
