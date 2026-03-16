import 'dart:async';
import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';
import '../mandarin_annotator/mandarin_annotator.dart';

// ---------------------------------------------------------------------------
// Streaming XML parse helpers (file-level, used only within this file)
// ---------------------------------------------------------------------------

String? _xmlPartial(String buf, String tag) {
  final open = buf.indexOf('<$tag>');
  if (open == -1) return null;
  final start = open + tag.length + 2;
  final close = buf.indexOf('</$tag>', start);
  return close == -1 ? buf.substring(start) : buf.substring(start, close);
}

/// Full-screen page for linguistic analysis.
///
/// User selects/enters a portion of the card's text
/// and the API analyzes sentence structure, grammar patterns, etc.
class LinguisticAnalysisPage extends StatefulWidget {
  final String fullText;
  final String? selectedText;

  const LinguisticAnalysisPage({
    super.key,
    required this.fullText,
    this.selectedText,
  });

  @override
  State<LinguisticAnalysisPage> createState() => _LinguisticAnalysisPageState();
}

class _LinguisticAnalysisPageState extends State<LinguisticAnalysisPage>
    with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();
  final MandarinAnnotator _annotator = MandarinAnnotator();
  final TextEditingController _selectionController = TextEditingController();

  AsyncJobStatusResponse? _result;
  bool _isLoading = false;
  String? _error;
  String _streamingText = '';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  // Dictionary-corrected pinyin (keyed by Chinese text)
  final Map<String, String> _correctedPinyin = {};

  @override
  void initState() {
    super.initState();
    // Pre-fill with selected text if provided, otherwise full text
    _selectionController.text = widget.selectedText ?? widget.fullText;
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
    _selectionController.dispose();
    super.dispose();
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    final selected = _selectionController.text.trim();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter text to analyze')));
      return;
    }

    _sseSub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
      _streamingText = '';
      _correctedPinyin.clear();
    });

    _sseSub = _api
        .linguisticStream(widget.fullText, selected, forceRefresh: forceRefresh, enableThinking: _thinkingEnabled)
        .listen(
          (ev) async {
            if (!mounted) return;
            if (ev.type == 'token') {
              setState(() => _streamingText += ev.data['t'] as String? ?? '');
            } else if (ev.type == 'result') {
              try {
                final status = AsyncJobStatusResponse.fromMap(ev.data);
                if (status.status == JobStatus.failed) {
                  setState(() {
                    _isLoading = false;
                    _error = status.error ?? 'Analysis failed';
                  });
                } else {
                  await _correctPinyin(status.result);
                  if (mounted) {
                    setState(() => _result = status);
                  }
                }
              } catch (_) {}
            } else if (ev.type == 'done') {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            } else if (ev.type == 'error') {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _error = ev.data['message'] as String? ?? 'Streaming error';
                });
              }
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

  /// Use MandarinAnnotator (dictionary-based) to get accurate pinyin for
  /// the analyzed text and grammar pattern examples, replacing LLM output.
  Future<void> _correctPinyin(dynamic data) async {
    if (data == null || data is! Map) return;
    final map = Map<String, dynamic>.from(data);

    // Collect all Chinese texts that need pinyin correction
    final textsToCorrect = <String>{};

    final analyzedText = map['analyzed_text'] as Map?;
    final chinese = analyzedText?['chinese'] as String? ?? '';
    if (chinese.isNotEmpty) textsToCorrect.add(chinese);

    final patterns = map['grammar_patterns'] as List? ?? [];
    for (final p in patterns) {
      if (p is! Map) continue;
      final ex = p['example_in_text'] as Map?;
      final exChinese = ex?['chinese'] as String? ?? '';
      if (exChinese.isNotEmpty) textsToCorrect.add(exChinese);
    }

    // Fetch accurate pinyin for each unique text
    for (final text in textsToCorrect) {
      try {
        final annotations = await _annotator.annotate(text, asWords: true);
        if (annotations.isNotEmpty) {
          final pinyin = annotations
              .map((a) => a['pinyin'] as String? ?? '')
              .where((p) => p.isNotEmpty)
              .join(' ');
          if (pinyin.isNotEmpty) {
            _correctedPinyin[text] = pinyin;
          }
        }
      } catch (_) {
        // Dictionary lookup failed — keep LLM pinyin as fallback
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linguistic Analysis'),
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
          // Input section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select text to analyze:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _selectionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Paste or type Chinese text…',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _analyze,
                    icon: const Icon(Icons.psychology),
                    label: Text(_isLoading ? 'Analyzing…' : 'Analyze Grammar'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      final cs = Theme.of(context).colorScheme;
      final buf = _streamingText;
      final analyzedChinese = _xmlPartial(buf, 'analyzed_chinese');
      final analyzedPinyin = _xmlPartial(buf, 'analyzed_pinyin');
      final expansionNote = _xmlPartial(buf, 'expansion_note');
      final englishTranslation = _xmlPartial(buf, 'english_translation');
      final sentenceStructure = _xmlPartial(buf, 'sentence_structure');
      final grammarRules = _xmlPartial(buf, 'grammar_rules');

      final hasContent =
          analyzedChinese != null ||
          englishTranslation != null ||
          sentenceStructure != null ||
          grammarRules != null;

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
                  if (!hasContent)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: const Text(
                          'Running linguistic analysis\u2026\nThis may take a moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),

                  // Analyzed text with pinyin
                  if (analyzedChinese != null &&
                      analyzedChinese.trim().isNotEmpty) ...[
                    _card(
                      cs,
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      borderColor: cs.primaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            analyzedChinese.trim(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.6,
                            ),
                          ),
                          if (analyzedPinyin != null &&
                              analyzedPinyin.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              analyzedPinyin.trim(),
                              style: TextStyle(
                                fontSize: 15,
                                color: cs.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Expansion note
                  if (expansionNote != null &&
                      expansionNote.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              expansionNote.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // English translation
                  if (englishTranslation != null &&
                      englishTranslation.trim().isNotEmpty) ...[
                    _sectionHeader('English Translation'),
                    _card(
                      cs,
                      child: SelectableText(
                        englishTranslation.trim(),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Sentence structure
                  if (sentenceStructure != null &&
                      sentenceStructure.trim().isNotEmpty) ...[
                    _sectionHeader('Sentence Structure'),
                    _card(
                      cs,
                      child: SelectableText(
                        sentenceStructure.trim(),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Grammar rules
                  if (grammarRules != null &&
                      grammarRules.trim().isNotEmpty) ...[
                    _sectionHeader('Grammar Rules'),
                    _card(
                      cs,
                      child: SelectableText(
                        grammarRules.trim(),
                        style: const TextStyle(fontSize: 15, height: 1.5),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    if (_result == null) {
      return const Center(
        child: Text(
          'Enter or select text above, then tap "Analyze Grammar"\n'
          'to see sentence structure and grammar patterns.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Parse the result map — backend returns:
    // {analyzed_text: {chinese, pinyin}, expansion_note, english_translation,
    //  sentence_structure_explanation, grammatical_rule_explanation,
    //  grammar_patterns: [{pattern, structure, example_in_text: {chinese, pinyin}, explanation}]}
    final data = _result!.result;
    if (data == null || data is! Map) {
      return const Center(child: Text('No analysis data returned.'));
    }

    final map = Map<String, dynamic>.from(data);
    final cs = Theme.of(context).colorScheme;

    // Analyzed text header
    final analyzedText = map['analyzed_text'] as Map?;
    final chinese = analyzedText?['chinese'] as String? ?? '';
    // Prefer dictionary-corrected pinyin over LLM-generated
    final pinyin =
        _correctedPinyin[chinese] ?? (analyzedText?['pinyin'] as String? ?? '');
    final expansionNote = map['expansion_note'] as String?;
    final translation = map['english_translation'] as String? ?? '';
    final structureExplanation =
        map['sentence_structure_explanation'] as String? ?? '';
    final grammarRuleExplanation =
        map['grammatical_rule_explanation'] as String? ?? '';
    final grammarPatterns = map['grammar_patterns'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Analyzed text with pinyin
          if (chinese.isNotEmpty) ...[
            _card(
              cs,
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderColor: cs.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    chinese,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.6,
                    ),
                  ),
                  if (pinyin.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      pinyin,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Expansion note
          if (expansionNote != null && expansionNote.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expansionNote,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // English translation
          if (translation.isNotEmpty) ...[
            _sectionHeader('English Translation'),
            _card(
              cs,
              child: SelectableText(
                translation,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Sentence structure explanation
          if (structureExplanation.isNotEmpty) ...[
            _sectionHeader('Sentence Structure'),
            _card(
              cs,
              child: SelectableText(
                structureExplanation,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Grammatical rule explanation
          if (grammarRuleExplanation.isNotEmpty) ...[
            _sectionHeader('Grammar Rules'),
            _card(
              cs,
              child: SelectableText(
                grammarRuleExplanation,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Grammar patterns
          if (grammarPatterns.isNotEmpty) ...[
            _sectionHeader('Grammar Patterns'),
            ...grammarPatterns.map((p) {
              if (p is! Map) return const SizedBox.shrink();
              final pm = Map<String, dynamic>.from(p);
              final patternName = pm['pattern'] as String? ?? '';
              final structure = pm['structure'] as String? ?? '';
              final example = pm['example_in_text'] as Map?;
              final exChinese = example?['chinese'] as String? ?? '';
              // Prefer dictionary-corrected pinyin over LLM-generated
              final exPinyin =
                  _correctedPinyin[exChinese] ??
                  (example?['pinyin'] as String? ?? '');
              final explanation = pm['explanation'] as String? ?? '';

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  shape: const Border(),
                  title: Text(
                    patternName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  subtitle: structure.isNotEmpty
                      ? Text(
                          structure,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : null,
                  initiallyExpanded: true,
                  children: [
                    if (exChinese.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              exChinese,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (exPinyin.isNotEmpty)
                              SelectableText(
                                exPinyin,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (explanation.isNotEmpty)
                      SelectableText(
                        explanation,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                  ],
                ),
              );
            }),
          ],
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

  Widget _card(
    ColorScheme cs, {
    required Widget child,
    Color? color,
    Color? borderColor,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color ?? cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor ?? Colors.grey.shade300),
    ),
    child: child,
  );
}
