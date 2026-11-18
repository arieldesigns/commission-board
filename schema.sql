-- Commission Board: database setup
-- Paste this whole file into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once.

-- 1. Profiles: one row per designer (display name + default currency)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 60),
  default_currency text not null default 'USD' check (default_currency in ('USD', 'EUR', 'GBP')),
  created_at timestamptz not null default now()
);

-- 2. Commissions: every card, tagged with the designer who owns it
create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client text not null check (char_length(client) between 1 and 80),
  description text not null default '' check (char_length(description) <= 1000),
  deadline date,
  price numeric(10, 2) not null default 0 check (price >= 0),
  currency text not null default 'USD' check (currency in ('USD', 'EUR', 'GBP')),
  paid boolean not null default false,
  status text not null default 'commissioned' check (status in ('commissioned', 'progress', 'done')),
  sort_order double precision not null default 1000,
  created_at timestamptz not null default now()
);
create index if not exists commissions_owner_idx on public.commissions (owner);

-- 3. Privacy: turn on Row Level Security so each designer only ever sees their own rows
alter table public.profiles enable row level security;
alter table public.commissions enable row level security;

drop policy if exists "Own profile: read" on public.profiles;
drop policy if exists "Own profile: insert" on public.profiles;
drop policy if exists "Own profile: update" on public.profiles;
create policy "Own profile: read"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "Own profile: insert" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "Own profile: update" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "Own commissions: read" on public.commissions;
drop policy if exists "Own commissions: insert" on public.commissions;
drop policy if exists "Own commissions: update" on public.commissions;
drop policy if exists "Own commissions: delete" on public.commissions;
create policy "Own commissions: read"   on public.commissions for select to authenticated using (owner = (select auth.uid()));
create policy "Own commissions: insert" on public.commissions for insert to authenticated with check (owner = (select auth.uid()));
create policy "Own commissions: update" on public.commissions for update to authenticated using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "Own commissions: delete" on public.commissions for delete to authenticated using (owner = (select auth.uid()));

-- Signed-in users can use the tables (the policies above still limit them to their own rows);
-- signed-out visitors get nothing.
revoke all on public.profiles, public.commissions from anon;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.commissions to authenticated;

-- 4. Create a profile automatically when someone signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 60))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 5. Let a designer delete their own account (and, through the cascades above, all their data)
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- 6. Completion date for the earnings chart (same as migrate-001-completed-at.sql)
alter table public.commissions add column if not exists completed_at timestamptz;

-- Cards that were already Done + Paid before this update: date them by when they were created.
drop trigger if exists commissions_set_completed_at on public.commissions;
update public.commissions
  set completed_at = created_at
  where status = 'done' and paid and completed_at is null;

-- From now on the database sets completed_at itself: stamped the moment a card becomes
-- Done + Paid, kept while it stays that way, cleared if it leaves Done or goes back to Not paid.
create or replace function public.set_completed_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'done' and new.paid then
    if tg_op = 'UPDATE' and old.status = 'done' and old.paid and old.completed_at is not null then
      new.completed_at := old.completed_at;
    else
      new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create trigger commissions_set_completed_at
  before insert or update on public.commissions
  for each row execute function public.set_completed_at();

-- 7. Cleared cards stay saved for earnings (same as migrate-002-archived.sql)
alter table public.commissions add column if not exists archived boolean not null default false;

-- 8. ILS, niche, notes, saved clients (same as migrate-003-clients-niche-notes-ils.sql)
-- Niche (free text) and notes (a list of dated notes) on each commission
alter table public.commissions add column if not exists niche text not null default ''
  check (char_length(niche) <= 60);
alter table public.commissions add column if not exists notes jsonb not null default '[]'::jsonb
  check (jsonb_typeof(notes) = 'array' and jsonb_array_length(notes) <= 100);

-- Saved clients list on each designer's profile (private, like everything else)
alter table public.profiles add column if not exists saved_clients text[] not null default '{}'
  check (cardinality(saved_clients) <= 200);

-- Allow ILS (Israeli shekel) as a currency
alter table public.commissions drop constraint if exists commissions_currency_check;
alter table public.commissions add constraint commissions_currency_check
  check (currency in ('USD', 'EUR', 'GBP', 'ILS'));
alter table public.profiles drop constraint if exists profiles_default_currency_check;
alter table public.profiles add constraint profiles_default_currency_check
  check (default_currency in ('USD', 'EUR', 'GBP', 'ILS'));
