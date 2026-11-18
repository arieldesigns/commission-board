-- Update 4: favorite niches list (dropdown in the Niche field).
-- Paste into Supabase > SQL Editor > New query, then click Run. Safe to run more than once.

alter table public.profiles add column if not exists saved_niches text[] not null default '{}'
  check (cardinality(saved_niches) <= 200);
