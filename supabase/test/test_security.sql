-- Scénarios de sécurité : chaque bloc agit sous l'identité d'un utilisateur.
-- Lancer avec : supabase/test/run.sh
\set ON_ERROR_STOP 1
\set QUIET 1

-- Comptes : Alice et Bob confirmés, Carole confirmée sans partage, Ève non confirmée.
reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'Alice@Exemple.fr', now(), '{"display_name": "Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@exemple.fr',   now(), '{}'),
  ('00000000-0000-0000-0000-00000000000c', 'carole@exemple.fr', now(), '{}'),
  ('00000000-0000-0000-0000-00000000000e', 'eve@exemple.fr',   null,  '{}');

\echo '1. Profils créés automatiquement, e-mail en minuscules, nom par défaut'
do $$ begin
  assert (select count(*) from public.profiles) = 4, 'quatre profils';
  assert (select email from public.profiles where display_name = 'Alice') = 'alice@exemple.fr', 'e-mail en minuscules';
  assert (select display_name from public.profiles where email = 'bob@exemple.fr') = 'bob', 'nom par défaut';
end $$;

-- Alice : deux objets, dont un prêté avec une note privée.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
set role authenticated;
insert into public.items (id, type, title, creator, loaned, created_at, updated_at) values
  ('10000000-0000-0000-0000-000000000001', 'vinyle', 'Kind of Blue', 'Miles Davis', true, now(), now()),
  ('10000000-0000-0000-0000-000000000002', 'bd', 'Blacksad', 'Guarnido', false, now(), now());
insert into public.items_private (item_id, loaned_to, notes) values
  ('10000000-0000-0000-0000-000000000001', 'Camille', 'pressage original');
insert into storage.objects (bucket_id, name) values
  ('covers', '00000000-0000-0000-0000-00000000000a/10000000-0000-0000-0000-000000000001.jpg');

\echo '2. Alice voit ses objets et ses données privées'
do $$ begin
  assert (select count(*) from public.items) = 2, 'Alice voit 2 objets';
  assert (select loaned_to from public.items_private) = 'Camille', 'Alice voit à qui elle a prêté';
  assert (select owner_id from public.items limit 1) = auth.uid(), 'propriétaire rempli automatiquement';
end $$;

\echo '3. Alice ne peut pas créer un objet au nom de Bob'
do $$ begin
  begin
    insert into public.items (id, owner_id, type, title, created_at, updated_at)
    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b', 'livre', 'Faux', now(), now());
    raise exception 'ÉCHEC : insertion au nom de Bob acceptée';
  exception when insufficient_privilege then null;
  end;
end $$;

\echo '4. Alice ne peut pas déposer une image dans le dossier de Bob'
do $$ begin
  begin
    insert into storage.objects (bucket_id, name) values ('covers', '00000000-0000-0000-0000-00000000000b/x.jpg');
    raise exception 'ÉCHEC : image déposée chez Bob';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Bob, avant tout partage.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \g /dev/null
set role authenticated;
\echo '5. Sans partage, Bob ne voit rien d''Alice (objets, privé, images, profil)'
do $$ begin
  assert (select count(*) from public.items) = 0, 'Bob ne voit aucun objet';
  assert (select count(*) from public.items_private) = 0, 'Bob ne voit aucune donnée privée';
  assert (select count(*) from storage.objects) = 0, 'Bob ne voit aucune image';
  assert (select count(*) from public.profiles) = 1, 'Bob ne voit que son profil';
end $$;

\echo '6. Bob ne peut pas se donner accès lui-même'
do $$ begin
  begin
    insert into public.shares (owner_id, viewer_id) values ('00000000-0000-0000-0000-00000000000a', auth.uid());
    raise exception 'ÉCHEC : Bob a créé un partage à sa place';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Alice partage avec Bob.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
set role authenticated;
\echo '7. Partage : e-mail inconnu, non confirmé, soi-même refusés ; e-mail de Bob accepté (casse ignorée)'
do $$
declare p public.profiles;
begin
  begin perform public.share_library('inconnu@exemple.fr'); raise exception 'ÉCHEC inconnu';
  exception when no_data_found then null; end;
  begin perform public.share_library('eve@exemple.fr'); raise exception 'ÉCHEC non confirmé';
  exception when no_data_found then null; end;
  begin perform public.share_library('alice@exemple.fr'); raise exception 'ÉCHEC soi-même';
  exception when invalid_parameter_value then null; end;
  p := public.share_library('  BOB@exemple.fr ');
  assert p.display_name = 'bob', 'renvoie le profil de Bob';
  perform public.share_library('bob@exemple.fr'); -- deux fois : sans erreur
  assert (select count(*) from public.shares) = 1, 'un seul partage';
  assert (select count(*) from public.profiles) = 2, 'Alice voit le profil de Bob';
end $$;

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \g /dev/null
set role authenticated;
\echo '8. Avec le partage, Bob lit les objets et les images d''Alice, mais pas le privé'
do $$ begin
  assert (select count(*) from public.items) = 2, 'Bob voit les 2 objets';
  assert (select loaned from public.items where title = 'Kind of Blue'), 'Bob voit « prêté »';
  assert (select count(*) from public.items_private) = 0, 'Bob ne voit pas à qui';
  assert (select count(*) from storage.objects) = 1, 'Bob voit la couverture';
  assert (select display_name from public.profiles where id <> auth.uid()) = 'Alice', 'Bob voit le nom d''Alice';
end $$;

\echo '9. Bob ne peut ni modifier ni supprimer les objets d''Alice, ni changer d''e-mail'
do $$
declare n int;
begin
  update public.items set title = 'Piraté' where true;
  get diagnostics n = row_count;
  assert n = 0, 'aucune modification';
  delete from public.items where true;
  get diagnostics n = row_count;
  assert n = 0, 'aucune suppression';
  delete from storage.objects where true;
  get diagnostics n = row_count;
  assert n = 0, 'aucune image supprimée';
  begin
    update public.profiles set email = 'pirate@exemple.fr' where id = auth.uid();
    raise exception 'ÉCHEC : e-mail modifiable';
  exception when insufficient_privilege then null;
  end;
  update public.profiles set display_name = 'Bobby' where id = auth.uid();
  update public.profiles set display_name = 'Piratée' where id <> auth.uid();
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.items where title = 'Piraté') = 0, 'titres intacts';
  assert (select display_name from public.profiles where email = 'bob@exemple.fr') = 'Bobby', 'Bob change son nom';
  assert (select display_name from public.profiles where email = 'alice@exemple.fr') = 'Alice', 'nom d''Alice intact';
end $$;

\echo '10. Carole (sans partage) ne voit toujours rien'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false) \g /dev/null
set role authenticated;
do $$ begin
  assert (select count(*) from public.items) = 0, 'Carole ne voit rien';
  assert (select count(*) from public.shares) = 0, 'Carole ne voit pas les partages des autres';
end $$;

\echo '11. Un objet ne peut pas changer de propriétaire'
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
set role authenticated;
do $$ begin
  begin
    update public.items set owner_id = '00000000-0000-0000-0000-00000000000b' where title = 'Blacksad';
    raise exception 'ÉCHEC : objet donné';
  exception when insufficient_privilege or raise_exception then
    if sqlerrm like 'ÉCHEC%' then raise; end if;
  end;
end $$;

\echo '12. Le curseur de synchronisation avance à chaque modification'
do $$
declare before timestamptz;
begin
  select synced_at into before from public.items where title = 'Blacksad';
  update public.items set rating = 5, updated_at = now() where title = 'Blacksad';
  assert (select synced_at from public.items where title = 'Blacksad') > before, 'synced_at avance';
end $$;

\echo '13. Alice retire l''accès : Bob ne voit plus rien'
delete from public.shares where viewer_id = '00000000-0000-0000-0000-00000000000b';
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \g /dev/null
set role authenticated;
do $$ begin
  assert (select count(*) from public.items) = 0, 'accès retiré';
  assert (select count(*) from storage.objects) = 0, 'images inaccessibles';
end $$;

\echo '14. Un invité peut quitter un partage'
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
set role authenticated;
select public.share_library('bob@exemple.fr') \g /dev/null
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \g /dev/null
set role authenticated;
do $$
declare n int;
begin
  assert (select count(*) from public.items) = 2, 'accès rétabli';
  delete from public.shares where owner_id = '00000000-0000-0000-0000-00000000000a';
  get diagnostics n = row_count;
  assert n = 1, 'Bob quitte le partage';
  assert (select count(*) from public.items) = 0, 'plus d''accès';
end $$;

\echo '15. Un visiteur non connecté n''a accès à rien'
reset role;
select set_config('request.jwt.claim.sub', '', false) \g /dev/null
set role anon;
do $$ begin
  begin
    perform count(*) from public.items;
    raise exception 'ÉCHEC : anon lit les objets';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.share_library('bob@exemple.fr');
    raise exception 'ÉCHEC : anon partage';
  exception when insufficient_privilege then null;
  end;
end $$;

\echo '16. Suppression de compte : toutes les données d''Alice disparaissent'
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
set role authenticated;
select public.delete_my_account() \g /dev/null
reset role;
do $$ begin
  assert not exists (select 1 from auth.users where email = 'alice@exemple.fr'), 'compte supprimé';
  assert (select count(*) from public.items) = 0, 'objets supprimés';
  assert (select count(*) from public.items_private) = 0, 'données privées supprimées';
  assert (select count(*) from public.profiles) = 3, 'profil supprimé';
end $$;

\echo 'TOUS LES SCÉNARIOS DE SÉCURITÉ SONT PASSÉS'
