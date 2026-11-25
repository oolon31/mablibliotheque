import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Connexion, ou création de compte (e-mail + mot de passe).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    for (final c in [_email, _password, _username, _displayName]) {
      c.dispose();
    }
    super.dispose();
  }

  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou mot de passe incorrect.';
    if (m.contains('not confirmed')) {
      return 'Votre adresse n\'est pas encore confirmée : ouvrez le lien reçu par e-mail, puis connectez-vous.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'Un compte existe déjà avec cette adresse. Connectez-vous plutôt.';
    }
    if (m.contains('password')) return 'Mot de passe refusé : choisissez-en un plus long (8 caractères minimum).';
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Trop de tentatives. Attendez quelques minutes avant de réessayer.';
    }
    return e.message;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_signup) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'username': _username.text.trim().toLowerCase(), 'display_name': _displayName.text.trim()},
        );
        if (res.session == null) {
          // Confirmation par e-mail activée : on attend le clic sur le lien.
          setState(() {
            _signup = false;
            _messageIsError = false;
            _message =
                'Compte créé. Ouvrez le lien de confirmation reçu par e-mail, '
                'puis connectez-vous ici.';
          });
        }
        // Sinon, la session est ouverte et l'écran suivant prend le relais.
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      setState(() {
        _messageIsError = true;
        _message = _friendly(e);
      });
    } catch (_) {
      setState(() {
        _messageIsError = true;
        _message = 'Pas de connexion internet. Réessayez quand le réseau revient.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.library_books, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Ma Bibliothèque', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Se connecter')),
                        ButtonSegment(value: true, label: Text('Créer un compte')),
                      ],
                      selected: {_signup},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => setState(() {
                              _signup = s.first;
                              _message = null;
                            }),
                    ),
                    const SizedBox(height: 20),
                    if (_signup) ...[
                      TextFormField(
                        controller: _displayName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Prénom ou pseudo affiché'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez un nom' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Identifiant',
                          helperText: 'Lettres, chiffres et _ (3 à 30 caractères)',
                        ),
                        validator: (v) =>
                            RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch((v ?? '').trim()) ? null : 'Identifiant invalide',
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                          ? null
                          : 'Adresse e-mail invalide',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        helperText: _signup ? '8 caractères minimum' : null,
                      ),
                      validator: (v) => (v == null || v.length < 8) ? '8 caractères minimum' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signup ? 'Créer mon compte' : 'Se connecter'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _messageIsError ? theme.colorScheme.error : theme.colorScheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
