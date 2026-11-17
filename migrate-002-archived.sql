-- Update 2: "Clear paid" hides finished cards instead of deleting them,
-- so they still count in your earnings and the Summary chart.
-- Paste into Supabase > SQL Editor > New query, then click Run. Safe to run more than once.

alter table public.commissions add column if not exists archived boolean not null default false;
