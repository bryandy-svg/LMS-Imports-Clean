-- Fix password-free mobile request submission after the inventory security upgrade.
-- Additive and non-destructive: no requests or inventory records are deleted.

begin;

alter table public.inventory_requests enable row level security;

-- Anonymous visitors may create pending requests only. They cannot read, change,
-- approve, deny, or delete requests through the Data API.
drop policy if exists "Allow anon insert requests" on public.inventory_requests;
drop policy if exists "Public users submit pending requests" on public.inventory_requests;

create policy "Public users submit pending requests"
on public.inventory_requests
for insert
to anon
with check (
  lower(coalesce(status, 'pending')) = 'pending'
  and coalesce(approved_by, '') = ''
);

grant insert on table public.inventory_requests to anon;
revoke select, update, delete on table public.inventory_requests from anon;

-- Signed-in users assigned Requests (and the primary administrator) can load the
-- complete request register immediately. This policy checks both current access
-- assignments and JWT app metadata so newly assigned access does not depend on a
-- stale browser token.
grant select on table public.inventory_requests to authenticated;

drop policy if exists "Assigned users read requests" on public.inventory_requests;
create policy "Assigned users read requests"
on public.inventory_requests
for select
to authenticated
using (
  lower(coalesce((select auth.jwt())->>'email', '')) = 'bryan.dy@lmsfm.com'
  or coalesce((select auth.jwt())->'app_metadata'->'access', '[]'::jsonb) ?| array['requests','manage_users']
  or exists (
    select 1
    from public.user_access ua
    where ua.user_id = (select auth.uid())
      and ua.access && array['requests','manage_users']::text[]
  )
);

commit;
