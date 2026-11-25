import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/config.dart';

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

  /// Demande un lien de réinitialisation. Le message est le même que l'adresse existe ou non.
  Future<void> _forgotPassword() async {
    final typed = _email.text.trim();
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: typed);
        return AlertDialog(
          title: const Text('Mot de passe oublié'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Indiquez votre adresse : vous recevrez un lien pour choisir un nouveau mot de passe.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Envoyer')),
          ],
        );
      },
    );
    if (address == null || address.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(address, redirectTo: passwordResetRedirect);
      setState(() {
        _messageIsError = false;
        _message =
            'Si un compte existe avec cette adresse, un lien de réinitialisation vient d\'être envoyé. '
            'Pensez à vérifier les indésirables.';
      });
    } on AuthException catch (e) {
      setState(() {
        _messageIsError = true;
        _message = e.message.toLowerCase().contains('rate') || e.message.toLowerCase().contains('too many')
            ? 'Trop de demandes. Attendez quelques minutes avant de réessayer.'
            : 'Envoi impossible pour le moment.';
      });
    } catch (_) {
      setState(() {
        _messageIsError = true;
        _message = 'Pas de connexion internet.';
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
                    if (!_signup)
                      TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text('Mot de passe oublié ?')),
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
