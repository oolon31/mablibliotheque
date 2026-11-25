
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/library.dart';
import 'cloud_item_repository.dart';
import 'migration.dart';

/// Une bibliothèque accessible : la mienne, ou une bibliothèque partagée avec moi.
class LibraryRef {
  const LibraryRef({required this.ownerId, required this.name, required this.role});

  final String ownerId;
  final String name;

  /// 'owner' (la mienne), 'write' (partagée, modifiable) ou 'read' (partagée, lecture seule).
  final String role;

  bool get isOwn => role == 'owner';
  bool get canEdit => role != 'read';

  String get roleLabel => switch (role) {
    'owner' => 'Votre bibliothèque',
    'write' => 'Partagée · modification autorisée',
    _ => 'Partagée · lecture seule',
  };
}

/// État de l'application : session, chargement, bibliothèques et bibliothèque ouverte.
/// Tout l'affichage en dépend, y compris l'écran d'accueil, qui se met à jour seul.
class AppState extends ChangeNotifier {
  AppState({required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  Library? _current;
  LibraryRef? _currentRef;
  List<LibraryRef> _libraries = [];
  bool _importChecked = false;

  bool signedIn = false;
  bool busy = false;
  bool recovering = false;
  String? error;

  Library? get current => _current;
  LibraryRef? get currentRef => _currentRef;
  List<LibraryRef> get libraries => List.unmodifiable(_libraries);

  SupabaseClient get _db => Supabase.instance.client;

  /// Appelé à chaque changement de session (connexion, déconnexion, rafraîchissement).
  Future<void> onSession(Session? session) async {
    if (session == null) {
      signedIn = false;
      recovering = false;
      error = null;
      _importChecked = false;
      _current = null;
      _currentRef = null;
      _libraries = [];
      notifyListeners();
      // Revenir à l'écran de connexion, quelles que soient les pages ouvertes.
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    signedIn = true;
    notifyListeners();
    if (_current == null && !busy) await load();
  }

  void startRecovery() {
    recovering = true;
    notifyListeners();
  }

  /// Le mot de passe a été changé : on reprend la session normale.
  Future<void> finishRecovery() async {
    recovering = false;
    notifyListeners();
    if (_current == null) await load();
  }

  /// Charge mes bibliothèques et ouvre la mienne. Affiche l'erreur en cas d'échec.
  Future<void> load() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _start();
      if (!_importChecked) {
        _importChecked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _offerImport());
      }
    } catch (e) {
      final detail = e.toString();
      error =
          'Impossible de charger votre bibliothèque.\n\n'
          'Détail technique : ${detail.length > 300 ? detail.substring(0, 300) : detail}';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _start() async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('Non connecté');

    final profile = await _db.from('profiles').select('username, display_name').eq('id', user.id).single();
    final shares = await _db
        .from('shares')
        .select('role, owner_id, owner:profiles!owner_id(username, display_name)')
        .eq('viewer_id', user.id)
        .order('created_at');

    final mine = LibraryRef(
      ownerId: user.id,
      name: (profile['display_name'] as String).trim().isNotEmpty
          ? profile['display_name'] as String
          : 'Ma bibliothèque',
      role: 'owner',
    );
    _libraries = [
      mine,
      for (final s in shares)
        LibraryRef(
          ownerId: s['owner_id'] as String,
          name: _nameOf(s['owner'] as Map<String, dynamic>?),
          role: s['role'] as String,
        ),
    ];
    await open(mine);
  }

  /// Recharge la liste des bibliothèques partagées (après une invitation, par exemple).
  Future<void> refreshLibraries() async {
    final ownerRef = _libraries.firstWhere((l) => l.isOwn);
    final user = _db.auth.currentUser!;
    final shares = await _db
        .from('shares')
        .select('role, owner_id, owner:profiles!owner_id(username, display_name)')
        .eq('viewer_id', user.id)
        .order('created_at');
    _libraries = [
      ownerRef,
      for (final s in shares)
        LibraryRef(
          ownerId: s['owner_id'] as String,
          name: _nameOf(s['owner'] as Map<String, dynamic>?),
          role: s['role'] as String,
        ),
    ];
    notifyListeners();
  }

  Future<void> open(LibraryRef ref) async {
    final library = Library(CloudItemRepository(ref.ownerId), canEdit: ref.canEdit);
    await library.load();
    _current = library;
    _currentRef = ref;
    notifyListeners();
  }

  /// Propose d'importer ce qui était enregistré sur le téléphone avant les comptes.
  Future<void> _offerImport() async {
    final user = _db.auth.currentUser;
    final ctx = navigatorKey.currentContext;
    if (user == null || ctx == null || kIsWeb || _current == null) return;
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
        await _current!.restore(local, replace: false);
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

  static String _nameOf(Map<String, dynamic>? owner) {
    if (owner == null) return 'Bibliothèque partagée';
    final display = (owner['display_name'] as String?)?.trim() ?? '';
    if (display.isNotEmpty) return 'Bibliothèque de $display';
    return 'Bibliothèque de @${owner['username']}';
  }
}

/// Donne accès à l'[AppState] depuis n'importe quel écran.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Null si l'écran est affiché hors session (tests, par exemple).
  static AppState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}
