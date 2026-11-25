\set ON_ERROR_STOP 1
-- Utilisateurs (le trigger crée les profils)
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'alice@x.fr', '{"username":"alice","display_name":"Alice"}'),
 ('00000000-0000-0000-0000-00000000000b', 'bob@x.fr',   '{"username":"bob","display_name":"Bob"}'),
 ('00000000-0000-0000-0000-00000000000c', 'carol@x.fr', '{"username":"carol","display_name":"Carol"}');
select 'profils créés' as etape, count(*) from public.profiles;

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, false);
  execute 'set role authenticated';
end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  execute 'set role anon';
end $$;

-- Helper : exécute une requête qui DOIT être refusée (RLS) et vérifie qu'elle n'a rien changé
create or replace function pg_temp.expect_denied(sql text, label text) returns void language plpgsql as $$
declare n int;
begin
  begin
    execute sql;
    get diagnostics n = row_count;
    if n > 0 then raise exception 'ÉCHEC (autorisé alors qu''il ne devait pas) : %', label; end if;
    raise notice 'OK (refusé ou sans effet) : %', label;
  exception when insufficient_privilege or check_violation then
    raise notice 'OK (refusé) : %', label;
  end;
end $$;

-- ---- Alice crée sa bibliothèque
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
with ins as (
  insert into public.items (owner_id, type, title, creator, on_loan, wishlist)
  values (auth.uid(), 'livre', 'Dune', 'Herbert', true, false) returning id)
insert into public.item_private (item_id, owner_id, loaned_to, notes)
select id, auth.uid(), 'Léo', 'Édition dédicacée' from ins;
insert into public.items (owner_id, type, title, creator) values (auth.uid(), 'vinyle', 'Kind of Blue', 'Miles Davis');
select 'alice voit ses objets' as etape, count(*) from public.items;

-- ---- Carol (inconnue) ne voit rien d'Alice
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select 'carol voit les objets d''alice (doit être 0)' as etape, count(*) from public.items where owner_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.expect_denied($q$insert into public.items (owner_id, type, title) values ('00000000-0000-0000-0000-00000000000a','livre','Piratage')$q$, 'carol ajoute dans la bibliothèque d''alice');

-- ---- Alice invite Bob en lecture seule (il a déjà un compte -> partage immédiat)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select 'invitation bob' as etape, public.invite_by_email('bob@x.fr', 'read') as resultat;
select 'liste des partages (alice)' as etape, count(*) from public.shares;

-- ---- Bob (lecture) : voit les objets, PAS les prêts ni les notes, ne peut rien modifier
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select 'bob voit les objets d''alice (attendu 2)' as etape, count(*) from public.items where owner_id = '00000000-0000-0000-0000-00000000000a';
select 'bob voit on_loan=true sans le nom' as etape, title, on_loan from public.items where owner_id = '00000000-0000-0000-0000-00000000000a' and on_loan;
select 'bob voit les infos privées (attendu 0)' as etape, count(*) from public.item_private;
select pg_temp.expect_denied($q$insert into public.items (owner_id, type, title) values ('00000000-0000-0000-0000-00000000000a','livre','Intrus')$q$, 'bob (lecture) ajoute chez alice');
select pg_temp.expect_denied($q$update public.items set title = 'Piraté' where owner_id = '00000000-0000-0000-0000-00000000000a'$q$, 'bob (lecture) modifie chez alice');
select pg_temp.expect_denied($q$delete from public.items where owner_id = '00000000-0000-0000-0000-00000000000a'$q$, 'bob (lecture) supprime chez alice');
select pg_temp.expect_denied($q$insert into public.shares (owner_id, viewer_id, role) values ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000c','write')$q$, 'bob (lecture) s''accorde des droits');

-- ---- Alice passe Bob en « modifier »
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select 'alice passe bob en écriture' as etape, public.invite_by_email('bob@x.fr', 'write') as resultat;
select 'droit de bob' as etape, role from public.shares where viewer_id = '00000000-0000-0000-0000-00000000000b';

select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select 'bob (écriture) voit les infos privées (attendu 1)' as etape, count(*) from public.item_private;
insert into public.items (owner_id, type, title) values ('00000000-0000-0000-0000-00000000000a','bd','Astérix le Gaulois');
select 'bob (écriture) a bien ajouté (attendu 3)' as etape, count(*) from public.items where owner_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.expect_denied($q$insert into public.items (owner_id, type, title) values ('00000000-0000-0000-0000-00000000000c','livre','Chez carol')$q$, 'bob ajoute dans la bibliothèque de carol');

-- ---- Invitation en attente : Dave n'a pas encore de compte
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select 'invitation dave (pas de compte)' as etape, public.invite_by_email('dave@x.fr', 'read') as resultat;
select 'invitation en attente' as etape, email, role from public.invitations;

-- Dave s'inscrit : le trigger convertit l'invitation en partage
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000d', 'dave@x.fr', '{"username":"dave","display_name":"Dave"}');
select 'après inscription de dave : partage créé' as etape, role from public.shares where viewer_id = '00000000-0000-0000-0000-00000000000d';
select 'après inscription de dave : invitation supprimée (attendu 0)' as etape, count(*) from public.invitations;

reset role;
-- Pseudo déjà pris : repli automatique, l'inscription réussit quand même
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000e', 'erin@x.fr', '{"username":"alice","display_name":"Autre Alice"}');
select 'pseudo pris -> repli' as etape, username from public.profiles where id = '00000000-0000-0000-0000-00000000000e';

-- ---- Restauration atomique dans SA bibliothèque (alice)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select 'restauration (fusion) renvoie 2 ids' as etape, count(*) from public.restore_library(
  '[{"type":"vinyle","title":"Abbey Road","creator":"The Beatles","year":1969,"rating":4,"loaned_to":"Marc","loan_date":"2026-10-01T10:00:00Z","notes":"x"},
    {"type":"livre","title":"Emma","creator":"Austen","wishlist":true}]'::jsonb, false);
select 'prêt privé créé' as etape, p.loaned_to from public.item_private p join public.items i on i.id=p.item_id where i.title='Abbey Road';
select 'indicateur de prêt' as etape, on_loan from public.items where title='Abbey Road';
-- Restauration invalide : doit tout annuler
select 'restauration invalide annulée' as etape, 'ok' as resultat;
do $$ begin
  perform * from public.restore_library('[{"type":"vinyle","title":"Bon"},{"type":"INCONNU","title":"Mauvais"}]'::jsonb, false);
  raise exception 'aurait dû échouer';
exception when others then raise notice 'OK : erreur attendue (%)', sqlerrm;
end $$;
select 'après échec : aucun objet "Bon"' as etape, count(*) from public.items where title='Bon';

-- Remplacement : efface l'ancien contenu d'Alice
select 'remplacement' as etape, count(*) from public.restore_library('[{"type":"bd","title":"Seul"}]'::jsonb, true);
select 'après remplacement : objets d''alice (attendu 1)' as etape, count(*) from public.items where owner_id = auth.uid();

-- ---- Alice retire Bob : il ne voit plus rien
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
delete from public.shares where viewer_id = '00000000-0000-0000-0000-00000000000b';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select 'bob après retrait (attendu 0)' as etape, count(*) from public.items where owner_id = '00000000-0000-0000-0000-00000000000a';

-- ---- Bob peut quitter une bibliothèque, mais ne peut pas s'ajouter un droit
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select 'alice rend visible dave' as etape, public.invite_by_email('dave@x.fr', 'write') as resultat;

-- ---- Anonyme : rien du tout
select pg_temp.as_anon();
select 'anonyme voit les objets (attendu 0)' as etape, count(*) from public.items;
select 'anonyme voit les profils (attendu 0)' as etape, count(*) from public.profiles;
reset role;
