import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../cloud/session.dart';
import '../data/item_repository.dart';
import '../state/library.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'reset_password_screen.dart';

/// Racine de l'application. L'état de session vit au-dessus de l'application :
/// l'écran affiché est choisi par [SessionHome], qui se met à jour à chaque changement.
class BibliothequeRoot extends StatefulWidget {
  const BibliothequeRoot({super.key});

  @override
  State<BibliothequeRoot> createState() => _BibliothequeRootState();
}

class _BibliothequeRootState extends State<BibliothequeRoot> {
  final _navKey = GlobalKey<NavigatorState>();
  late final AppState _app = AppState(navigatorKey: _navKey);
  // Bibliothèque vide tant qu'aucune session n'est ouverte.
  final _placeholder = Library(MemoryItemRepository());
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _sub = auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _app.startRecovery();
      } else {
        _app.onSession(state.session);
      }
    });
    _app.onSession(auth.currentSession);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: _app,
      child: ListenableBuilder(
        listenable: _app,
        builder: (context, _) => LibraryScope(
          library: _app.current ?? _placeholder,
          child: BibliothequeApp(navigatorKey: _navKey, home: const SessionHome()),
        ),
      ),
    );
  }
}

/// Première page de l'application : connexion, chargement, nouveau mot de passe ou accueil.
class SessionHome extends StatelessWidget {
  const SessionHome({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.recovering) return ResetPasswordScreen(onDone: app.finishRecovery);
        if (app.current != null) return const HomeScreen();
        if (!app.signedIn) return const AuthScreen();
        return _LoadingView(
          busy: app.busy,
          error: app.error,
          onRetry: app.load,
          onLogout: () => Supabase.instance.client.auth.signOut(),
        );
      },
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
