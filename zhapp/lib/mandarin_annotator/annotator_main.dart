import 'package:flutter/material.dart';
import 'package:zhapp/mandarin_annotator/mandarin_annotator.dart';

void main() {
  runApp(const MandarinAnnotatorApp());
}

class MandarinAnnotatorApp extends StatelessWidget {
  const MandarinAnnotatorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mandarin Annotator',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const AnnotatorTestPage(),
    );
  }
}

class AnnotatorTestPage extends StatefulWidget {
  const AnnotatorTestPage({Key? key}) : super(key: key);

  @override
  State<AnnotatorTestPage> createState() => _AnnotatorTestPageState();
}

class _AnnotatorTestPageState extends State<AnnotatorTestPage> {
  final annotator = MandarinAnnotator();
  late Future<List<Map<String, dynamic>>> annotationsFuture;

  static const String testText =
      """北京故宫是中国明清两代的皇家宫殿，旧称为紫禁城，是中国古代宫廷建筑的精华。北京故宫以三大殿为中心，占地面积72万平方米，建筑面积约15万平方米，有大小宫殿七十多座，房屋九千余间。是世界上现存规模最大、保存最为完整的木质结构古建筑之一。
故宫博物院是一座特殊的博物馆，成立于1925年，建立在紫禁城的基础上。近几年，在人们头脑中陈旧甚至略微显得古板的故宫开始活跃起来。一部《我在故宫修文物》让普通人了解到故宫背后的工匠精神，《 国家宝藏》恢弘的气势与现代科技结合，让人们见识到大国风范
故宫文创，依托悠久的故宫历史，发掘新的产品形态，将古老与现代结合，将历史与商业叠加。故宫口红，故宫项链，故宫台历等等，被人们广为使用。""";

  @override
  void initState() {
    super.initState();
    annotationsFuture = annotator.annotate(testText, asWords: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mandarin Annotator - Hover for Details'),
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: annotationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading annotations...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        annotationsFuture = annotator.annotate(
                          testText,
                          asWords: true,
                        );
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          List<Map<String, dynamic>> annotations = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  'Forbidden City Text Annotation',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Hover over any word to see pronunciation and definitions',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),

                // Annotated text display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[50],
                  ),
                  child: _buildAnnotatedTextWithPunctuation(
                    testText,
                    annotations,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnnotatedTextWithPunctuation(
    String text,
    List<Map<String, dynamic>> annotations,
  ) {
    List<Widget> children = [];
    int textIndex = 0;
    int annIndex = 0;

    while (textIndex < text.length) {
      if (annIndex < annotations.length) {
        // Check if next annotation starts at current position
        // Find it by matching the character sequence
        Map<String, dynamic> nextAnn = annotations[annIndex];
        String wordToFind = nextAnn['word'] as String;

        int wordStart = text.indexOf(wordToFind, textIndex);
        if (wordStart == textIndex) {
          // Add any punctuation/non-CJK before this word
          if (textIndex > 0 && children.isNotEmpty == false) {
            // Already handled
          }

          // Add the annotated word
          children.add(AnnotatedWordWidget(annotation: nextAnn));
          textIndex += wordToFind.length;
          annIndex++;
        } else {
          // Add punctuation/non-CJK character
          String char = text[textIndex];
          children.add(
            Text(
              char,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          );
          textIndex++;
        }
      } else {
        // Add remaining punctuation/non-CJK
        String char = text[textIndex];
        children.add(
          Text(
            char,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        );
        textIndex++;
      }
    }

    return Wrap(spacing: 0, runSpacing: 0, children: children);
  }

  Widget _buildDetailsTable(
    BuildContext context,
    List<Map<String, dynamic>> annotations,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Word')),
          DataColumn(label: Text('Pinyin')),
          DataColumn(label: Text('Chars')),
          DataColumn(label: Text('All Definitions')),
        ],
        rows: annotations.map((ann) {
          String definitions = '';
          if (ann['definitions_full'] is List &&
              ann['definitions_full'].isNotEmpty) {
            List<String> allDefs = [];
            for (String def in ann['definitions_full'].cast<String>()) {
              final parts = def.split(RegExp(r'[/;]'));
              // Add all meanings (everything after the pinyin)
              if (parts.length > 1) {
                allDefs.addAll(parts.skip(1).toList());
              }
            }
            definitions = allDefs.join('\n');
          }

          return DataRow(
            cells: [
              DataCell(
                Text(
                  ann['word'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(Text(ann['pinyin'] as String)),
              DataCell(Text('${ann['character_count']}')),
              DataCell(
                Text(definitions, maxLines: 5, overflow: TextOverflow.ellipsis),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// Widget that displays a single annotated word with hover tooltip
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

  Iterable<T> flatten<T>(Iterable<Iterable<T>> items) sync* {
    for (var i in items) {
      yield* i;
    }
  }

  Iterable<X> flatMap<T, X>(Iterable<Iterable<T>> items, X Function(T) f) =>
      flatten(items).map(f);

  String _buildTooltipText() {
    String word = widget.annotation['word'] as String;
    String pinyin = widget.annotation['pinyin'] as String;
    List<dynamic> allDefs = widget.annotation['definitions_full'] ?? [];

    String definition;
    if (allDefs.isNotEmpty) {
      // Split each definition_full entry by / to get pinyin and meaning
      List<String> meanings = [];
      for (String def in allDefs.cast<String>()) {
        final parts = def.split(RegExp(r'[/;]'));
        // Add all parts after the first one (which is pinyin) as separate meanings
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

                  // Group each pronunciation with its meanings
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: pinyinList.asMap().entries.map((entry) {
                      int index = entry.key;
                      String pinyinStr = entry.value as String;

                      // Get the corresponding definition for this pronunciation
                      String def = index < definitionsList.length
                          ? definitionsList[index] as String
                          : '';

                      // Split the definition by / to get all meanings
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
