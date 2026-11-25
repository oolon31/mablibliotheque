import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gérer qui peut voir ou modifier MA bibliothèque.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _role = 'read';
  bool _busy = false;
  List<Map<String, dynamic>> _shares = [];
  List<Map<String, dynamic>> _invitations = [];
  bool _loading = true;

  SupabaseClient get _db => Supabase.instance.client;
  String get _me => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final shares = await _db
          .from('shares')
          .select('viewer_id, role, viewer:profiles!viewer_id(username, display_name)')
          .eq('owner_id', _me)
          .order('created_at');
      final invitations = await _db.from('invitations').select('email, role').eq('owner_id', _me).order('created_at');
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _invitations = invitations;
      });
    } catch (_) {
      _snack('Impossible de charger les partages. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _nameOf(Map<String, dynamic>? p) {
    if (p == null) return 'Utilisateur';
    final display = (p['display_name'] as String?)?.trim() ?? '';
    return display.isNotEmpty ? display : '@${p['username']}';
  }

  Future<void> _invite() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await _db.rpc('invite_by_email', params: {'invitee': _email.text.trim(), 'invitee_role': _role});
      _email.clear();
      _snack(
        result == 'shared' ? 'Accès accordé : la personne voit votre bibliothèque dès sa prochaine ouverture.' : 'Invitation enregistrée. Dès qu\'elle créera son compte avec cette adresse, elle verra votre bibliothèque.',
      );
      await _load();
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Pas de connexion internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeShareRole(String viewerId, String role) async {
    try {
      await _db.from('shares').update({'role': role}).eq('owner_id', _me).eq('viewer_id', viewerId);
      await _load();
    } catch (_) {
      _snack('Modification impossible.');
    }
  }

  Future<void> _removeShare(String viewerId) async {
    try {
      await _db.from('shares').delete().eq('owner_id', _me).eq('viewer_id', viewerId);
      await _load();
    } catch (_) {
      _snack('Suppression impossible.');
    }
  }

  Future<void> _cancelInvitation(String email) async {
    try {
      await _db.from('invitations').delete().eq('owner_id', _me).eq('email', email);
      await _load();
    } catch (_) {
      _snack('Annulation impossible.');
    }
  }

  Widget _roleDropdown(String current, ValueChanged<String> onChanged) => DropdownButton<String>(
    value: current,
    underline: const SizedBox.shrink(),
    items: const [
      DropdownMenuItem(value: 'read', child: Text('Lecture seule')),
      DropdownMenuItem(value: 'write', child: Text('Peut modifier')),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Partager ma bibliothèque')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Inviter quelqu\'un', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'La personne doit avoir un compte avec cette adresse e-mail. '
                    'Vous choisissez pour elle la lecture seule, ou la possibilité de modifier.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                          ? null
                          : 'Adresse e-mail invalide',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'read', label: Text('Lecture seule'), icon: Icon(Icons.visibility)),
                      ButtonSegment(value: 'write', label: Text('Modifier'), icon: Icon(Icons.edit)),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Inviter'),
                    onPressed: _busy ? null : _invite,
                  ),
                  const SizedBox(height: 28),
                  Text('Ont accès', style: theme.textTheme.titleMedium),
                  if (_shares.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Personne pour l\'instant.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final s in _shares)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(_nameOf(s['viewer'] as Map<String, dynamic>?)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _roleDropdown(s['role'] as String, (r) => _changeShareRole(s['viewer_id'] as String, r)),
                          IconButton(
                            tooltip: 'Retirer',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _removeShare(s['viewer_id'] as String),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (_invitations.isNotEmpty) ...[
                    Text('Invitations en attente', style: theme.textTheme.titleMedium),
                    for (final inv in _invitations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
                        title: Text(inv['email'] as String),
                        subtitle: Text(inv['role'] == 'write' ? 'Peut modifier' : 'Lecture seule'),
                        trailing: IconButton(
                          tooltip: 'Annuler l\'invitation',
                          icon: const Icon(Icons.close),
                          onPressed: () => _cancelInvitation(inv['email'] as String),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
