-- Update 5: a color for each favorite niche.
-- Paste into Supabase > SQL Editor > New query, then click Run. Safe to run more than once.

alter table public.profiles add column if not exists niche_colors jsonb not null default '{}'::jsonb
  check (jsonb_typeof(niche_colors) = 'object');
