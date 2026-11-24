import 'package:material_ui/material_ui.dart';

import '../data/item_repository.dart';
import '../models/item.dart';

enum SortOrder {
  title('Titre'),
  creator('Artiste / auteur'),
  yearDesc('Année (récent d\'abord)'),
  added('Derniers ajouts');

  const SortOrder(this.label);
  final String label;
}

/// Minuscules sans accents, pour une recherche tolérante (« eau » trouve « Éau »).
String normalize(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

/// Clé de tri par titre : les albums d'une même série se suivent, dans l'ordre des tomes.
String _titleKey(Item i) {
  if (i.series.isEmpty) return normalize(i.title);
  final n = int.tryParse(i.volume);
  final vol = n != null ? n.toString().padLeft(4, '0') : i.volume;
  return '${normalize(i.series)} $vol ${normalize(i.title)}';
}

/// Filtre et trie une liste d'objets. Fonction pure, testée séparément.
List<Item> filterItems(
  Iterable<Item> items, {
  ItemType? type,
  String query = '',
  bool wishlist = false,
  SortOrder sort = SortOrder.title,
}) {
  final words = normalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final result = items.where((i) {
    if (i.wishlist != wishlist) return false;
    if (type != null && i.type != type) return false;
    if (words.isEmpty) return true;
    final haystack = normalize([
      i.title, i.creator, i.series, i.publisher, i.genre, i.identifier, i.notes,
      i.year?.toString() ?? '',
    ].join(' '));
    return words.every(haystack.contains);
  }).toList();

  int byTitle(Item a, Item b) => _titleKey(a).compareTo(_titleKey(b));
  switch (sort) {
    case SortOrder.title:
      result.sort(byTitle);
    case SortOrder.creator:
      result.sort((a, b) {
        final c = normalize(a.creator).compareTo(normalize(b.creator));
        return c != 0 ? c : byTitle(a, b);
      });
    case SortOrder.yearDesc:
      result.sort((a, b) {
        final c = (b.year ?? -1).compareTo(a.year ?? -1);
        return c != 0 ? c : byTitle(a, b);
      });
    case SortOrder.added:
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return result;
}

/// État global de la bibliothèque, partagé par tous les écrans.
class Library extends ChangeNotifier {
  Library(this._repo);

  final ItemRepository _repo;
  List<Item> _items = [];
  bool loaded = false;

  List<Item> get items => List.unmodifiable(_items);
  Iterable<Item> get owned => _items.where((i) => !i.wishlist);
  List<Item> get loans => owned.where((i) => i.isLoaned).toList()
    ..sort((a, b) => (a.loanDate ?? a.createdAt).compareTo(b.loanDate ?? b.createdAt));

  Item? byId(int id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Valeurs déjà saisies pour un champ, pour l'autocomplétion.
  List<String> suggestions(String Function(Item) field, {ItemType? type}) {
    final set = <String>{};
    for (final i in _items) {
      if (type != null && i.type != type) continue;
      final v = field(i).trim();
      if (v.isNotEmpty) set.add(v);
    }
    return set.toList()..sort((a, b) => normalize(a).compareTo(normalize(b)));
  }

  Future<void> load() async {
    _items = await _repo.all();
    loaded = true;
    notifyListeners();
  }

  Future<Item> add(Item item) async {
    final saved = await _repo.insert(item);
    _items.add(saved);
    notifyListeners();
    return saved;
  }

  Future<void> save(Item item) async {
    await _repo.update(item);
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx >= 0) _items[idx] = item;
    notifyListeners();
  }

  Future<void> remove(Item item) async {
    await _repo.delete(item.id!);
    _items.removeWhere((i) => i.id == item.id);
    notifyListeners();
  }

  Future<void> lend(Item item, String to) =>
      save(item.copyWith(loanedTo: to.trim(), loanDate: DateTime.now()));

  Future<void> giveBack(Item item) => save(item.copyWith(loanedTo: null, loanDate: null));

  /// Ajoute les objets d'une sauvegarde, ou remplace toute la bibliothèque par eux.
  Future<List<Item>> restore(List<Item> items, {required bool replace}) async {
    final saved = await _repo.insertAll(items, replace: replace);
    if (replace) _items = [];
    _items.addAll(saved);
    notifyListeners();
    return saved;
  }

  /// Passe un objet de la liste d'envies à la collection.
  Future<void> acquire(Item item) => save(item.copyWith(wishlist: false));
}

/// Donne accès à la [Library] depuis n'importe quel widget.
class LibraryScope extends InheritedNotifier<Library> {
  const LibraryScope({super.key, required Library library, required super.child})
      : super(notifier: library);

  static Library of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryScope>()!.notifier!;

  static Library read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryScope>()!.notifier!;
}
