/// Serveur Supabase de l'application. La clé « publishable » est publique par conception :
/// la sécurité repose sur les règles d'accès de la base (voir supabase/schema.sql).
const supabaseUrl = 'https://bkeevceuotqskpamjpig.supabase.co';
const supabasePublishableKey = 'sb_publishable_MVnT8mFWvJJqcn9eIn3oOA_TE4WBeLl';

/// Adresse de retour du lien de réinitialisation. Doit figurer dans Supabase :
/// Authentication → URL Configuration → Redirect URLs.
const passwordResetRedirect = 'fr.mabibliotheque://reset-password';
