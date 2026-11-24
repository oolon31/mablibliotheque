import '../models/item.dart';

/// Exemples utilisés par la démo web (et les tests). L'application Android démarre vide.
List<Item> demoItems() {
  final now = DateTime.now();
  DateTime ago(int days) => now.subtract(Duration(days: days));
  return [
    Item(type: ItemType.vinyle, title: 'Kind of Blue', creator: 'Miles Davis', year: 1959,
        publisher: 'Columbia', genre: 'Jazz', format: '33 tours (LP)', condition: ItemCondition.tresBon,
        rating: 5, createdAt: ago(40)),
    Item(type: ItemType.vinyle, title: 'Rumours', creator: 'Fleetwood Mac', year: 1977,
        publisher: 'Warner Bros.', genre: 'Rock', format: '33 tours (LP)', condition: ItemCondition.bon,
        rating: 4, loanedTo: 'Camille', loanDate: ago(12), createdAt: ago(30)),
    Item(type: ItemType.vinyle, title: 'Histoire de Melody Nelson', creator: 'Serge Gainsbourg',
        year: 1971, publisher: 'Philips', genre: 'Chanson française', format: '33 tours (LP)',
        rating: 5, createdAt: ago(20)),
    Item(type: ItemType.livre, title: 'L\'Étranger', creator: 'Albert Camus', year: 1942,
        publisher: 'Gallimard', genre: 'Roman', format: 'Poche', rating: 4, createdAt: ago(25)),
    Item(type: ItemType.livre, title: 'Dune', creator: 'Frank Herbert', year: 1965,
        publisher: 'Robert Laffont', genre: 'Science-fiction', format: 'Broché', series: 'Dune',
        volume: '1', rating: 5, loanedTo: 'Léo', loanDate: ago(3), createdAt: ago(15)),
    Item(type: ItemType.bd, title: 'Les Cigares du pharaon', creator: 'Hergé', year: 1934,
        publisher: 'Casterman', genre: 'Aventure', format: 'Album', series: 'Les Aventures de Tintin',
        volume: '4', condition: ItemCondition.bon, createdAt: ago(10)),
    Item(type: ItemType.bd, title: 'Tintin au pays des Soviets', creator: 'Hergé', year: 1930,
        publisher: 'Casterman', genre: 'Aventure', format: 'Album', series: 'Les Aventures de Tintin',
        volume: '1', createdAt: ago(9)),
    Item(type: ItemType.bd, title: 'Blacksad : Quelque part entre les ombres', creator: 'Díaz Canales / Guarnido',
        year: 2000, publisher: 'Dargaud', genre: 'Polar', format: 'Album', series: 'Blacksad', volume: '1',
        rating: 5, createdAt: ago(5)),
    Item(type: ItemType.vinyle, title: 'Random Access Memories', creator: 'Daft Punk', year: 2013,
        publisher: 'Columbia', genre: 'Électro', format: 'Double album', wishlist: true, createdAt: ago(2)),
    Item(type: ItemType.livre, title: 'Les Furtifs', creator: 'Alain Damasio', year: 2019,
        publisher: 'La Volte', genre: 'Science-fiction', wishlist: true, createdAt: ago(1)),
  ];
}
