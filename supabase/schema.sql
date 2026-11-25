-- =============================================================================
-- Ma Bibliothèque : schéma, règles d'accès et stockage des couvertures.
-- À coller entièrement dans Supabase → SQL Editor → Run. Peut être relancé.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text not null unique check (char_length(username) between 3 and 30),
  display_name text not null default '',
  created_at   timestamptz not null default now()
);

-- Objets d'une bibliothèque. Le propriétaire est owner_id.
create table if not exists public.items (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  type        text not null check (type in ('vinyle', 'livre', 'bd')),
  title       text not null check (char_length(title) between 1 and 300),
  creator     text not null default '',
  year        int,
  publisher   text not null default '',
  series      text not null default '',
  volume      text not null default '',
  genre       text not null default '',
  format      text not null default '',
  identifier  text not null default '',
  condition   text check (condition in ('neuf', 'tresBon', 'bon', 'moyen', 'abime')),
  rating      int not null default 0 check (rating between 0 and 5),
  wishlist    boolean not null default false,
  -- Visible par les lecteurs : « prêté » oui/non, sans le nom de l'emprunteur.
  on_loan     boolean not null default false,
  cover_path  text,                       -- chemin dans le bucket « covers », ex. <owner>/<id>.jpg
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Informations privées : nom de l'emprunteur, date de prêt, notes.
-- Seuls le propriétaire et les invités en écriture peuvent les lire.
create table if not exists public.item_private (
  item_id    bigint primary key references public.items(id) on delete cascade,
  owner_id   uuid not null references auth.users(id) on delete cascade,
  loaned_to  text,
  loan_date  timestamptz,
  notes      text not null default ''
);

-- Partages effectifs : viewer_id peut consulter (read) ou modifier (write) la bibliothèque de owner_id.
create table if not exists public.shares (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  role       text not null check (role in ('read', 'write')),
  created_at timestamptz not null default now(),
  primary key (owner_id, viewer_id),
  check (owner_id <> viewer_id)
);

-- Invitations envoyées à une adresse qui n'a pas encore de compte.
-- Convertie automatiquement en partage à l'inscription (voir handle_new_user).
create table if not exists public.invitations (
  owner_id   uuid not null references auth.users(id) on delete cascade,
  email      text not null,
  role       text not null check (role in ('read', 'write')),
  created_at timestamptz not null default now(),
  primary key (owner_id, email)
);

create index if not exists items_owner_idx on public.items(owner_id);
create index if not exists shares_viewer_idx on public.shares(viewer_id);
create index if not exists invitations_email_idx on public.invitations(lower(email));

-- ---------------------------------------------------------------------------
-- Fonctions d'accès (SECURITY DEFINER : évitent la récursion des règles RLS)
-- ---------------------------------------------------------------------------

create or replace function public.can_read(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select owner = auth.uid()
      or exists (select 1 from public.shares s
                 where s.owner_id = owner and s.viewer_id = auth.uid());
$$;

create or replace function public.can_write(owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select owner = auth.uid()
      or exists (select 1 from public.shares s
                 where s.owner_id = owner and s.viewer_id = auth.uid() and s.role = 'write');
$$;

-- Inviter quelqu'un par e-mail. Renvoie 'shared' si le compte existe déjà, 'pending' sinon.
create or replace function public.invite_by_email(invitee text, invitee_role text)
returns text language plpgsql security definer set search_path = public as $$
declare
  target uuid;
  clean text := lower(trim(invitee));
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if invitee_role not in ('read', 'write') then
    raise exception 'Droit inconnu';
  end if;
  if clean = '' or position('@' in clean) = 0 then
    raise exception 'Adresse e-mail invalide';
  end if;

  select id into target from auth.users where lower(email) = clean;
  if target is null then
    insert into public.invitations (owner_id, email, role)
    values (auth.uid(), clean, invitee_role)
    on conflict (owner_id, email) do update set role = excluded.role;
    return 'pending';
  end if;
  if target = auth.uid() then
    raise exception 'Vous ne pouvez pas vous inviter vous-même';
  end if;
  insert into public.shares (owner_id, viewer_id, role)
  values (auth.uid(), target, invitee_role)
  on conflict (owner_id, viewer_id) do update set role = excluded.role;
  return 'shared';
end;
$$;

-- Création du profil à l'inscription, et conversion des invitations en attente.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  wanted text := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));
  name   text := coalesce(new.raw_user_meta_data ->> 'display_name', '');
begin
  if char_length(wanted) < 3 or char_length(wanted) > 30 or exists (select 1 from public.profiles where username = wanted) then
    wanted := 'user_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  insert into public.profiles (id, username, display_name) values (new.id, wanted, name);

  insert into public.shares (owner_id, viewer_id, role)
  select i.owner_id, new.id, i.role from public.invitations i
  where lower(i.email) = lower(new.email) and i.owner_id <> new.id
  on conflict (owner_id, viewer_id) do nothing;

  delete from public.invitations where lower(email) = lower(new.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Règles d'accès (RLS)
-- ---------------------------------------------------------------------------

alter table public.profiles     enable row level security;
alter table public.items        enable row level security;
alter table public.item_private enable row level security;
alter table public.shares       enable row level security;
alter table public.invitations  enable row level security;

-- Profils : lisibles par tous les connectés (pour afficher les noms), modifiables par soi seul.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Objets : lecture pour le propriétaire et les invités ; écriture pour le propriétaire et les invités « write ».
drop policy if exists items_select on public.items;
create policy items_select on public.items for select to authenticated using (public.can_read(owner_id));
drop policy if exists items_insert on public.items;
create policy items_insert on public.items for insert to authenticated with check (public.can_write(owner_id));
drop policy if exists items_update on public.items;
create policy items_update on public.items for update to authenticated
  using (public.can_write(owner_id)) with check (public.can_write(owner_id));
drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated using (public.can_write(owner_id));

-- Informations privées : seulement propriétaire et invités « write ».
drop policy if exists private_all on public.item_private;
create policy private_all on public.item_private for all to authenticated
  using (public.can_write(owner_id)) with check (public.can_write(owner_id));

-- Partages : le propriétaire gère ses partages ; un invité peut se retirer.
drop policy if exists shares_select on public.shares;
create policy shares_select on public.shares for select to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());
drop policy if exists shares_insert on public.shares;
create policy shares_insert on public.shares for insert to authenticated
  with check (owner_id = auth.uid());
drop policy if exists shares_update on public.shares;
create policy shares_update on public.shares for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists shares_delete on public.shares;
create policy shares_delete on public.shares for delete to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());

-- Invitations : le propriétaire seul.
drop policy if exists invitations_all on public.invitations;
create policy invitations_all on public.invitations for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Couvertures : bucket privé « covers », chemin <owner_id>/<item_id>.<ext>
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covers', 'covers', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set public = false, file_size_limit = 5242880;

drop policy if exists covers_select on storage.objects;
create policy covers_select on storage.objects for select to authenticated
  using (bucket_id = 'covers' and public.can_read(((storage.foldername(name))[1])::uuid));
drop policy if exists covers_insert on storage.objects;
create policy covers_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'covers' and public.can_write(((storage.foldername(name))[1])::uuid));
drop policy if exists covers_update on storage.objects;
create policy covers_update on storage.objects for update to authenticated
  using (bucket_id = 'covers' and public.can_write(((storage.foldername(name))[1])::uuid));
drop policy if exists covers_delete on storage.objects;
create policy covers_delete on storage.objects for delete to authenticated
  using (bucket_id = 'covers' and public.can_write(((storage.foldername(name))[1])::uuid));

-- ---------------------------------------------------------------------------
-- Restauration atomique d'une sauvegarde dans SA bibliothèque.
-- payload : tableau JSON d'objets (champs de la sauvegarde, cover_path déjà envoyé).
-- Renvoie les identifiants créés, dans l'ordre du fichier.
-- ---------------------------------------------------------------------------
create or replace function public.restore_library(payload jsonb, replace_all boolean)
returns setof bigint language plpgsql security invoker set search_path = public as $$
declare
  r record;
  new_id bigint;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  if replace_all then
    delete from public.items where owner_id = auth.uid();
  end if;
  for r in
    select * from jsonb_to_recordset(payload) as x(
      type text, title text, creator text, year int, publisher text, series text, volume text,
      genre text, format text, identifier text, condition text, rating int, wishlist boolean,
      loaned_to text, loan_date timestamptz, notes text, cover_path text)
  loop
    insert into public.items (owner_id, type, title, creator, year, publisher, series, volume, genre,
                              format, identifier, condition, rating, wishlist, on_loan, cover_path)
    values (auth.uid(), r.type, r.title, coalesce(r.creator, ''), r.year, coalesce(r.publisher, ''),
            coalesce(r.series, ''), coalesce(r.volume, ''), coalesce(r.genre, ''), coalesce(r.format, ''),
            coalesce(r.identifier, ''), r.condition, coalesce(r.rating, 0), coalesce(r.wishlist, false),
            coalesce(r.loaned_to, '') <> '', r.cover_path)
    returning id into new_id;

    insert into public.item_private (item_id, owner_id, loaned_to, loan_date, notes)
    values (new_id, auth.uid(), nullif(r.loaned_to, ''), r.loan_date, coalesce(r.notes, ''));

    return next new_id;
  end loop;
end;
$$;

-- Types d'objets : livres, BD, vinyles, DVD et Blu-ray (idempotent).
alter table public.items drop constraint if exists items_type_check;
alter table public.items add constraint items_type_check
  check (type in ('vinyle', 'livre', 'bd', 'dvd', 'bluray'));

-- ---------------------------------------------------------------------------
-- Droits de base. Les nouveaux projets Supabase n'accordent plus rien automatiquement :
-- sans ces lignes, l'application reçoit « permission denied » (code 42501).
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.items, public.item_private,
  public.shares, public.invitations to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.can_read(uuid), public.can_write(uuid),
  public.invite_by_email(text, text), public.restore_library(jsonb, boolean) to authenticated;
-- Le rôle « anon » (non connecté) n'a aucun droit sur les données.
revoke all on all tables in schema public from anon;
