import 'package:flutter_test/flutter_test.dart';
import 'package:ma_bibliotheque/data/demo_data.dart';
import 'package:ma_bibliotheque/data/item_repository.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/state/library.dart';

void main() {
  final items = demoItems();

  test('toMap / fromMap conserve toutes les données', () {
    final dune = items.firstWhere((i) => i.title == 'Dune');
    final back = Item.fromMap(dune.copyWith(id: 7).toMap());
    expect(back.id, 7);
    expect(back.toMap(), dune.copyWith(id: 7).toMap());
    expect(back.loanDate!.millisecondsSinceEpoch, dune.loanDate!.millisecondsSinceEpoch);
  });

  test('copyWith permet de remettre un champ à null', () {
    final loaned = items.firstWhere((i) => i.isLoaned);
    final back = loaned.copyWith(loanedTo: null, loanDate: null);
    expect(back.isLoaned, isFalse);
    expect(back.loanDate, isNull);
    expect(back.title, loaned.title);
  });

  test('la recherche ignore accents et majuscules', () {
    expect(filterItems(items, query: 'etranger').map((i) => i.title), ['L\'Étranger']);
    expect(filterItems(items, query: 'HERGÉ').length, 2);
    // Plusieurs mots : tous doivent être présents.
    expect(filterItems(items, query: 'tintin 1930').map((i) => i.title), ['Tintin au pays des Soviets']);
  });

  test('collection et envies sont séparées', () {
    expect(filterItems(items).any((i) => i.wishlist), isFalse);
    expect(
      filterItems(items, wishlist: true).map((i) => i.title),
      containsAll(['Random Access Memories', 'Les Furtifs']),
    );
  });

  test('le filtre par type fonctionne', () {
    final bd = filterItems(items, type: ItemType.bd);
    expect(bd.length, 3);
    expect(bd.every((i) => i.type == ItemType.bd), isTrue);
  });

  test('tri par titre : les tomes d\'une série se suivent dans l\'ordre', () {
    final bd = filterItems(items, type: ItemType.bd).map((i) => i.title).toList();
    expect(bd.indexOf('Tintin au pays des Soviets'), lessThan(bd.indexOf('Les Cigares du pharaon')));
  });

  test('tri par année, la plus récente d\'abord', () {
    final years = filterItems(items, sort: SortOrder.yearDesc).map((i) => i.year!).toList();
    final sorted = [...years]..sort((a, b) => b.compareTo(a));
    expect(years, sorted);
  });

  test('prêter, rendre et acquérir', () async {
    final library = Library(MemoryItemRepository(demoItems()));
    await library.load();
    final initialLoans = library.loans.length;

    final kind = library.items.firstWhere((i) => i.title == 'Kind of Blue');
    await library.lend(kind, '  Marie ');
    expect(library.byId(kind.id!)!.loanedTo, 'Marie');
    expect(library.loans.length, initialLoans + 1);

    await library.giveBack(library.byId(kind.id!)!);
    expect(library.byId(kind.id!)!.isLoaned, isFalse);
    expect(library.loans.length, initialLoans);

    final wish = library.items.firstWhere((i) => i.wishlist);
    await library.acquire(wish);
    expect(library.byId(wish.id!)!.wishlist, isFalse);
  });

  test('suggestions sans doublons, triées', () async {
    final library = Library(MemoryItemRepository(demoItems()));
    await library.load();
    final creators = library.suggestions((i) => i.creator, type: ItemType.bd);
    expect(creators, ['Díaz Canales / Guarnido', 'Hergé']);
  });
}
