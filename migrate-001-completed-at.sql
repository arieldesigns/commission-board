-- Update 1: track when a commission was completed (Done + Paid) for the earnings chart.
-- Paste into Supabase > SQL Editor > New query, then click Run. Safe to run more than once.

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
