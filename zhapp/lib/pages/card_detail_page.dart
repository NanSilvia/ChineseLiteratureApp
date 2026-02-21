import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../services/connectivity_service.dart';
import '../widgets/annotated_chinese_text.dart';

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

    return GestureDetector(
      onLongPressStart: (details) =>
          _showTextContextMenu(details.globalPosition, _card!.textZh),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: isOnline
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
        const SizedBox(height: 12),
        _buildAnalysisContent(),
      ],
    );
  }

  Widget _buildAnalysisContent() {
    if (isOffline && _analysis == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Analysis requires an internet connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: isOnline ? _loadAnalysis : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isAnalyzing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Analyzing text...'),
          ],
        ),
      );
    }

    if (_analysisError != null && _analysisError != 'offline') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          children: [
            Text(_analysisError!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadAnalysis,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_analysis != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnalysisRow('Characters', '${_analysis!['characters']}'),
            const SizedBox(height: 8),
            _buildAnalysisRow('Words', '${_analysis!['words']}'),
            const SizedBox(height: 12),
            Text(
              _analysis!['analysis'] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text('No analysis available'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: isOnline ? _loadAnalysis : null,
            icon: const Icon(Icons.analytics),
            label: const Text('Analyze'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value),
      ],
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateOnly(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // ──────────── Long-press context menu ────────────

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
