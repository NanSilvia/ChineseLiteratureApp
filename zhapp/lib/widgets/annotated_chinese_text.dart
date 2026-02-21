import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../mandarin_annotator/mandarin_annotator.dart';

/// Displays Chinese text with interactive word-level annotations.
///
/// Uses the exact rendering logic from the original annotator_main.dart.
/// Falls back to plain [SelectableText] while loading or on error.
class AnnotatedChineseText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const AnnotatedChineseText({super.key, required this.text, this.style});

  @override
  State<AnnotatedChineseText> createState() => _AnnotatedChineseTextState();
}

class _AnnotatedChineseTextState extends State<AnnotatedChineseText> {
  final MandarinAnnotator _annotator = MandarinAnnotator();

  List<Map<String, dynamic>>? _annotations;
  bool _isLoading = true;
  String? _error;

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

  Future<void> _loadAnnotations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final annotations = await _annotator.annotate(widget.text, asWords: true);
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        widget.style ?? const TextStyle(fontSize: 16, color: Colors.black87);

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
                _showContextMenu(details.globalPosition, widget.text),
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

    return GestureDetector(
      onLongPressStart: (details) =>
          _showContextMenu(details.globalPosition, widget.text),
      child: _buildAnnotatedTextWithPunctuation(
        widget.text,
        _annotations!,
        baseStyle,
      ),
    );
  }

  // ──── Exact rendering logic from annotator_main.dart ────

  Widget _buildAnnotatedTextWithPunctuation(
    String text,
    List<Map<String, dynamic>> annotations,
    TextStyle baseStyle,
  ) {
    List<Widget> children = [];
    int textIndex = 0;
    int annIndex = 0;

    while (textIndex < text.length) {
      if (annIndex < annotations.length) {
        Map<String, dynamic> nextAnn = annotations[annIndex];
        String wordToFind = nextAnn['word'] as String;

        int wordStart = text.indexOf(wordToFind, textIndex);
        if (wordStart == textIndex) {
          children.add(AnnotatedWordWidget(annotation: nextAnn));
          textIndex += wordToFind.length;
          annIndex++;
        } else {
          String char = text[textIndex];
          children.add(Text(char, style: baseStyle));
          textIndex++;
        }
      } else {
        String char = text[textIndex];
        children.add(Text(char, style: baseStyle));
        textIndex++;
      }
    }

    return Wrap(spacing: 0, runSpacing: 0, children: children);
  }

  // ──── Context menu ────

  void _showContextMenu(Offset position, String text) async {
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

// ──── AnnotatedWordWidget — exact copy from annotator_main.dart ────

class AnnotatedWordWidget extends StatefulWidget {
  final Map<String, dynamic> annotation;

  const AnnotatedWordWidget({Key? key, required this.annotation})
    : super(key: key);

  @override
  State<AnnotatedWordWidget> createState() => _AnnotatedWordWidgetState();
}

class _AnnotatedWordWidgetState extends State<AnnotatedWordWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: _buildTooltipText(),
        showDuration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.blue[100] : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _isHovered ? Colors.blue : Colors.transparent,
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTap: () => _showDetailsDialog(context),
            child: Text(
              widget.annotation['word'] as String,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontWeight: _isHovered ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildTooltipText() {
    String word = widget.annotation['word'] as String;
    String pinyin = widget.annotation['pinyin'] as String;
    List<dynamic> allDefs = widget.annotation['definitions_full'] ?? [];

    String definition;
    if (allDefs.isNotEmpty) {
      List<String> meanings = [];
      for (String def in allDefs.cast<String>()) {
        final parts = def.split(RegExp(r'[/;]'));
        if (parts.length > 1) {
          meanings.addAll(parts.skip(1).toList());
        }
      }
      definition = meanings.isNotEmpty
          ? meanings.join('\n')
          : 'No definition available';
    } else {
      definition = 'No definition available';
    }

    return '$word [$pinyin]\n$definition';
  }

  void _showDetailsDialog(BuildContext context) {
    List<dynamic> details = widget.annotation['details'] as List? ?? [];
    List<dynamic> allDefs =
        widget.annotation['definitions_full'] as List? ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.annotation['word'] as String,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (details.isNotEmpty)
                ...details.map((detail) {
                  List<dynamic> pinyinList = detail['pinyin'] as List? ?? [];
                  List<dynamic> definitionsList =
                      detail['definitions'] as List? ?? [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: pinyinList.asMap().entries.map((entry) {
                      int index = entry.key;
                      String pinyinStr = entry.value as String;

                      String def = index < definitionsList.length
                          ? definitionsList[index] as String
                          : '';

                      List<String> meanings = def.split(RegExp(r'[/;]'));

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
                            ...meanings.map((meaning) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $meaning',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }).toList()
              else if (allDefs.isNotEmpty)
                ...allDefs.cast<String>().map((def) {
                  final parts = def.split(RegExp(r'[/;]'));
                  if (parts.isNotEmpty) {
                    String pronunciation = parts[0];
                    List<String> meanings = parts.length > 1
                        ? parts.skip(1).toList()
                        : [];

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
                          ...meanings.map((meaning) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $meaning',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }).toList()
              else
                const Text('No definitions available'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
