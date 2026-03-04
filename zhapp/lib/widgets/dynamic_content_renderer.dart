import 'package:flutter/material.dart';

/// Recursively renders dynamic JSON-like data as formatted Flutter widgets.
///
/// Handles: String, int, double, bool, null, List, `Map<String, dynamic>`,
/// and nested combinations. Avoids calling `.toString()` on complex structures.
class DynamicContentRenderer extends StatelessWidget {
  final dynamic data;
  final int depth;
  final TextStyle? textStyle;

  const DynamicContentRenderer({
    super.key,
    required this.data,
    this.depth = 0,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return _render(context, data, depth);
  }

  Widget _render(BuildContext context, dynamic value, int level) {
    if (value == null) {
      return Text('—', style: _defaultStyle(context));
    }

    if (value is String) {
      return SelectableText(value, style: textStyle ?? _defaultStyle(context));
    }

    if (value is num || value is bool) {
      return SelectableText(
        value.toString(),
        style: textStyle ?? _defaultStyle(context),
      );
    }

    if (value is List) {
      return _renderList(context, value, level);
    }

    if (value is Map) {
      return _renderMap(context, Map<String, dynamic>.from(value), level);
    }

    // Fallback for unknown types
    return SelectableText(
      value.toString(),
      style: textStyle ?? _defaultStyle(context),
    );
  }

  Widget _renderList(BuildContext context, List items, int level) {
    if (items.isEmpty) {
      return Text(
        'No items',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
          fontSize: 14,
        ),
      );
    }

    // If all items are simple scalars, render as bullet list
    if (items.every((i) => i is String || i is num || i is bool)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.map((entry) {
          return Padding(
            padding: EdgeInsets.only(left: level * 8.0, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    entry.value.toString(),
                    style: _defaultStyle(context),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    // Mixed/complex items — render each with a numbered header
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;

        if (item is Map) {
          return Container(
            margin: EdgeInsets.only(left: level * 8.0, bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${idx + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                _render(context, item, level + 1),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(left: level * 8.0, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${idx + 1}. ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(child: _render(context, item, level + 1)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _renderMap(BuildContext context, Map<String, dynamic> map, int level) {
    if (map.isEmpty) {
      return Text(
        'No data',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
          fontSize: 14,
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: map.entries.map((entry) {
        final label = formatKey(entry.key);
        final value = entry.value;

        // Simple scalar value — render inline as label: value
        if (value is String || value is num || value is bool || value == null) {
          return Padding(
            padding: EdgeInsets.only(left: level * 4.0, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 80),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    value?.toString() ?? '—',
                    style: _defaultStyle(context),
                  ),
                ),
              ],
            ),
          );
        }

        // Complex value (map or list) — render as a titled section
        return Padding(
          padding: EdgeInsets.only(left: level * 4.0, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _render(context, value, level + 1),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  TextStyle _defaultStyle(BuildContext context) {
    return const TextStyle(fontSize: 15, height: 1.5);
  }

  /// Converts snake_case or camelCase keys to human-readable labels.
  static String formatKey(String key) {
    // snake_case → Title Case
    final words = key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'[_\s]+'))
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
    return words;
  }
}
