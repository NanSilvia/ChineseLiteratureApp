import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../widgets/glowing_title_field.dart';

// Page shown when text is shared into the app from an external source
// (e.g. selected text in a browser). Lets the user review and save it as a card.
class SharedTextPage extends StatefulWidget {
  final String sharedText;

  const SharedTextPage({super.key, required this.sharedText});

  @override
  State<SharedTextPage> createState() => _SharedTextPageState();
}

class _SharedTextPageState extends State<SharedTextPage> {
  final ApiService _api = ApiService();
  late final TextEditingController _textController;
  final TextEditingController _titleController = TextEditingController();
  bool _isSaving = false;
  bool _isGeneratingTitle = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.sharedText.trim());
    // Auto-generate a title from the shared text immediately
    _generateTitle(widget.sharedText.trim());
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _generateTitle(String text) async {
    if (text.isEmpty) return;
    setState(() => _isGeneratingTitle = true);
    final result = await _api.generateCardTitle(text);
    if (!mounted) return;
    setState(() {
      _isGeneratingTitle = false;
      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        _titleController.text = result.data!;
      }
    });
  }

  Future<void> _saveCard() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await _api.createCard(
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      textZh: text,
      source: 'shared',
    );

    if (!mounted) return;

    if (result.isSuccess) {
      CardNotifier().notifyCardsChanged();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Card saved to library')));
    } else {
      setState(() {
        _isSaving = false;
        _error = result.error ?? 'Failed to save card';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save as Card'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveCard,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlowingTitleField(
              controller: _titleController,
              isGenerating: _isGeneratingTitle,
              onRegenerate: _isGeneratingTitle
                  ? null
                  : () => _generateTitle(_textController.text.trim()),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  alignLabelWithHint: true,
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
