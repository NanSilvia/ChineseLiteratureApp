import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';

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
        title: Text(_card?.displayTitle ?? 'Card Detail'),
        actions: [
          if (_card != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                // TODO: Implement share functionality
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
            if (_card!.displayTitle != null) ...[
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SelectableText(
        _card!.textZh,
        style: const TextStyle(fontSize: 18, height: 1.8),
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
        const SizedBox(width: 8),
        Text(
          'Created ${_formatDateTime(_card!.createdAt)}',
          style: const TextStyle(color: Colors.grey),
        ),
        if (_card!.updatedAt != null) ...[
          const Text(' • ', style: TextStyle(color: Colors.grey)),
          Text(
            'Updated ${_formatDateTime(_card!.updatedAt!)}',
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
}
