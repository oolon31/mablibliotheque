# Ma Bibliothèque

Application Android (Flutter) pour gérer sa collection de vinyles, livres et bandes dessinées.
Chaque personne a son compte et sa bibliothèque, qu'elle peut partager en lecture seule ou en modification.

## Installer l'application

Téléchargez `apk/ma-bibliotheque-2.1.1.apk` sur votre téléphone Android et ouvrez-le
(autorisez l'installation depuis cette source si Android le demande).

## Fonctionnalités

- Collection, liste d'envies, prêts, statistiques
- Ajout par scan de code-barres (livres, BD, vinyles), avec recherche automatique de la fiche
- Sauvegarde et restauration dans un fichier `.zip`
- Comptes (e-mail et mot de passe), mot de passe oublié
- Partage : invitation par e-mail, droit de lecture seule ou de modification

## Développement

```bash
flutter pub get
flutter test                 # tests unitaires et d'interface
flutter build apk --release  # génère l'APK
```

### Serveur (Supabase)

1. Créez un projet Supabase.
2. Dans l'éditeur SQL, exécutez `supabase/schema.sql` (tables, règles d'accès, couvertures, restauration).
3. Dans **Authentication → URL Configuration**, ajoutez `fr.mabibliotheque://reset-password` aux Redirect URLs.
4. Renseignez l'adresse et la clé publique dans `lib/cloud/config.dart`.

Les règles d'accès se testent sur PostgreSQL local, sans toucher au serveur réel : voir `supabase/tests/README.md`.

## Limites connues

- L'application nécessite une connexion internet pour afficher et modifier les bibliothèques.
- Les mises à jour ne sont pas en direct : la bibliothèque se rafraîchit à l'ouverture et en tirant vers le bas.
- L'APK est signé avec une clé temporaire : une mise à jour ne peut pas s'installer par-dessus une version signée autrement.
