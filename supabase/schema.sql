-- =============================================================================
-- Ma Bibliothèque : schéma Supabase
-- À coller une seule fois dans Supabase → SQL Editor → New query → Run.
--
-- Principes de sécurité (Row Level Security) :
--   • chacun ne peut créer, modifier ou supprimer que SA bibliothèque ;
--   • une bibliothèque n'est lisible que par son propriétaire et les personnes
--     avec qui il l'a partagée, en lecture seule ;
--   • les noms des emprunteurs et les notes sont dans une table à part,
--     lisible uniquement par le propriétaire.
-- =============================================================================

-- ---------------------------------------------------------------- profils ---
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text not null unique,
  display_name text not null default '',
  created_at   timestamptz not null default now()
);

-- Un profil est créé automatiquement à l'inscription, et suit les changements d'e-mail.
create or replace function public.handle_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1))
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end $$;

drop trigger if exists on_auth_user_saved on auth.users;
create trigger on_auth_user_saved
  after insert or update of email on auth.users
  for each row execute function public.handle_auth_user();

-- ---------------------------------------------------------------- partages ---
create table if not exists public.shares (
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, viewer_id),
  check (owner_id <> viewer_id)
);
create index if not exists shares_viewer_idx on public.shares (viewer_id);

-- ------------------------------------------------------------------ objets ---
create table if not exists public.items (
  id          uuid primary key,
  owner_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  type        text not null check (type in ('vinyle', 'livre', 'bd')),
  title       text not null,
  creator     text not null default '',
  year        integer,
  publisher   text not null default '',
  series      text not null default '',
  volume      text not null default '',
  genre       text not null default '',
  format      text not null default '',
  identifier  text not null default '',
  condition   text,
  rating      smallint not null default 0 check (rating between 0 and 5),
  wishlist    boolean not null default false,
  -- Visible des personnes avec qui on partage : « prêté », sans dire à qui.
  loaned      boolean not null default false,
  cover_path  text,
  created_at  timestamptz not null,
  updated_at  timestamptz not null,
  -- Suppression « douce » : les autres appareils doivent apprendre qu'un objet a disparu.
  deleted     boolean not null default false,
  -- Horodatage serveur, sert de curseur de synchronisation.
  synced_at   timestamptz not null default clock_timestamp()
);
create index if not exists items_owner_sync_idx on public.items (owner_id, synced_at);

-- Partie privée de chaque objet : jamais visible des autres.
create table if not exists public.items_private (
  item_id    uuid primary key references public.items (id) on delete cascade,
  owner_id   uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  loaned_to  text,
  loan_date  timestamptz,
  notes      text not null default ''
);

create or replace function public.touch_synced_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.synced_at := clock_timestamp();
  return new;
end $$;

drop trigger if exists items_touch on public.items;
create trigger items_touch before insert or update on public.items
  for each row execute function public.touch_synced_at();

-- Le propriétaire d'un objet ne peut pas changer (pas de « don » d'objet à autrui).
create or replace function public.keep_owner()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.owner_id <> old.owner_id then
    raise exception 'Le propriétaire d''un objet ne peut pas être modifié';
  end if;
  return new;
end $$;

drop trigger if exists items_keep_owner on public.items;
create trigger items_keep_owner before update on public.items
  for each row execute function public.keep_owner();
drop trigger if exists items_private_keep_owner on public.items_private;
create trigger items_private_keep_owner before update on public.items_private
  for each row execute function public.keep_owner();

-- ------------------------------------------------------------- RLS : règles ---
alter table public.profiles      enable row level security;
alter table public.shares        enable row level security;
alter table public.items         enable row level security;
alter table public.items_private enable row level security;

-- Vrai si l'utilisateur connecté peut lire la bibliothèque de « owner ».
create or replace function public.can_read_library(owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select owner = auth.uid()
      or exists (select 1 from public.shares s where s.owner_id = owner and s.viewer_id = auth.uid());
$$;

-- Profils : le sien, et ceux des personnes liées par un partage (dans un sens ou dans l'autre).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid()
  or exists (select 1 from public.shares s
             where (s.owner_id = auth.uid() and s.viewer_id = profiles.id)
                or (s.viewer_id = auth.uid() and s.owner_id = profiles.id))
);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- Seul le nom affiché est modifiable (l'e-mail suit le compte).
revoke update on public.profiles from authenticated, anon;
grant update (display_name) on public.profiles to authenticated;

-- Partages : visibles par les deux personnes concernées ; créés uniquement via
-- share_library() ; supprimables par le propriétaire (retrait) ou l'invité (départ).
drop policy if exists shares_select on public.shares;
create policy shares_select on public.shares for select to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());
drop policy if exists shares_delete on public.shares;
create policy shares_delete on public.shares for delete to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());

-- Objets : lecture par le propriétaire et ses invités ; écriture par le propriétaire seul.
drop policy if exists items_select on public.items;
create policy items_select on public.items for select to authenticated
  using (public.can_read_library(owner_id));
drop policy if exists items_insert on public.items;
create policy items_insert on public.items for insert to authenticated
  with check (owner_id = auth.uid());
drop policy if exists items_update on public.items;
create policy items_update on public.items for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated
  using (owner_id = auth.uid());

-- Partie privée : propriétaire uniquement, et seulement pour ses propres objets.
drop policy if exists items_private_all on public.items_private;
create policy items_private_all on public.items_private for all to authenticated
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and exists (select 1 from public.items i where i.id = item_id and i.owner_id = auth.uid())
  );

-- Les visiteurs non connectés n'ont accès à rien.
revoke all on public.profiles, public.shares, public.items, public.items_private from anon;

-- ------------------------------------------------------- fonctions appelables ---

-- Partage sa bibliothèque avec le compte qui a cet e-mail (compte confirmé uniquement).
create or replace function public.share_library(p_email text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare
  target public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Vous devez être connecté' using errcode = '28000';
  end if;
  select p.* into target
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.email = lower(trim(p_email))
     and u.email_confirmed_at is not null;
  if target.id is null then
    raise exception 'Aucun compte Ma Bibliothèque n''utilise cet e-mail' using errcode = 'P0002';
  end if;
  if target.id = auth.uid() then
    raise exception 'Vous ne pouvez pas partager avec vous-même' using errcode = '22023';
  end if;
  insert into public.shares (owner_id, viewer_id) values (auth.uid(), target.id)
    on conflict do nothing;
  return target;
end $$;

-- Supprime le compte et toutes ses données (les couvertures sont effacées par l'application avant).
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Vous devez être connecté' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke execute on function public.share_library(text), public.delete_my_account() from public, anon;
grant execute on function public.share_library(text), public.delete_my_account() to authenticated;
revoke execute on function public.can_read_library(uuid) from public, anon;
grant execute on function public.can_read_library(uuid) to authenticated;

-- -------------------------------------------------------------- couvertures ---
-- Stockage privé ; chaque image est rangée dans un dossier au nom de son propriétaire :
-- covers/<identifiant du propriétaire>/<identifiant de l'objet>.jpg
insert into storage.buckets (id, name, public)
values ('covers', 'covers', false)
on conflict (id) do nothing;

drop policy if exists covers_select on storage.objects;
create policy covers_select on storage.objects for select to authenticated using (
  bucket_id = 'covers'
  and public.can_read_library(((storage.foldername(name))[1])::uuid)
);
drop policy if exists covers_insert on storage.objects;
create policy covers_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists covers_update on storage.objects;
create policy covers_update on storage.objects for update to authenticated
  using (bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists covers_delete on storage.objects;
create policy covers_delete on storage.objects for delete to authenticated using (
  bucket_id = 'covers' and (storage.foldername(name))[1] = auth.uid()::text
);
