import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../state/library.dart';
import 'backup_flow.dart';
import 'item_form_screen.dart';
import 'item_list_page.dart';
import 'loans_page.dart';
import 'scan_flow.dart';
import 'stats_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Ma bibliothèque', 'Mes envies', 'Prêts en cours', 'Statistiques'];

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final loanCount = library.loans.length;
    final pages = const [
      ItemListPage(key: PageStorageKey('collection'), wishlist: false),
      ItemListPage(key: PageStorageKey('wishlist'), wishlist: true),
      LoansPage(),
      StatsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          PopupMenuButton<void Function()>(
            tooltip: 'Plus d\'options',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => exportBackup(context),
                child: const ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Sauvegarder la bibliothèque'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: () => importBackup(context),
                child: const ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Restaurer une sauvegarde'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: !library.loaded ? const Center(child: CircularProgressIndicator()) : pages[_tab],
      floatingActionButton: _tab <= 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!kIsWeb) ...[
                  FloatingActionButton(
                    heroTag: 'scan',
                    tooltip: 'Ajouter en scannant le code-barres',
                    onPressed: () => scanAndAdd(context, wishlist: _tab == 1),
                    child: const Icon(Icons.qr_code_scanner),
                  ),
                  const SizedBox(height: 16),
                ],
                FloatingActionButton.extended(
                  heroTag: 'add',
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ItemFormScreen(initialWishlist: _tab == 1),
                  )),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Collection',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Envies',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: loanCount > 0, label: Text('$loanCount'), child: const Icon(Icons.outbox)),
            label: 'Prêts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
