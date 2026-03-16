import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recase/recase.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

// ---------------------------------------------------------------------------
// Streaming XML parse helpers (file-level, used only within this file)
// ---------------------------------------------------------------------------

/// Returns the content inside [tag] in [buf]. If the closing tag hasn't
/// arrived yet, returns everything after the opening tag (partial content).
/// Returns null if the opening tag hasn't appeared at all.
String? _xmlPartial(String buf, String tag) {
  final open = buf.indexOf('<$tag>');
  if (open == -1) return null;
  final start = open + tag.length + 2;
  final close = buf.indexOf('</$tag>', start);
  return close == -1 ? buf.substring(start) : buf.substring(start, close);
}

String _sanitizeVisibleTranslation(dynamic value) {
  final text = value?.toString() ?? '';
  if (!text.contains('<')) return text;
  final extracted = _xmlPartial(text, 'translated_text');
  if (extracted != null && extracted.trim().isNotEmpty) {
    return extracted.trim();
  }
  return text.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

/// Returns completed `<pair><source>…</source><detail>…</detail></pair>`
/// blocks found inside [parentTag] as `[source, detail]` pairs.
List<List<String>> _xmlPairs(String buf, String parentTag) {
  final block = _xmlPartial(buf, parentTag);
  if (block == null) return [];
  final pairs = <List<String>>[];
  for (final m in RegExp(
    r'<pair>(.*?)</pair>',
    dotAll: true,
  ).allMatches(block)) {
    final inner = m.group(1)!;
    pairs.add([
      (_xmlPartial(inner, 'source') ?? '').trim(),
      (_xmlPartial(inner, 'detail') ?? '').trim(),
    ]);
  }
  return pairs;
}

/// Returns completed `<item>…</item>` strings found inside [parentTag].
List<String> _xmlItems(String buf, String parentTag) {
  final block = _xmlPartial(buf, parentTag);
  if (block == null) return [];
  return RegExp(
    r'<item>(.*?)</item>',
    dotAll: true,
  ).allMatches(block).map((m) => m.group(1)!.trim()).toList();
}

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
  String _streamingText = '';
  String _statusMessage = 'Translating\u2026';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  final List<String> _schemas = ['translate', 'simple', 'detailed'];

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
      _statusMessage = 'Translating\u2026';
    });

    if (forceRefresh) {
      // For force-refresh, fall back to the non-streaming (cached) path
      // but use the stream to show tokens live.
    }

    _sseSub = _api
        .translateStream(
          widget.text,
          schemaName: _schemaName,
          forceRefresh: forceRefresh,
          enableThinking: _thinkingEnabled,
        )
        .listen(
          (ev) {
            if (!mounted) return;
            if (ev.type == 'status') {
              setState(
                () => _statusMessage = ev.data['message'] as String? ?? '',
              );
            } else if (ev.type == 'token') {
              setState(() => _streamingText += ev.data['t'] as String? ?? '');
            } else if (ev.type == 'result') {
              try {
                final parsed = TranslationResponse.fromMap(ev.data);
                setState(() => _result = parsed);
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation'),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(minHeight: 2),
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _statusMessage,
                style: TextStyle(color: cs.primary, fontSize: 12),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('Original Text'),
                  _card(
                    child: SelectableText(
                      widget.text,
                      style: const TextStyle(fontSize: 18, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildStreamingSections(cs),
                ],
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
                  _sanitizeVisibleTranslation(data),
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

  // ---------------------------------------------------------------------------
  // Section-aware streaming display
  // ---------------------------------------------------------------------------

  List<Widget> _buildStreamingSections(ColorScheme cs) {
    final buf = _streamingText;
    if (buf.isEmpty) return [];
    final widgets = <Widget>[];

    // Translation — all schemas generate <translated_text> first
    final translatedContent = _xmlPartial(buf, 'translated_text');
    if (translatedContent != null) {
      widgets.add(_sectionHeader('Translation'));
      widgets.add(
        _card(
          child: SelectableText(
            translatedContent.trim(),
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    // "translate" schema: <explanations> with <pair> items
    if (_schemaName == 'translate') {
      final explanations = _xmlPairs(buf, 'explanations');
      if (explanations.isNotEmpty) {
        widgets.add(_sectionHeader('Explanations'));
        for (final item in explanations) {
          if (item.length >= 2) {
            widgets.add(_explanationTile(item[0], item[1], cs));
          }
        }
        widgets.add(const SizedBox(height: 16));
      }
    }

    // "detailed" schema: grammatical_analysis, challenging_phrases,
    // cultural_context, stylistic_notes, alternative_interpretations
    if (_schemaName == 'detailed') {
      final grammaticalAnalysis = _xmlPairs(buf, 'grammatical_analysis');
      if (grammaticalAnalysis.isNotEmpty) {
        widgets.add(_sectionHeader('Grammatical Analysis'));
        for (final item in grammaticalAnalysis) {
          if (item.length >= 2) {
            widgets.add(_explanationTile(item[0].titleCase, item[1], cs));
          }
        }
        widgets.add(const SizedBox(height: 16));
      }

      final challengingPhrases = _xmlPairs(buf, 'challenging_phrases');
      if (challengingPhrases.isNotEmpty) {
        widgets.add(_sectionHeader('Challenging Phrases'));
        for (final item in challengingPhrases) {
          if (item.length >= 2) {
            widgets.add(_explanationTile(item[0].titleCase, item[1], cs));
          }
        }
        widgets.add(const SizedBox(height: 16));
      }

      final culturalContext = _xmlPartial(buf, 'cultural_context');
      if (culturalContext != null && culturalContext.trim().isNotEmpty) {
        widgets.add(_sectionHeader('Cultural Context'));
        widgets.add(
          _card(
            child: SelectableText(
              culturalContext.trim(),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        );
        widgets.add(const SizedBox(height: 16));
      }

      final stylisticNotes = _xmlPartial(buf, 'stylistic_notes');
      if (stylisticNotes != null && stylisticNotes.trim().isNotEmpty) {
        widgets.add(_sectionHeader('Stylistic Notes'));
        widgets.add(
          _card(
            child: SelectableText(
              stylisticNotes.trim(),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        );
        widgets.add(const SizedBox(height: 16));
      }

      final altInterpretations = _xmlItems(buf, 'alternative_interpretations');
      if (altInterpretations.isNotEmpty) {
        widgets.add(_sectionHeader('Alternative Interpretations'));
        for (final alt in altInterpretations) {
          widgets.add(
            Padding(
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
                      alt,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    return widgets;
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
