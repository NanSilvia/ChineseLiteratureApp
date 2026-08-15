import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../mandarin_annotator/mandarin_annotator.dart';

class AnnotatedChineseText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final void Function(String?)? onSelectionChanged;

  const AnnotatedChineseText({
    super.key,
    required this.text,
    this.style,
    this.onSelectionChanged,
  });

  @override
  State<AnnotatedChineseText> createState() => _AnnotatedChineseTextState();
}

class _AnnotatedChineseTextState extends State<AnnotatedChineseText> {
  final MandarinAnnotator _annotator = MandarinAnnotator();

  List<Map<String, dynamic>>? _annotations;
  bool _isLoading = true;
  String? _error;
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  //  lifecycle

  @override
  void initState() {
    super.initState();
    _loadAnnotations();
  }

  @override
  void didUpdateWidget(covariant AnnotatedChineseText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _loadAnnotations();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  //  annotation loading

  Future<void> _loadAnnotations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final annotations = await _annotator.annotate(widget.text, asWords: true);
      if (mounted) {
        _disposeRecognizers();
        for (final ann in annotations) {
          _recognizers.add(
            TapGestureRecognizer()..onTap = () => _showWordDetails(ann),
          );
        }
        setState(() {
          _annotations = annotations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  //  build

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        (widget.style ?? const TextStyle(fontSize: 16, color: Colors.black87))
            .copyWith(height: 1.4);

    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(widget.text, style: baseStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Loading annotations…',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      );
    }

    if (_error != null || _annotations == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPressStart: (details) =>
                _showContextMenuFallback(details.globalPosition, widget.text),
            child: SelectableText(widget.text, style: baseStyle),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _loadAnnotations,
            child: Row(
              children: [
                Icon(Icons.refresh, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Tap to load annotations',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _buildAnnotatedTextWithPunctuation(
      widget.text,
      _annotations!,
      baseStyle,
    );
  }

  //  Rendering

  Widget _buildAnnotatedTextWithPunctuation(
    String text,
    List<Map<String, dynamic>> annotations,
    TextStyle baseStyle,
  ) {
    List<InlineSpan> spans = [];
    int textIndex = 0;
    int annIndex = 0;

    while (textIndex < text.length) {
      if (annIndex < annotations.length) {
        final nextAnn = annotations[annIndex];
        final wordToFind = nextAnn['word'] as String;
        final wordStart = text.indexOf(wordToFind, textIndex);

        if (wordStart == textIndex) {
          spans.add(
            TextSpan(
              text: wordToFind,
              style: baseStyle,
              recognizer: annIndex < _recognizers.length
                  ? _recognizers[annIndex]
                  : null,
            ),
          );
          textIndex += wordToFind.length;
          annIndex++;
        } else {
          final nextAnnotStart = wordStart >= 0 ? wordStart : text.length;
          spans.add(
            TextSpan(
              text: text.substring(textIndex, nextAnnotStart),
              style: baseStyle,
            ),
          );
          textIndex = nextAnnotStart;
        }
      } else {
        spans.add(TextSpan(text: text.substring(textIndex), style: baseStyle));
        break;
      }
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor:
          DefaultSelectionStyle.of(context).selectionColor ??
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
    );
  }

  void _showWordDetails(Map<String, dynamic> annotation) {
    final List<dynamic> details = annotation['details'] as List? ?? [];
    final List<dynamic> allDefs = annotation['definitions_full'] as List? ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          annotation['word'] as String,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (details.isNotEmpty)
                ...details.map((detail) {
                  final List<dynamic> pinyinList =
                      detail['pinyin'] as List? ?? [];
                  final List<dynamic> definitionsList =
                      detail['definitions'] as List? ?? [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: pinyinList.asMap().entries.map((entry) {
                      final index = entry.key;
                      final pinyinStr = entry.value as String;
                      final def = index < definitionsList.length
                          ? definitionsList[index] as String
                          : '';
                      final meanings = def.split(RegExp(r'[/;]'));

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pinyinStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...meanings.map(
                              (meaning) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $meaning',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                })
              else if (allDefs.isNotEmpty)
                ...allDefs.cast<String>().map((def) {
                  final parts = def.split(RegExp(r'[/;]'));
                  if (parts.isNotEmpty) {
                    final pronunciation = parts[0];
                    final meanings = parts.length > 1
                        ? parts.skip(1).toList()
                        : <String>[];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pronunciation,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...meanings.map(
                            (meaning) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $meaning',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                })
              else
                const Text('No definitions available'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  //  Fallback context menu (error / loading-failed state)

  Future<void> _showContextMenuFallback(Offset position, String text) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy text'),
            ],
          ),
        ),
      ],
    );

    if (result == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }
}
