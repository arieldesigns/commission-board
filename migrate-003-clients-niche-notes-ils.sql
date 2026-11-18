-- Update 3: ILS currency, thumbnail niche, notes on each card, saved clients list.
-- Paste into Supabase > SQL Editor > New query, then click Run. Safe to run more than once.

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
