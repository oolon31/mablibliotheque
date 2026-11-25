# Tests des règles d'accès (sans toucher au serveur réel)

Ils s'exécutent sur un PostgreSQL local, avec une imitation minimale de Supabase (`0_shim_local.sql`).

```bash
createdb bib
psql bib -v ON_ERROR_STOP=1 -f supabase/tests/0_shim_local.sql
psql bib -v ON_ERROR_STOP=1 -f supabase/schema.sql
psql bib -v ON_ERROR_STOP=1 -f supabase/tests/1_acces.sql
psql bib -v ON_ERROR_STOP=1 -f supabase/tests/2_couvertures.sql
```

Chaque refus attendu affiche `OK` ; un accès non autorisé arrête le test avec `ÉCHEC`.
