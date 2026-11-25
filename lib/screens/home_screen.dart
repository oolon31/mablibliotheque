import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/session.dart';
import '../state/library.dart';
import 'backup_flow.dart';
import 'item_form_screen.dart';
import 'item_list_page.dart';
import 'loans_page.dart';
import 'scan_flow.dart';
import 'sharing_screen.dart';
import 'stats_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  static const _titles = ['Ma bibliothèque', 'Mes envies', 'Prêts en cours', 'Statistiques'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Recharge la bibliothèque au retour dans l'application : les modifications des autres y figurent.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final library = LibraryScope.read(context);
    try {
      await library.load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Actualisation impossible : pas de connexion internet.')));
      }
    }
  }

  Future<void> _switchLibrary() async {
    final app = AppScope.of(context);
    await app.refreshLibraries().catchError((_) {});
    if (!mounted) return;
    final chosen = await showModalBottomSheet<LibraryRef>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ref in app.libraries)
              ListTile(
                leading: Icon(ref.isOwn ? Icons.home_outlined : Icons.people_outline),
                title: Text(ref.isOwn ? 'Ma bibliothèque' : ref.name),
                subtitle: Text(ref.roleLabel),
                selected: ref.ownerId == app.currentRef?.ownerId,
                onTap: () => Navigator.pop(ctx, ref),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.ownerId == app.currentRef?.ownerId || !mounted) return;
    try {
      await app.open(chosen);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir cette bibliothèque.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final app = AppScope.maybeOf(context);
    final ref = app?.currentRef;
    final isOwn = ref?.isOwn ?? true;
    final ownerName = ref?.name ?? '';
    final loanCount = library.loans.length;
    final pages = const [
      ItemListPage(key: PageStorageKey('collection'), wishlist: false),
      ItemListPage(key: PageStorageKey('wishlist'), wishlist: true),
      LoansPage(),
      StatsPage(),
    ];

    final title = _tab == 0 && !isOwn ? ownerName : _titles[_tab];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, overflow: TextOverflow.ellipsis),
            if (_tab == 0 && !isOwn && ref != null) Text(ref.roleLabel, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          PopupMenuButton<void Function()>(
            tooltip: 'Plus d\'options',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (app != null)
                PopupMenuItem(
                  value: _switchLibrary,
                  child: const ListTile(
                    leading: Icon(Icons.swap_horiz),
                    title: Text('Changer de bibliothèque'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (isOwn && app != null)
                PopupMenuItem(
                  value: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SharingScreen())),
                  child: const ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Partager ma bibliothèque'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: () => exportBackup(context),
                child: const ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Sauvegarder cette bibliothèque'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (isOwn)
                PopupMenuItem(
                  value: () => importBackup(context),
                  child: const ListTile(
                    leading: Icon(Icons.restore),
                    title: Text('Restaurer une sauvegarde'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (app != null)
                PopupMenuItem(
                  value: () => Supabase.instance.client.auth.signOut(),
                  child: const ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Se déconnecter'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: !library.loaded ? const Center(child: CircularProgressIndicator()) : pages[_tab],
      floatingActionButton: _tab <= 1 && library.canEdit
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
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ItemFormScreen(initialWishlist: _tab == 1))),
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
