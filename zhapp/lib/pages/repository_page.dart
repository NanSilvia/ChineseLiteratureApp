import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/folder_model.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import 'card_detail_page.dart';

/// Screen 1: Repository (Main Feed)
/// Shows a single list of all cards sorted most recent -> oldest
/// with category controls for filtering
class RepositoryPage extends StatefulWidget {
  const RepositoryPage({super.key});

  @override
  State<RepositoryPage> createState() => _RepositoryPageState();
}

class _RepositoryPageState extends State<RepositoryPage>
    with ConnectivityAware {
  final ApiService _api = ApiService();

  List<CardModel> _cards = [];
  List<FolderModel> _folders = [];
  int? _selectedFolderId; // null means "All"
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void onConnectivityChanged(bool isOnline) {
    if (isOnline) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load folders and cards in parallel
      final foldersResult = await _api.getFolders();
      final cardsResult = await _api.getCards(folderId: _selectedFolderId);

      if (mounted) {
        setState(() {
          if (foldersResult.isSuccess) {
            _folders = foldersResult.data ?? [];
          }
          if (cardsResult.isSuccess) {
            _cards = cardsResult.data ?? [];
            // Ensure cards are sorted most recent first
            _cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }
          if (!foldersResult.isSuccess || !cardsResult.isSuccess) {
            _error = foldersResult.error ?? cardsResult.error;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onFolderSelected(int? folderId) {
    setState(() {
      _selectedFolderId = folderId;
    });
    _loadData();
  }

  void _openCardDetail(CardModel card) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => CardDetailPage(cardId: card.id!),
          ),
        )
        .then((_) => _loadData()); // Refresh on return
  }

  Future<void> _deleteCard(CardModel card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Are you sure you want to delete this card?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && card.id != null) {
      if (isOffline) {
        _showMessage('You must be online to delete cards.');
        return;
      }

      final result = await _api.deleteCard(card.id!);
      if (result.isSuccess) {
        _showMessage('Card deleted');
        _loadData();
      } else {
        _showMessage(result.error ?? 'Failed to delete card');
      }
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline banner
        const OfflineBanner(),

        // Category filter chips
        _buildCategoryFilter(),

        // Main content
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // "All" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: _selectedFolderId == null,
              onSelected: (_) => _onFolderSelected(null),
            ),
          ),
          // Folder chips
          ..._folders.map(
            (folder) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(folder.name),
                selected: _selectedFolderId == folder.id,
                onSelected: (_) => _onFolderSelected(folder.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _cards.isEmpty) {
      return Center(
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
              isOffline ? 'No saved data available offline.' : _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.library_books_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No cards yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the camera to extract Chinese text',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _cards.length,
        itemBuilder: (context, index) => _buildCardItem(_cards[index]),
      ),
    );
  }

  Widget _buildCardItem(CardModel card) {
    final hasTitle = card.displayTitle != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openCardDetail(card),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title (if exists)
              if (hasTitle) ...[
                Text(
                  card.displayTitle!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],

              // Chinese text preview (first 100 chars)
              Text(
                card.previewTextZh,
                style: TextStyle(fontSize: hasTitle ? 14 : 16, height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 12),

              // Footer with date and delete action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        card.source == 'ocr' ? Icons.camera_alt : Icons.edit,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(card.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.grey,
                    onPressed: () => _deleteCard(card),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
