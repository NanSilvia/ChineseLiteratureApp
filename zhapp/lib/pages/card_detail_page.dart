import 'dart:ui' show DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../services/card_notifier.dart';
import '../services/connectivity_service.dart';
import '../widgets/annotated_chinese_text.dart';
import 'translation_result_page.dart';
import 'summarization_page.dart';
import 'word_analysis_page.dart';
import 'linguistic_analysis_page.dart';
import 'question_setup_page.dart';
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

  // Tracks what is currently selected inside the SelectionArea
  String? _selectedText;

  final ScrollController _scrollController = ScrollController();
  // Used to measure the visible viewport so we know when handles scroll off-screen.
  final GlobalKey _scrollViewKey = GlobalKey();
  // Per-handle visibility notifiers — toggled as each handle scrolls in/out of
  // the viewport. Backed by _HidableHandleControls so the overlay rebuilds
  // without clearing the selection.
  final ValueNotifier<bool> _startHandleVisible = ValueNotifier(true);
  final ValueNotifier<bool> _endHandleVisible = ValueNotifier(true);
  late final _HidableHandleControls _selectionControls = _HidableHandleControls(
    startVisible: _startHandleVisible,
    endVisible: _endHandleVisible,
  );
  // We own our context-menu overlay completely so we can destroy and
  // recreate it with fresh anchor positions after a scroll or handle drag.
  SelectableRegionState? _savedSelectableState;
  OverlayEntry? _menuEntry;
  bool _isScrolling = false;
  // Anchors used when _menuEntry was last built — compared on each
  // contextMenuBuilder call to detect handle-drag repositioning.
  Offset? _lastMenuAnchorAbove;
  Offset? _lastMenuAnchorBelow;

  String get _effectiveText =>
      (_selectedText?.isNotEmpty ?? false) ? _selectedText! : _card!.textZh;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  @override
  void dispose() {
    _removeMenu();
    _startHandleVisible.dispose();
    _endHandleVisible.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Updates per-handle visibility based on whether each handle lies inside
  /// the scroll-view's current viewport rect. Handles that scroll into the
  /// AppBar zone (above the scroll view's top edge) are also hidden —
  /// the viewport rect starts below the AppBar so they naturally vanish.
  void _updateHandleVisibility() {
    final state = _savedSelectableState;
    if (state == null || _selectedText == null) return;

    final RenderBox? box =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Rect viewportRect = box.localToGlobal(Offset.zero) & box.size;
    final anchors = state.contextMenuAnchors;
    // `primaryAnchor` is the *toolbar* position (above the selection).
    // The start handle sits roughly handleOffset pixels below it, at the
    // actual top of the selected text.
    // `secondaryAnchor` is the fallback toolbar position (below the selection).
    // The end handle sits roughly handleOffset pixels above it.
    const double handleOffset = 28;
    final double startY = anchors.primaryAnchor.dy + handleOffset;
    final double endY =
        (anchors.secondaryAnchor ?? anchors.primaryAnchor).dy - handleOffset;

    _startHandleVisible.value =
        startY >= viewportRect.top && startY <= viewportRect.bottom;
    _endHandleVisible.value =
        endY >= viewportRect.top && endY <= viewportRect.bottom;
  }

  void _removeMenu() {
    _menuEntry?.remove();
    _menuEntry?.dispose();
    _menuEntry = null;
    _lastMenuAnchorAbove = null;
    _lastMenuAnchorBelow = null;
  }

  void _recreateMenu() {
    _removeMenu();
    final state = _savedSelectableState;
    if (!mounted || _selectedText == null || state == null) return;

    // The notifiers are kept up-to-date by _updateHandleVisibility() called on
    // every ScrollUpdateNotification. On first selection (no scroll has fired)
    // they default to true, so the menu always shows. We only skip it when a
    // prior scroll explicitly confirmed both handles are off-screen.
    if (!_startHandleVisible.value && !_endHandleVisible.value) return;

    // Read anchors fresh — localToGlobal is called inside this getter,
    // so it reflects the layout that is current at call time.
    final anchors = state.contextMenuAnchors;
    final primary = anchors.primaryAnchor;
    final secondary = anchors.secondaryAnchor;
    _lastMenuAnchorAbove = primary;
    _lastMenuAnchorBelow = secondary ?? primary;
    const double handleOffset = 28;

    final effectiveText = (_selectedText?.isNotEmpty ?? false)
        ? _selectedText!
        : _card!.textZh;

    final appItems = isOnline
        ? <({IconData icon, String label, VoidCallback onTap})>[
            (
              icon: Icons.translate,
              label: 'Translate',
              onTap: () {
                _removeMenu();
                _openPage(TranslationResultPage(text: effectiveText));
              },
            ),
            (
              icon: Icons.summarize,
              label: 'Summarize',
              onTap: () {
                _removeMenu();
                _openPage(SummarizationPage(text: effectiveText));
              },
            ),
            (
              icon: Icons.spellcheck,
              label: 'Word Analysis',
              onTap: () {
                _removeMenu();
                _openPage(WordAnalysisPage(cardText: effectiveText));
              },
            ),
            (
              icon: Icons.psychology,
              label: 'Grammar',
              onTap: () {
                _removeMenu();
                _openPage(
                  LinguisticAnalysisPage(
                    fullText: _card!.textZh,
                    selectedText: _selectedText,
                  ),
                );
              },
            ),
            (
              icon: Icons.quiz,
              label: 'Questions',
              onTap: () {
                _removeMenu();
                _openPage(QuestionSetupPage(text: effectiveText, cardId: widget.cardId));
              },
            ),
          ]
        : <({IconData icon, String label, VoidCallback onTap})>[];

    Rect? cutoutRect;
    for (final f in MediaQuery.of(context).displayFeatures) {
      if (f.type == DisplayFeatureType.cutout) {
        cutoutRect = f.bounds;
        break;
      }
    }

    _menuEntry = OverlayEntry(
      builder: (_) => CustomSingleChildLayout(
        delegate: _CutoutAwareMenuDelegate(
          anchorAbove: primary - const Offset(0, handleOffset),
          anchorBelow: (secondary ?? primary) + const Offset(0, handleOffset),
          cutout: cutoutRect,
        ),
        child: _SelectionContextMenu(
          appItems: appItems,
          systemItems: state.contextMenuButtonItems,
        ),
      ),
    );
    Overlay.of(context).insert(_menuEntry!);
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
      });
      CardNotifier().notifyCardsChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Card updated.')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to update card')),
        );
      }
    }
  }

  Future<void> _shareCardText() async {
    if (_card == null) return;

    final title = _card!.title?.trim();
    final text = _card!.textZh.trim();
    final shareText = [
      if (title != null && title.isNotEmpty) title,
      text,
    ].join('\n\n');

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: _card!.displayTitle),
    );
  }

  @override
  void onConnectivityChanged(bool isOnline) {}

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
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Card' : ""),
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
              tooltip: 'Share card text',
              onPressed: _shareCardText,
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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // Ignore sub-pixel nudges — pressing a menu button can produce a
          // tiny scroll delta that would otherwise kill the menu before the
          // tap registers.
          final delta = notification.scrollDelta?.abs() ?? 0;
          if (delta > 4.0) {
            _isScrolling = true;
            _removeMenu();
            _updateHandleVisibility();
          }
        } else if (notification is ScrollEndNotification) {
          if (_isScrolling) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _isScrolling = false;
              _recreateMenu();
            });
          }
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _loadCard,
        child: SingleChildScrollView(
          key: _scrollViewKey,
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: _isEditing
              ? EdgeInsets.all(16)
              : EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
              ] else if (_card!.title != null && _card!.title!.isNotEmpty) ...[
                Text(
                  _card!.title!,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
              ],
              // Full Chinese text
              _buildChineseTextSection(),

              const SizedBox(height: 8),
              // Metadata
              _buildMetadataSection(),

              // Analysis section (online-only)
              _buildAnalysisSection(),
            ],
          ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SelectionArea(
        selectionControls: _selectionControls,
        onSelectionChanged: (content) {
          setState(
            () => _selectedText = (content?.plainText.isNotEmpty ?? false)
                ? content!.plainText
                : null,
          );
          if (content == null || content.plainText.isEmpty) _removeMenu();
        },
        contextMenuBuilder: (context, selectableRegionState) {
          // Save state so _recreateMenu() can use it after a scroll.
          // Return SizedBox.shrink() — we own the overlay via _menuEntry.
          _savedSelectableState = selectableRegionState;
          // Only create the menu if it doesn't exist yet. This prevents
          // destroying + recreating the OverlayEntry on every rebuild
          // (e.g. from setState in onSelectionChanged), which would reset
          // hit-testing mid-tap and make buttons nearly un-tappable.
          if (!_isScrolling) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _isScrolling) return;
              final anchors = _savedSelectableState?.contextMenuAnchors;
              if (anchors == null) return;
              final newAbove = anchors.primaryAnchor;
              final newBelow = anchors.secondaryAnchor ?? anchors.primaryAnchor;
              final anchorsMoved = newAbove != _lastMenuAnchorAbove ||
                  newBelow != _lastMenuAnchorBelow;
              if (_menuEntry == null || anchorsMoved) _recreateMenu();
            });
          }
          return const SizedBox.shrink();
        },
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
            : Text(
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
          _card!.source == 'ocr' ? Icons.create : Icons.edit,
          size: 12,
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
              color: Colors.blue,
              onTap: () =>
                  _openPage(TranslationResultPage(text: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.summarize,
              label: 'Summarize',
              color: Colors.purple,
              onTap: () => _openPage(SummarizationPage(text: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.spellcheck,
              label: 'Word Analysis',
              color: Colors.teal,
              onTap: () =>
                  _openPage(WordAnalysisPage(cardText: _effectiveText)),
            ),
            _toolButton(
              icon: Icons.psychology,
              label: 'Grammar',
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
              color: Colors.orange,
              onTap: () => _openPage(QuestionSetupPage(text: _effectiveText, cardId: widget.cardId)),
            ),
            _toolButton(
              icon: Icons.menu_book,
              label: 'Books',
              color: Colors.brown,
              onTap: () => _openPage(BooksPage(cardText: _effectiveText)),
            ),
          ],
        ),
      ],
    );
  }

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

  String _formatDateOnly(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Selection controls that hide individual handles via ValueNotifier without
// clearing the selection. The AppBar naturally occludes handles that scroll
// above the scroll view's top edge because the notifiers are toggled based on
// the viewport rect (which starts below the AppBar).
class _HidableHandleControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {
  _HidableHandleControls({
    required this.startVisible,
    required this.endVisible,
  });

  final ValueNotifier<bool> startVisible;
  final ValueNotifier<bool> endVisible;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    // collapsed = single cursor; treat it like the start handle.
    final notifier = type == TextSelectionHandleType.right
        ? endVisible
        : startVisible;
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (ctx, show, _) {
        if (!show) return const SizedBox.shrink();
        return super.buildHandle(ctx, type, textLineHeight, onTap);
      },
    );
  }
}

//  Cutout-aware context menu layout delegate

class _CutoutAwareMenuDelegate extends SingleChildLayoutDelegate {
  _CutoutAwareMenuDelegate({
    required this.anchorAbove,
    required this.anchorBelow,
    this.cutout,
  });

  final Offset anchorAbove;
  final Offset anchorBelow;
  final Rect? cutout;

  static const double _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double menuLeft = (anchorAbove.dx - childSize.width / 2).clamp(
      _margin,
      size.width - childSize.width - _margin,
    );
    final double menuTop = anchorAbove.dy - childSize.height;

    // Check if showing above would overlap the cutout rect.
    bool wouldOverlapCutout = false;
    if (cutout != null) {
      final menuRect = Rect.fromLTWH(
        menuLeft,
        menuTop,
        childSize.width,
        childSize.height,
      );
      wouldOverlapCutout = menuRect.overlaps(cutout!);
    }

    // Show above if there is enough screen space AND no cutout overlap.
    if (menuTop >= _margin && !wouldOverlapCutout) {
      return Offset(menuLeft, menuTop);
    }

    // Otherwise show below.
    final double belowLeft = (anchorBelow.dx - childSize.width / 2).clamp(
      _margin,
      size.width - childSize.width - _margin,
    );
    final double belowTop = anchorBelow.dy.clamp(
      _margin,
      size.height - childSize.height - _margin,
    );
    return Offset(belowLeft, belowTop);
  }

  @override
  bool shouldRelayout(_CutoutAwareMenuDelegate oldDelegate) =>
      anchorAbove != oldDelegate.anchorAbove ||
      anchorBelow != oldDelegate.anchorBelow ||
      cutout != oldDelegate.cutout;
}

//  Selection context menu

class _SelectionContextMenu extends StatefulWidget {
  final List<({IconData icon, String label, VoidCallback onTap})> appItems;
  final List<ContextMenuButtonItem> systemItems;

  const _SelectionContextMenu({
    required this.appItems,
    required this.systemItems,
  });

  @override
  State<_SelectionContextMenu> createState() => _SelectionContextMenuState();
}

class _SelectionContextMenuState extends State<_SelectionContextMenu> {
  bool _showMore = false;

  static String _labelFor(ContextMenuButtonItem item) {
    if (item.label != null && item.label!.isNotEmpty) return item.label!;
    switch (item.type) {
      case ContextMenuButtonType.copy:
        return 'Copy';
      case ContextMenuButtonType.cut:
        return 'Cut';
      case ContextMenuButtonType.paste:
        return 'Paste';
      case ContextMenuButtonType.selectAll:
        return 'Select All';
      case ContextMenuButtonType.share:
        return 'Share';
      case ContextMenuButtonType.delete:
        return 'Delete';
      default:
        return 'More';
    }
  }

  static IconData _iconFor(ContextMenuButtonItem item) {
    switch (item.type) {
      case ContextMenuButtonType.copy:
        return Icons.copy_outlined;
      case ContextMenuButtonType.cut:
        return Icons.cut_outlined;
      case ContextMenuButtonType.paste:
        return Icons.paste_outlined;
      case ContextMenuButtonType.selectAll:
        return Icons.select_all_outlined;
      case ContextMenuButtonType.share:
        return Icons.share_outlined;
      case ContextMenuButtonType.delete:
        return Icons.delete_outline;
      default:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final copyItem = widget.systemItems
        .where((i) => i.type == ContextMenuButtonType.copy)
        .firstOrNull;
    final shareItem = widget.systemItems
        .where((i) => i.type == ContextMenuButtonType.share)
        .firstOrNull;
    final extraItems = widget.systemItems
        .where(
          (i) =>
              i.type != ContextMenuButtonType.copy &&
              i.type != ContextMenuButtonType.share,
        )
        .toList();

    final hasSystemRow =
        copyItem != null || shareItem != null || extraItems.isNotEmpty;

    return Material(
      elevation: 24,
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scrollable app-specific + optional "More" system items
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in widget.appItems)
                        _AppMenuItem(item: item),
                      if (_showMore && extraItems.isNotEmpty) ...[
                        if (widget.appItems.isNotEmpty)
                          Divider(height: 1, color: colorScheme.outlineVariant),
                        for (final item in extraItems)
                          _SystemMenuItem(
                            item: item,
                            label: _labelFor(item),
                            icon: _iconFor(item),
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // Copy · Share · More bottom bar
              if (hasSystemRow) ...[
                Divider(height: 1, color: colorScheme.outlineVariant),
                IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (copyItem != null)
                        _BottomRowButton(
                          icon: Icons.copy_outlined,
                          label: 'Copy',
                          onTap: copyItem.onPressed,
                        ),
                      if (copyItem != null &&
                          (shareItem != null || extraItems.isNotEmpty))
                        VerticalDivider(
                          width: 1,
                          color: colorScheme.outlineVariant,
                        ),
                      if (shareItem != null)
                        _BottomRowButton(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: shareItem.onPressed,
                        ),
                      if (shareItem != null && extraItems.isNotEmpty)
                        VerticalDivider(
                          width: 1,
                          color: colorScheme.outlineVariant,
                        ),
                      if (extraItems.isNotEmpty)
                        _BottomRowButton(
                          icon: _showMore
                              ? Icons.expand_less
                              : Icons.more_horiz,
                          label: 'More',
                          onTap: () => setState(() => _showMore = !_showMore),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMenuItem extends StatelessWidget {
  final ({IconData icon, String label, VoidCallback onTap}) item;
  const _AppMenuItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 10),
            Text(
              item.label,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMenuItem extends StatelessWidget {
  final ContextMenuButtonItem item;
  final String label;
  final IconData icon;
  const _SystemMenuItem({
    required this.item,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: item.onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomRowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _BottomRowButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
