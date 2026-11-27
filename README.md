# Ma Bibliothèque

Application Android (Flutter) pour gérer sa collection de vinyles, livres et bandes dessinées.
Chaque personne a son compte et sa bibliothèque, qu'elle peut partager en lecture seule ou en modification.

## Installer l'application

Téléchargez `apk/ma-bibliotheque-2.3.0.apk` sur votre téléphone Android et ouvrez-le
(autorisez l'installation depuis cette source si Android le demande).

## Fonctionnalités

- Collection, liste d'envies, prêts, statistiques
- Ajout par scan de code-barres (livres, BD, vinyles, DVD, Blu-ray), avec recherche automatique de la fiche
- Code non reconnu : recherche du livre par titre et auteur
- Types : vinyles, livres, BD, DVD, Blu-ray, Lego (numéro de set, thème, nombre de pièces)
- Sauvegarde et restauration dans un fichier `.zip`
- Comptes (e-mail et mot de passe), mot de passe oublié
- Partage : invitation par e-mail, droit de lecture seule ou de modification

## Développement

Pour signer l'APK de production, créez `android/key.properties` à partir de `android/key.properties.example` (non versionné).

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
- La clé de signature de production n'est pas dans le dépôt. Sans elle, il est impossible de publier une mise à jour qui s'installe par-dessus l'application : conservez-la en lieu sûr (voir `android/key.properties.example`).
- Les versions 2.2.0 et antérieures étaient signées avec une autre clé : il faut les désinstaller avant d'installer la version actuelle (à partir de la 2.2.1, les mises à jour s'installent par-dessus). Les données sont dans le cloud et restent accessibles après reconnexion.

## Licence

Projet distribué sous licence MIT : voir le fichier `LICENSE`.
