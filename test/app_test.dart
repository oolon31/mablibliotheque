import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ma_bibliotheque/data/item_repository.dart';
import 'package:ma_bibliotheque/main.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/state/library.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  testWidgets('ajouter une BD puis la retrouver par la recherche', (tester) async {
    final library = Library(MemoryItemRepository());
    await library.load();
    await tester.pumpWidget(BibliothequeApp(library: library));
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
}
