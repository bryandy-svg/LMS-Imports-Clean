-- Add Jobsite to Piti Greenwaste tickets without deleting or replacing any data.
alter table public.greenwaste_tickets
  add column if not exists jobsite text;

create index if not exists greenwaste_tickets_jobsite_idx
  on public.greenwaste_tickets (jobsite);

-- Backfill only blank Jobsite columns when an older JSON payload already has one.
update public.greenwaste_tickets
set jobsite = nullif(payload->>'jobsite', '')
where jobsite is null
  and nullif(payload->>'jobsite', '') is not null;
