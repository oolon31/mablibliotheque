\set ON_ERROR_STOP 1
reset role;
insert into storage.objects (bucket_id, name) values ('covers', '00000000-0000-0000-0000-00000000000a/1_abc.jpg');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false); set role authenticated;
select 'alice voit sa couverture (1)' as etape, count(*) from storage.objects where bucket_id='covers';
reset role; select set_config('request.jwt.claim.sub', '', false);
-- Bob : a un partage en écriture avec Alice (rétabli pour le test)
insert into public.shares (owner_id, viewer_id, role) values ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b','read') on conflict do nothing;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false); set role authenticated;
select 'bob (lecture) voit la couverture (attendu 1)' as etape, count(*) from storage.objects where bucket_id='covers';
select 'bob (lecture) ne peut pas en ajouter' as etape;
do $$ begin insert into storage.objects (bucket_id, name) values ('covers','00000000-0000-0000-0000-00000000000a/intrus.jpg'); raise exception 'ÉCHEC'; exception when insufficient_privilege or others then if sqlerrm = 'ÉCHEC' then raise; end if; raise notice 'OK refusé: %', sqlerrm; end $$;
reset role; select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false); set role authenticated;
select 'carol (inconnue) ne voit rien (attendu 0)' as etape, count(*) from storage.objects where bucket_id='covers';
reset role;
