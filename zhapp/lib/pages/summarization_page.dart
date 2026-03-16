import 'dart:async';
import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

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

List<String> _xmlItems(String buf, String parentTag) {
  final block = _xmlPartial(buf, parentTag);
  if (block == null) return [];
  return RegExp(
    r'<item>(.*?)</item>',
    dotAll: true,
  ).allMatches(block).map((m) => m.group(1)!.trim()).toList();
}

/// Full-screen page showing AI-powered summarization result.
class SummarizationPage extends StatefulWidget {
  final String text;

  const SummarizationPage({super.key, required this.text});

  @override
  State<SummarizationPage> createState() => _SummarizationPageState();
}

class _SummarizationPageState extends State<SummarizationPage>
    with ConnectivityAware {
  final TranslationApiService _api = TranslationApiService();

  SummarizationResponse? _result;
  bool _isLoading = true;
  String? _error;
  String _streamingText = '';
  bool _thinkingEnabled = true;
  StreamSubscription<SseEvent>? _sseSub;

  // Configurable options
  String _length = 'medium';
  String _style = 'neutral';

  final _lengths = ['short', 'medium', 'long'];
  final _styles = ['neutral', 'simple', 'academic'];

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
    });

    _sseSub = _api
        .summarizeStream(
          widget.text,
          language: 'chi',
          length: _length,
          style: _style,
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
                setState(
                  () => _result = SummarizationResponse.fromMap(ev.data),
                );
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
        title: const Text('Summarization'),
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
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Options row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _dropdownChip(
                  label: 'Length',
                  value: _length,
                  items: _lengths,
                  onChanged: (v) {
                    setState(() => _length = v);
                    _load();
                  },
                ),
                _dropdownChip(
                  label: 'Style',
                  value: _style,
                  items: _styles,
                  onChanged: (v) {
                    setState(() => _style = v);
                    _load();
                  },
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

  Widget _dropdownChip({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: '),
          Text(
            value,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
      onPressed: () async {
        final picked = await showMenu<String>(
          context: context,
          position: RelativeRect.fill,
          items: items
              .map((i) => PopupMenuItem(value: i, child: Text(i)))
              .toList(),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      final cs = Theme.of(context).colorScheme;
      final summaryContent = _xmlPartial(_streamingText, 'summary');
      final keyPoints = _xmlItems(_streamingText, 'key_points');
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
                  if (summaryContent != null) ...[
                    Text(
                      'Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primaryContainer),
                      ),
                      child: SelectableText(
                        summaryContent.trim(),
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Text(
                          'Summarizing\u2026',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  if (keyPoints.isNotEmpty) ...[
                    Text(
                      'Key Points',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(
                      keyPoints.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: cs.primary,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                keyPoints[i],
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
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_result == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Wrap(
            spacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.text_fields, size: 16),
                label: Text('Original: ${_result!.wordCountOriginal} chars'),
              ),
              Chip(
                avatar: const Icon(Icons.short_text, size: 16),
                label: Text('Summary: ${_result!.wordCountSummary} chars'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary
          Text(
            'Summary',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primaryContainer),
            ),
            child: SelectableText(
              _result!.summary,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
          ),

          // Key points
          if (_result!.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Key Points',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...List.generate(_result!.keyPoints.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: cs.primary,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 12, color: cs.onPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _result!.keyPoints[i],
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
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
}
