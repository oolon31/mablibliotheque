import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import '../state/library.dart';
import '../widgets/cover.dart';
import '../widgets/item_tile.dart';
import 'item_form_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final int itemId;

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final item = library.byId(itemId);
    if (item == null) {
      // L'objet vient d'être supprimé.
      return const Scaffold(body: SizedBox.shrink());
    }
    final theme = Theme.of(context);

    final infos = <(String, String)>[
      if (item.creator.isNotEmpty) (item.type.creatorLabel, item.creator),
      if (item.seriesLabel.isNotEmpty) ('Série', item.seriesLabel),
      if (item.year != null) ('Année', '${item.year}'),
      if (item.publisher.isNotEmpty) (item.type.publisherLabel, item.publisher),
      if (item.type.usesPieces && item.volume.isNotEmpty) ('Pièces', item.volume),
      if (item.genre.isNotEmpty) (item.type.genreLabel, item.genre),
      if (item.format.isNotEmpty) (item.type.formatLabel, item.format),
      if (item.condition != null) ('État', item.condition!.label),
      if (item.identifier.isNotEmpty) (item.type.identifierLabel, item.identifier),
      ('Ajouté le', DateFormat.yMMMMd('fr').format(item.createdAt)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(item.type.label),
        actions: [
          if (library.canEdit)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemFormScreen(item: item))),
            ),
          if (library.canEdit)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, library, item),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(child: Cover(item: item, width: 140, radius: 12)),
          const SizedBox(height: 16),
          if (item.seriesLabel.isNotEmpty)
            Text(
              item.seriesLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(color: typeColor(context, item.type)),
            ),
          Text(item.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          if (item.creator.isNotEmpty)
            Text(
              item.creator,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (item.rating > 0) ...[
            const SizedBox(height: 8),
            Center(child: RatingStars(rating: item.rating, size: 24)),
          ],
          const SizedBox(height: 16),
          if (!library.canEdit && item.isLoaned && !item.wishlist)
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.outbox, color: theme.colorScheme.onErrorContainer),
                title: Text('Prêté', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            )
          else if (item.wishlist && library.canEdit)
            FilledButton.icon(
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Je l\'ai acquis'),
              onPressed: () async {
                await library.acquire(item);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Ajouté à votre collection')));
                }
              },
            )
          else if (library.canEdit)
            _LoanCard(item: item),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final (label, value) in infos)
                    ListTile(
                      dense: true,
                      title: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      subtitle: Text(value, style: theme.textTheme.bodyLarge),
                    ),
                ],
              ),
            ),
          ),
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Notes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(item.notes, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Library library, Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('« ${item.title} » sera définitivement retiré de votre bibliothèque.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await library.remove(item);
    await deleteCoverFile(item.coverPath);
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.read(context);
    if (!item.isLoaned) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.outbox),
        label: const Text('Prêter'),
        onPressed: () async {
          final name = await askBorrower(context);
          if (name != null) await library.lend(item, name);
        },
      );
    }
    final theme = Theme.of(context);
    final since = item.loanDate == null ? '' : ' depuis le ${DateFormat.yMMMd('fr').format(item.loanDate!)}';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.outbox, color: theme.colorScheme.onErrorContainer),
        title: Text('Prêté à ${item.loanedTo}', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        subtitle: since.isEmpty
            ? null
            : Text(since.trim(), style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        trailing: TextButton(onPressed: () => library.giveBack(item), child: const Text('Rendu')),
      ),
    );
  }
}

/// Demande à qui l'objet est prêté. Renvoie null si l'utilisateur annule.
Future<String?> askBorrower(BuildContext context) {
  final controller = TextEditingController();
  final known = LibraryScope.read(context).suggestions((i) => i.loanedTo ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: const Text('Prêter à…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom'),
              onSubmitted: (_) => submit(),
            ),
            if (known.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in known) ActionChip(label: Text(name), onPressed: () => Navigator.pop(ctx, name)),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: submit, child: const Text('Prêter')),
        ],
      );
    },
  );
}
