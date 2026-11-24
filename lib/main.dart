import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'data/demo_data.dart';
import 'data/item_repository.dart';
import 'data/sqlite_item_repository.dart';
import 'screens/home_screen.dart';
import 'state/library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  // Android : base SQLite sur le téléphone. Web : démo en mémoire, rien n'est enregistré.
  final ItemRepository repo =
      kIsWeb ? MemoryItemRepository(demoItems()) : await SqliteItemRepository.open();
  final library = Library(repo);
  runApp(BibliothequeApp(library: library));
  await library.load();
}

class BibliothequeApp extends StatelessWidget {
  const BibliothequeApp({super.key, required this.library});

  final Library library;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8C4A2F), brightness: b),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        );
    return LibraryScope(
      library: library,
      child: MaterialApp(
        title: 'Ma Bibliothèque',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeScreen(),
      ),
    );
  }
}
