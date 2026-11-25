import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../cloud/migration.dart';
import '../cloud/session.dart';
import '../data/item_repository.dart';
import '../state/library.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

/// Racine de l'application. Elle tient l'état de session et la bibliothèque courante
/// au-dessus de tout le reste, pour que chaque écran y accède, y compris ceux qui s'ouvrent par-dessus.
class BibliothequeRoot extends StatefulWidget {
  const BibliothequeRoot({super.key});

  @override
  State<BibliothequeRoot> createState() => _BibliothequeRootState();
}

class _BibliothequeRootState extends State<BibliothequeRoot> {
  final _app = AppState();
  final _navKey = GlobalKey<NavigatorState>();
  // Bibliothèque vide tant qu'aucune session n'est ouverte.
  final _placeholder = Library(MemoryItemRepository());
  StreamSubscription<AuthState>? _sub;
  bool _busy = false;
  bool _importChecked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _sub = auth.onAuthStateChange.listen((state) {
      if (state.session == null) {
        _app.clear();
        _importChecked = false;
        if (mounted) setState(() => _error = null);
      } else if (_app.current == null && !_busy) {
        _load();
      }
    });
    if (auth.currentSession != null) _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.start();
      if (!_importChecked) {
        _importChecked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _offerImport());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger votre bibliothèque. Vérifiez votre connexion.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Propose d'importer ce qui était enregistré sur le téléphone avant les comptes.
  Future<void> _offerImport() async {
    final user = Supabase.instance.client.auth.currentUser;
    final ctx = _navKey.currentContext;
    if (user == null || ctx == null || kIsWeb || _app.current == null) return;
    final local = await LocalMigration.pending(user.id);
    if (local.isEmpty || !ctx.mounted) return;

    final yes = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Importer votre bibliothèque ?'),
        content: Text(
          '${local.length} objet${local.length > 1 ? 's' : ''} étaient enregistrés sur ce téléphone '
          'avant la création des comptes. Voulez-vous les ajouter à votre bibliothèque ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Non merci')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Importer')),
        ],
      ),
    );
    if (yes == true) {
      try {
        await _app.current!.restore(local, replace: false);
      } catch (_) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Import impossible pour le moment. Réessayez plus tard depuis le menu ⋮.')),
          );
        }
        return;
      }
    }
    await LocalMigration.markDone(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    return AppScope(
      app: _app,
      child: ListenableBuilder(
        listenable: _app,
        builder: (context, _) {
          final library = _app.current;
          final Widget home;
          if (library != null) {
            home = const HomeScreen();
          } else if (!signedIn) {
            home = const AuthScreen();
          } else {
            home = _LoadingView(
              busy: _busy,
              error: _error,
              onRetry: _load,
              onLogout: () => Supabase.instance.client.auth.signOut(),
            );
          }
          return LibraryScope(
            library: library ?? _placeholder,
            child: BibliothequeApp(
              // Une nouvelle clé à chaque changement de session : la pile d'écrans repart de zéro.
              key: ValueKey('session-${Supabase.instance.client.auth.currentUser?.id ?? 'none'}'),
              navigatorKey: _navKey,
              home: home,
            ),
          );
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.busy, required this.error, required this.onRetry, required this.onLogout});

  final bool busy;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: busy || error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
                    TextButton(onPressed: onLogout, child: const Text('Se déconnecter')),
                  ],
                ),
        ),
      ),
    );
  }
}
