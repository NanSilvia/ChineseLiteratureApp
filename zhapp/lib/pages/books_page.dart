import 'package:flutter/material.dart';
import '../models/translation_models.dart';
import '../services/translation_api_service.dart';
import '../services/connectivity_service.dart';

// Full-screen page for book search, recommendations, similar-difficulty,
// and text research — all book-related endpoints in one tabbed view.
class BooksPage extends StatefulWidget {
  final String cardText;

  const BooksPage({super.key, required this.cardText});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage>
    with ConnectivityAware, SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Books & Reading'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (bypass cache)',
            onPressed: () => _refreshNotifier.value++,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Search'),
            Tab(icon: Icon(Icons.recommend), text: 'Recommend'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Difficulty'),
            Tab(icon: Icon(Icons.science), text: 'Research'),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BookSearchTab(
                  cardText: widget.cardText,
                  refreshNotifier: _refreshNotifier,
                ),
                _BookRecommendTab(
                  cardText: widget.cardText,
                  refreshNotifier: _refreshNotifier,
                ),
                _DifficultyTab(
                  cardText: widget.cardText,
                  refreshNotifier: _refreshNotifier,
                ),
                _ResearchTab(
                  cardText: widget.cardText,
                  refreshNotifier: _refreshNotifier,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//
//  TAB 1: Book Search
//

class _BookSearchTab extends StatefulWidget {
  final String cardText;
  final ValueNotifier<int> refreshNotifier;
  const _BookSearchTab({required this.cardText, required this.refreshNotifier});

  @override
  State<_BookSearchTab> createState() => _BookSearchTabState();
}

class _BookSearchTabState extends State<_BookSearchTab>
    with AutomaticKeepAliveClientMixin {
  final TranslationApiService _api = TranslationApiService();
  final TextEditingController _queryController = TextEditingController();

  BookSearchResponse? _result;
  bool _isLoading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onRefresh);
    _queryController.dispose();
    super.dispose();
  }

  void _onRefresh() {
    if (_queryController.text.trim().isNotEmpty) {
      _search(forceRefresh: true);
    }
  }

  Future<void> _search({bool forceRefresh = false}) async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.searchBooks(q, forceRefresh: forceRefresh);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search books',
                    hintText: 'Title, author, ISBN…',
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _search,
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _result == null
              ? const Center(
                  child: Text(
                    'Search for books above.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _result!.results.isEmpty
              ? const Center(child: Text('No books found.'))
              : _buildBookList(_result!.results),
        ),
      ],
    );
  }

  Widget _buildBookList(List<BookSummary> books) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: books.length,
      itemBuilder: (context, i) => _BookCard(book: books[i]),
    );
  }
}

//
//  TAB 2: Book Recommendations
//

class _BookRecommendTab extends StatefulWidget {
  final String cardText;
  final ValueNotifier<int> refreshNotifier;
  const _BookRecommendTab({
    required this.cardText,
    required this.refreshNotifier,
  });

  @override
  State<_BookRecommendTab> createState() => _BookRecommendTabState();
}

class _BookRecommendTabState extends State<_BookRecommendTab>
    with AutomaticKeepAliveClientMixin {
  final TranslationApiService _api = TranslationApiService();

  // Uses researchText (translates Chinese → English first) so keyword
  // extraction works on the translated text instead of raw Chinese.
  TextResearchResponse? _result;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load(forceRefresh: true);

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.researchText(
      widget.cardText,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Getting recommendations…'),
          ],
        ),
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

    if (_result == null || _result!.bookRecommendations.isEmpty) {
      return const Center(child: Text('No recommendations found.'));
    }

    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Keywords
        if (_result!.keywords.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _result!.keywords
                .map(
                  (k) => Chip(
                    label: Text(k, style: const TextStyle(fontSize: 12)),
                    backgroundColor: cs.secondaryContainer,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            '${_result!.numBooksFound} books found',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const Divider(),
        ],
        ..._result!.bookRecommendations.map((b) => _BookCard(book: b)),
      ],
    );
  }
}

//
//  TAB 3: Text Difficulty + Similar Texts
//

class _DifficultyTab extends StatefulWidget {
  final String cardText;
  final ValueNotifier<int> refreshNotifier;
  const _DifficultyTab({required this.cardText, required this.refreshNotifier});

  @override
  State<_DifficultyTab> createState() => _DifficultyTabState();
}

class _DifficultyTabState extends State<_DifficultyTab>
    with AutomaticKeepAliveClientMixin {
  final TranslationApiService _api = TranslationApiService();

  TextDifficultyResponse? _result;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load(forceRefresh: true);

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.findSimilarDifficulty(
      widget.cardText,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Analyzing difficulty…'),
          ],
        ),
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

    if (_result == null) {
      return const Center(child: Text('No data.'));
    }

    final m = _result!.difficultyMetrics;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Difficulty overview
          Text(
            'Difficulty Analysis',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _DifficultyGauge(metrics: m),

          const SizedBox(height: 16),

          // Metrics grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip('Characters', '${m.characterCount}'),
              _metricChip('Unique', '${m.uniqueCharacters}'),
              _metricChip('Words', '${m.wordCount}'),
              _metricChip('Avg Length', m.avgWordLength.toStringAsFixed(1)),
              if (m.hskLevel != null) _metricChip('HSK Level', '${m.hskLevel}'),
              if (m.estimatedStudyHours != null)
                _metricChip('Study Hrs', '${m.estimatedStudyHours}'),
            ],
          ),

          if (m.vocabularyComplexity != null) ...[
            const SizedBox(height: 12),
            Text(
              'Vocabulary: ${m.vocabularyComplexity}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
          if (m.grammarComplexity != null) ...[
            const SizedBox(height: 4),
            Text(
              'Grammar: ${m.grammarComplexity}',
              style: const TextStyle(fontSize: 14),
            ),
          ],

          // Similar texts
          if (_result!.similarTexts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Similar Difficulty Texts (${_result!.numFound})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._result!.similarTexts.map(
              (t) => _SimilarTextBookCard(similarText: t),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) =>
      Chip(label: Text('$label: $value', style: const TextStyle(fontSize: 13)));
}

// Simple gauge showing difficulty level and score.
class _DifficultyGauge extends StatelessWidget {
  final TextDifficultyMetrics metrics;
  const _DifficultyGauge({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _color(metrics.complexityScore);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: metrics.complexityScore / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                ),
                Center(
                  child: Text(
                    '${metrics.complexityScore.round()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metrics.difficultyLevel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (metrics.hskLevel != null)
                  Text(
                    'HSK Level ${metrics.hskLevel}',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _color(double score) {
    if (score < 25) return Colors.green;
    if (score < 50) return Colors.orange;
    if (score < 75) return Colors.deepOrange;
    return Colors.red;
  }
}

// Card for similar-difficulty texts — mirrors [_BookCard] layout but adds a
// difficulty score badge. Tapping opens the same detail bottom sheet.
class _SimilarTextBookCard extends StatelessWidget {
  final SimilarTextResult similarText;
  const _SimilarTextBookCard({required this.similarText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dm = similarText.difficultyMetrics;

    // Convert to BookSummary so we can reuse the detail sheet.
    final bookSummary = BookSummary(
      title: similarText.title,
      authors: similarText.authors,
      openlibraryKey: similarText.openlibraryKey,
      language: similarText.language,
      subjects: similarText.subjects,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: similarText.openlibraryKey.isNotEmpty
            ? () => _BookCard.showBookDetail(context, bookSummary)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Difficulty score circle
              CircleAvatar(
                radius: 22,
                backgroundColor: _difficultyColor(dm.complexityScore),
                child: Text(
                  dm.complexityScore.round().toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      similarText.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (similarText.authors.isNotEmpty)
                      Text(
                        similarText.authors.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        Text(
                          dm.difficultyLevel,
                          style: TextStyle(
                            fontSize: 12,
                            color: _difficultyColor(dm.complexityScore),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (dm.hskLevel != null)
                          Text(
                            'HSK ${dm.hskLevel}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (similarText.language.isNotEmpty)
                          Text(
                            similarText.language.join(', '),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Color _difficultyColor(double score) {
    if (score < 25) return Colors.green;
    if (score < 50) return Colors.orange;
    if (score < 75) return Colors.deepOrange;
    return Colors.red;
  }
}

//
//  TAB 4: Research (Translate + Books)
//

class _ResearchTab extends StatefulWidget {
  final String cardText;
  final ValueNotifier<int> refreshNotifier;
  const _ResearchTab({required this.cardText, required this.refreshNotifier});

  @override
  State<_ResearchTab> createState() => _ResearchTabState();
}

class _ResearchTabState extends State<_ResearchTab>
    with AutomaticKeepAliveClientMixin {
  final TranslationApiService _api = TranslationApiService();

  TextResearchResponse? _result;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier.addListener(_onRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _load(forceRefresh: true);

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _api.researchText(
      widget.cardText,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess) {
          _result = result.data;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Researching text…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
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

    if (_result == null) {
      return const Center(child: Text('No data'));
    }

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keywords
          if (_result!.keywords.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _result!.keywords
                  .map(
                    (k) => Chip(
                      label: Text(k, style: const TextStyle(fontSize: 12)),
                      backgroundColor: cs.tertiaryContainer,
                    ),
                  )
                  .toList(),
            ),
          ],

          // Book recommendations
          if (_result!.bookRecommendations.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Related Books (${_result!.numBooksFound})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._result!.bookRecommendations.map((b) => _BookCard(book: b)),
          ],
        ],
      ),
    );
  }
}

//
//  Shared: BookCard widget
//

class _BookCard extends StatelessWidget {
  final BookSummary book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: book.openlibraryKey != null
            ? () => showBookDetail(context, book)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Cover
              if (book.coverUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    book.coverUrl!,
                    width: 50,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 50,
                      height: 70,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.book, color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 70,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.book, color: Colors.grey),
                ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (book.authors.isNotEmpty)
                      Text(
                        book.authors.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (book.firstPublishYear != null)
                          Text(
                            '${book.firstPublishYear}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (book.numberOfPages != null)
                          Text(
                            '${book.numberOfPages} pp',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (book.language.isNotEmpty)
                          Text(
                            book.language.join(', '),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (book.hasFulltext)
                const Tooltip(
                  message: 'Full text available',
                  child: Icon(Icons.menu_book, size: 18, color: Colors.green),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void showBookDetail(BuildContext context, BookSummary book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (book.coverUrl != null)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          book.coverUrl!,
                          height: 160,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (book.authors.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.authors.join(', '),
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (book.firstPublishYear != null)
                    _detailRow_('First Published', '${book.firstPublishYear}'),
                  if (book.numberOfPages != null)
                    _detailRow_('Pages', '${book.numberOfPages}'),
                  if (book.isbn != null) _detailRow_('ISBN', book.isbn!),
                  if (book.publishers.isNotEmpty)
                    _detailRow_('Publishers', book.publishers.join(', ')),
                  if (book.language.isNotEmpty)
                    _detailRow_('Languages', book.language.join(', ')),
                  if (book.subjects.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Subjects',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: book.subjects
                          .take(10)
                          .map(
                            (s) => Chip(
                              label: Text(
                                s,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _detailRow_(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
