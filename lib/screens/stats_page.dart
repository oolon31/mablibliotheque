import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import '../state/library.dart';
import '../widgets/cover.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final owned = library.owned.toList();
    final theme = Theme.of(context);
    final wishCount = library.items.length - owned.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            _Tile(value: owned.length, label: 'dans la collection'),
            const SizedBox(width: 12),
            _Tile(value: library.loans.length, label: 'prêtés'),
            const SizedBox(width: 12),
            _Tile(value: wishCount, label: 'envies'),
          ],
        ),
        const SizedBox(height: 24),
        Text('Par type', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final t in ItemType.values)
          _Bar(
            icon: t.icon,
            color: typeColor(context, t),
            label: t.plural,
            count: owned.where((i) => i.type == t).length,
            total: owned.length,
          ),
        ..._top(context, 'Genres favoris', owned.map((i) => i.genre)),
        ..._top(context, 'Artistes et auteurs les plus présents', owned.map((i) => i.creator)),
      ],
    );
  }

  List<Widget> _top(BuildContext context, String title, Iterable<String> values) {
    final counts = <String, int>{};
    for (final v in values) {
      final k = v.trim();
      if (k.isNotEmpty) counts[k] = (counts[k] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final max = top.first.value;
    return [
      const SizedBox(height: 24),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final e in top) _Bar(label: e.key, count: e.value, total: max, color: Theme.of(context).colorScheme.primary),
    ];
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text('$value', style: theme.textTheme.headlineMedium),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.count, required this.total, required this.color, this.icon});

  final String label;
  final int count;
  final int total;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 6)],
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('$count', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
