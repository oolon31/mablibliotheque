import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import 'cover.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.onTap});

  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final line2 = [
      if (item.creator.isNotEmpty) item.creator else if (item.type.usesPieces && item.genre.isNotEmpty) item.genre,
      if (item.year != null) '${item.year}',
      if (item.type.usesPieces && item.volume.isNotEmpty) '${item.volume} pièces',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              child: Center(child: Cover(item: item, width: 48)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.seriesLabel.isNotEmpty)
                    Text(
                      item.seriesLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: typeColor(context, item.type)),
                    ),
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                  if (line2.isNotEmpty) Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  if (item.isLoaned)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.outbox, size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              (item.loanedTo ?? '').isEmpty ? 'Prêté' : 'Prêté à ${item.loanedTo}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (item.rating > 0) ...[
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item.rating}', style: muted),
                  Icon(Icons.star_rounded, size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Étoiles de notation, cliquables si [onChanged] est fourni.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.onChanged, this.size = 28});

  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating;
        final icon = Icon(filled ? Icons.star_rounded : Icons.star_outline_rounded, color: color, size: size);
        if (onChanged == null) return icon;
        return IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '${i + 1} sur 5',
          // Toucher l'étoile déjà sélectionnée retire la note.
          onPressed: () => onChanged!(rating == i + 1 ? 0 : i + 1),
          icon: icon,
        );
      }),
    );
  }
}
