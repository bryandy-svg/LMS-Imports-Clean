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

commit;
