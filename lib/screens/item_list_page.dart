import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import '../state/library.dart';
import '../widgets/item_tile.dart';
import 'item_detail_screen.dart';

/// Liste filtrable, utilisée pour la collection et pour la liste d'envies.
class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key, required this.wishlist});

  final bool wishlist;

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends State<ItemListPage> {
  final _search = TextEditingController();
  ItemType? _type;
  SortOrder _sort = SortOrder.title;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final pool = library.items.where((i) => i.wishlist == widget.wishlist);
    final items = filterItems(library.items,
        type: _type, query: _search.text, wishlist: widget.wishlist, sort: _sort);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SearchBar(
            controller: _search,
            hintText: widget.wishlist ? 'Rechercher dans mes envies' : 'Titre, auteur, série, genre…',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (_) => setState(() {}),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_search.clear),
                ),
              PopupMenuButton<SortOrder>(
                tooltip: 'Trier',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  for (final s in SortOrder.values) PopupMenuItem(value: s, child: Text(s.label)),
                ],
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              _chip(null, 'Tout', pool.length),
              for (final t in ItemType.values)
                _chip(t, t.plural, pool.where((i) => i.type == t).length),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(wishlist: widget.wishlist, searching: pool.isNotEmpty)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 168),
                  itemCount: items.length,
                  itemBuilder: (context, i) => ItemTile(
                    item: items[i],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ItemDetailScreen(itemId: items[i].id!),
                    )),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(ItemType? type, String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($count)'),
        avatar: type == null ? null : Icon(type.icon, size: 18),
        selected: _type == type,
        showCheckmark: false,
        onSelected: (_) => setState(() => _type = type),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.wishlist, required this.searching});

  final bool wishlist;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, text) = searching
        ? (Icons.search_off, 'Aucun résultat', 'Essayez un autre mot ou un autre filtre.')
        : wishlist
            ? (Icons.favorite_border, 'Aucune envie pour l\'instant',
                'Ajoutez ici les disques, livres et BD que vous aimeriez acquérir.')
            : (Icons.library_books_outlined, 'Votre bibliothèque est vide',
                'Touchez « Ajouter » pour enregistrer votre premier vinyle, livre ou BD.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
