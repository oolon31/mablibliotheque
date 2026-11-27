import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ma_bibliotheque/data/item_repository.dart';
import 'package:ma_bibliotheque/app.dart';
import 'package:ma_bibliotheque/screens/home_screen.dart';
import 'package:ma_bibliotheque/screens/item_form_screen.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/state/library.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  testWidgets('ajouter une BD puis la retrouver par la recherche', (tester) async {
    final library = Library(MemoryItemRepository());
    await library.load();
    await tester.pumpWidget(
      LibraryScope(
        library: library,
        child: const BibliothequeApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Votre bibliothèque est vide'), findsOneWidget);

    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    // Le titre est obligatoire.
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Le titre est obligatoire'), findsOneWidget);

    await tester.tap(find.text('BD'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Titre *'), 'Astérix le Gaulois');
    await tester.enterText(find.widgetWithText(TextFormField, 'Série'), 'Astérix');
    await tester.enterText(find.widgetWithText(TextFormField, 'Tome'), '1');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(library.items.single.type, ItemType.bd);
    expect(library.items.single.seriesLabel, 'Astérix · T. 1');
    expect(find.text('Astérix le Gaulois'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'asterix');
    await tester.pumpAndSettle();
    expect(find.text('Astérix le Gaulois'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
  });

  testWidgets('une fiche trouvée par code-barres préremplit le formulaire', (tester) async {
    final library = Library(MemoryItemRepository());
    await library.load();
    final draft = Item(
      type: ItemType.bd,
      title: 'On a marché sur la lune',
      creator: 'Hergé',
      series: 'Les Aventures de Tintin',
      volume: '17',
      year: 1954,
      publisher: 'Casterman',
      identifier: '9782203001169',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      LibraryScope(
        library: library,
        child: MaterialApp(home: ItemFormScreen(draft: draft)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ajouter'), findsOneWidget); // c'est bien un ajout
    expect(find.text('Remplir avec le code-barres'), findsNothing); // déjà rempli
    expect(find.text('Hergé'), findsOneWidget);
    expect(find.text('9782203001169'), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final saved = library.items.single;
    expect(saved.type, ItemType.bd);
    expect(saved.seriesLabel, 'Les Aventures de Tintin · T. 17');
    expect(saved.identifier, '9782203001169');
    expect(saved.id, isNotNull);
  });

  testWidgets('un ISBN invalide est refusé', (tester) async {
    final library = Library(MemoryItemRepository());
    await library.load();
    await tester.pumpWidget(
      LibraryScope(
        library: library,
        child: const MaterialApp(home: ItemFormScreen(initialType: ItemType.livre)),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Titre *'), 'Test');
    await tester.enterText(find.widgetWithText(TextFormField, 'ISBN'), '9782070360025');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('ISBN invalide'), findsOneWidget);
    expect(library.items, isEmpty);
  });

  testWidgets('ajouter un set Lego : pas d\'auteur, nombre de pièces, numéro de set libre', (tester) async {
    final library = Library(MemoryItemRepository());
    await library.load();
    await tester.pumpWidget(
      LibraryScope(
        library: library,
        child: const MaterialApp(home: ItemFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Lego'));
    await tester.pumpAndSettle();

    // Un set n'a pas d'auteur ; il a un nombre de pièces et une marque préremplie.
    expect(find.widgetWithText(TextFormField, 'Nombre de pièces'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Série'), findsNothing);
    expect(find.text('LEGO'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Titre *'), 'Faucon Millenium');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre de pièces'), '7541');
    await tester.enterText(find.widgetWithText(TextFormField, 'Numéro du set ou code-barres'), '75192');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('ISBN invalide'), findsNothing);
    final saved = library.items.single;
    expect(saved.type, ItemType.lego);
    expect(saved.volume, '7541');
    expect(saved.identifier, '75192');
    expect(saved.publisher, 'LEGO');
    expect(saved.creator, isEmpty);
  });
}
