import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/library.dart';
import 'cloud_item_repository.dart';

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

/// État de la session : la liste des bibliothèques et celle qui est ouverte.
class AppState extends ChangeNotifier {
  Library? _current;
  LibraryRef? _currentRef;
  List<LibraryRef> _libraries = [];

  Library? get current => _current;
  LibraryRef? get currentRef => _currentRef;
  List<LibraryRef> get libraries => List.unmodifiable(_libraries);

  SupabaseClient get _db => Supabase.instance.client;

  /// Charge mes bibliothèques et ouvre la mienne. Lève une exception si le réseau échoue.
  Future<void> start() async {
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

  /// Recharge la liste des bibliothèques partagées (après une invitation acceptée, par exemple).
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

  void clear() {
    _current = null;
    _currentRef = null;
    _libraries = [];
    notifyListeners();
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
