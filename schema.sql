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
