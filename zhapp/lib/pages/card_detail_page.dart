import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../services/connectivity_service.dart';
import '../widgets/annotated_chinese_text.dart';
import 'translation_result_page.dart';
import 'summarization_page.dart';
import 'word_analysis_page.dart';
import 'linguistic_analysis_page.dart';
import 'questions_page.dart';
import 'books_page.dart';

/// Card Detail View (Inside Screen 1)
/// Shows full card content and analysis section (online-only)
class CardDetailPage extends StatefulWidget {
  final int cardId;

  const CardDetailPage({super.key, required this.cardId});

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage>
    with ConnectivityAware {
  final ApiService _api = ApiService();

  CardModel? _card;
  bool _isLoading = true;
  String? _error;

  // Edit state
  bool _isEditing = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  // Analysis state
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysis;
  String? _analysisError;

  // Text selection state
  bool _isSelectingText = false;
  String? _selectedText;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _titleController.text = _card?.title ?? '';
      _textController.text = _card?.textZh ?? '';
    });
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  Future<void> _saveEdit() async {
    if (_card == null) return;

    final newText = _textController.text.trim();
    if (newText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chinese text cannot be empty.')),
      );
      return;
    }

    if (isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be online to edit cards.')),
      );
      return;
    }

    final updated = _card!.copyWith(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      textZh: newText,
    );

    final result = await _api.updateCard(updated);
    if (result.isSuccess) {
      setState(() {
        _card = result.data;
        _isEditing = false;
        _analysis = null; // re-analyse with new text
      });
      CardNotifier().notifyCardsChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Card updated.')));
      }
      if (isOnline) _loadAnalysis();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to update card')),
        );
      }
    }
  }

  @override
  void onConnectivityChanged(bool isOnline) {
    if (isOnline && _card != null && _analysis == null) {
      // Auto-load analysis when coming back online
      _loadAnalysis();
    }
  }

  Future<void> _loadCard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.getCardById(widget.cardId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _card = result.data;
          // Auto-load analysis if online
          if (isOnline) {
            _loadAnalysis();
          }
        } else {
          _error = result.error;
        }
      });
    }
  }

  Future<void> _loadAnalysis() async {
    if (_card == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });

    final result = await _api.analyzeText(_card!.textZh);

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        if (result.isSuccess) {
          _analysis = result.data;
        } else if (result.isOffline) {
          _analysisError = 'offline';
        } else {
          _analysisError = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Card' : (_card?.displayTitle ?? 'Card Detail'),
        ),
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelEditing,
              )
            : null,
        actions: [
          if (_card != null && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit card',
              onPressed: _startEditing,
            ),
          if (_card != null && _isEditing)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save changes',
              onPressed: _saveEdit,
            ),
          if (_card != null && !_isEditing)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share coming soon')),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOffline ? Icons.wifi_off : Icons.error_outline,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCard,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_card == null) {
      return const Center(child: Text('Card not found'));
    }

    return RefreshIndicator(
      onRefresh: _loadCard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title section
            if (_isEditing) ...[
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'Give this card a title...',
                ),
              ),
              const SizedBox(height: 16),
            ] else if (_card!.displayTitle != null) ...[
              Text(
                _card!.displayTitle!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Full Chinese text
            _buildChineseTextSection(),

            const SizedBox(height: 24),

            // Metadata
            _buildMetadataSection(),

            const SizedBox(height: 24),

            // Analysis section (online-only)
            _buildAnalysisSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildChineseTextSection() {
    if (_isEditing) {
      return TextField(
        controller: _textController,
        maxLines: null,
        minLines: 5,
        style: const TextStyle(fontSize: 18, height: 1.8),
        decoration: InputDecoration(
          labelText: 'Chinese Text',
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selection mode toggle
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isSelectingText = !_isSelectingText;
                  if (!_isSelectingText) _selectedText = null;
                });
              },
              icon: Icon(
                _isSelectingText ? Icons.close : Icons.select_all,
                size: 18,
              ),
              label: Text(
                _isSelectingText ? 'Exit Selection' : 'Select Text',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        // Text container
        GestureDetector(
          onLongPressStart: _isSelectingText
              ? null
              : (details) =>
                    _showTextContextMenu(details.globalPosition, _card!.textZh),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isSelectingText
                  ? Colors.blue.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isSelectingText
                    ? Colors.blue.shade300
                    : Colors.grey.shade300,
              ),
            ),
            child: _isSelectingText
                ? SelectableText(
                    _card!.textZh,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.8,
                      color: Colors.black87,
                    ),
                    onSelectionChanged: (selection, cause) {
                      final text = _card!.textZh;
                      if (selection.start < selection.end) {
                        final selected = text.substring(
                          selection.start,
                          selection.end,
                        );
                        setState(() => _selectedText = selected);
                      }
                    },
                  )
                : isOnline
                ? AnnotatedChineseText(
                    key: ValueKey(_card!.textZh),
                    text: _card!.textZh,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.8,
                      color: Colors.black87,
                    ),
                  )
                : SelectableText(
                    _card!.textZh,
                    style: const TextStyle(fontSize: 18, height: 1.8),
                  ),
          ),
        ),
        // Selection indicator
        if (_selectedText != null && _selectedText!.isNotEmpty)
          _buildSelectionBanner(),
      ],
    );
  }

  Widget _buildSelectionBanner() {
    final cs = Theme.of(context).colorScheme;
    final preview = _selectedText!.length > 60
        ? '${_selectedText!.substring(0, 60)}…'
        : _selectedText!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.format_quote, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preview,
              style: TextStyle(
                fontSize: 13,
                color: cs.onPrimaryContainer,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _selectedText = null),
            child: Icon(Icons.close, size: 16, color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    return Row(
      children: [
        Icon(
          _card!.source == 'ocr' ? Icons.camera_alt : Icons.edit,
          size: 16,
          color: Colors.grey,
        ),
        Text(
          'Created ${_formatDateOnly(_card!.createdAt)}',
          style: const TextStyle(color: Colors.grey),
        ),
        if (_card!.updatedAt != null) ...[
          const Text(' • ', style: TextStyle(color: Colors.grey)),
          Text(
            'Updated ${_formatDateOnly(_card!.updatedAt!)}',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _buildAnalysisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.analytics_outlined),
            const SizedBox(width: 8),
            Text(
              'Analysis',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (!isOnline)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Online only',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _buildAnalysisToolsGrid(),
      ],
    );
  }

  /// Grid of buttons for every API feature — navigates to dedicated pages.
  Widget _buildAnalysisToolsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI Tools',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            _toolButton(
              icon: Icons.translate,
              label: 'Translate',
              subtitle: _hasSelection ? 'selected text' : null,
              color: Colors.blue,
              onTap: () =>
                  _openPage(TranslationResultPage(text: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.summarize,
              label: 'Summarize',
              subtitle: _hasSelection ? 'selected text' : null,
              color: Colors.purple,
              onTap: () => _openPage(SummarizationPage(text: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.spellcheck,
              label: 'Word Analysis',
              subtitle: _hasSelection ? 'selected text' : null,
              color: Colors.teal,
              onTap: () =>
                  _openPage(WordAnalysisPage(cardText: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.psychology,
              label: 'Grammar',
              subtitle: _hasSelection ? 'selected text' : null,
              color: Colors.indigo,
              onTap: () => _openPage(
                LinguisticAnalysisPage(
                  fullText: _card!.textZh,
                  selectedText: _selectedText,
                ),
              ),
            ),
            _toolButton(
              icon: Icons.quiz,
              label: 'Questions',
              subtitle: _hasSelection ? 'selected text' : null,
              color: Colors.orange,
              onTap: () => _openPage(QuestionsPage(text: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.menu_book,
              label: 'Books',
              color: Colors.brown,
              onTap: () => _openPage(BooksPage(cardText: _card!.textZh)),
            ),
          ],
        ),
      ],
    );
  }

  /// The text to pass to tools that support subset selection.
  String get _effectiveText => _selectedText ?? _card!.textZh;

  /// Whether the user has an active text selection.
  bool get _hasSelection => _selectedText != null && _selectedText!.isNotEmpty;

  Widget _toolButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final enabled = isOnline;
    return Material(
      color: enabled ? color.withValues(alpha: 0.08) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: enabled ? color : Colors.grey, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled ? color : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: enabled
                              ? color.withValues(alpha: 0.7)
                              : Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: enabled
                    ? color.withValues(alpha: 0.5)
                    : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value),
      ],
    );
  }

  String _formatDateOnly(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  //  Long-press context menu

  void _showTextContextMenu(Offset position, String text) async {
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
