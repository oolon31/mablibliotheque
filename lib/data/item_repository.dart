import '../models/item.dart';

/// Stockage des objets. L'application utilise SQLite sur Android ;
/// la version en mémoire sert aux tests et à la démo web.
abstract class ItemRepository {
  Future<List<Item>> all();
  Future<Item> insert(Item item);
  Future<void> update(Item item);
  Future<void> delete(int id);

  /// Ajoute plusieurs objets d'un coup ; avec [replace], efface d'abord tout le reste.
  /// Tout réussit ou rien ne change.
  Future<List<Item>> insertAll(List<Item> items, {bool replace = false});
}

class MemoryItemRepository implements ItemRepository {
  MemoryItemRepository([List<Item> initial = const []]) {
    for (final item in initial) {
      _items[_nextId] = item.copyWith(id: _nextId);
      _nextId++;
    }
  }

  final Map<int, Item> _items = {};
  int _nextId = 1;

  @override
  Future<List<Item>> all() async => _items.values.toList();

  @override
  Future<Item> insert(Item item) async {
    final saved = item.copyWith(id: _nextId++);
    _items[saved.id!] = saved;
    return saved;
  }

  @override
  Future<void> update(Item item) async => _items[item.id!] = item;

  @override
  Future<void> delete(int id) async => _items.remove(id);

  @override
  Future<List<Item>> insertAll(List<Item> items, {bool replace = false}) async {
    if (replace) _items.clear();
    return [for (final i in items) await insert(i)];
  }
}
