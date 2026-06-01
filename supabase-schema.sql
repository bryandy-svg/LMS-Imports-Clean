create table if not exists public.inventory_items (
  id uuid primary key,
  name text,
  sku text,
  quantity numeric default 0,
  po_number text,
  source_from text,
  issue_type text,
  issued_to text,
  issued_from text,
  issued_quantity numeric default 0,
  issue_purpose text,
  approved_by text,
  signature_name text,
  signature_data text,
  issue_po_number text,
  company text,
  authorization_ref text,
  return_date date,
  returned_date date,
  condition_out text,
  condition_in text,
  return_status text,
  payload jsonb not null,
  updated_at timestamptz default now()
);

alter table public.inventory_items add column if not exists po_number text;
alter table public.inventory_items add column if not exists source_from text;
alter table public.inventory_items add column if not exists issue_type text;
alter table public.inventory_items add column if not exists issued_to text;
alter table public.inventory_items add column if not exists issued_from text;
alter table public.inventory_items add column if not exists issued_quantity numeric default 0;
alter table public.inventory_items add column if not exists issue_purpose text;
alter table public.inventory_items add column if not exists approved_by text;
alter table public.inventory_items add column if not exists signature_name text;
alter table public.inventory_items add column if not exists signature_data text;
alter table public.inventory_items add column if not exists issue_po_number text;
alter table public.inventory_items add column if not exists company text;
alter table public.inventory_items add column if not exists authorization_ref text;
alter table public.inventory_items add column if not exists return_date date;
alter table public.inventory_items add column if not exists returned_date date;
alter table public.inventory_items add column if not exists condition_out text;
alter table public.inventory_items add column if not exists condition_in text;
alter table public.inventory_items add column if not exists return_status text;

create index if not exists inventory_items_sku_idx on public.inventory_items (sku);
create index if not exists inventory_items_po_number_idx on public.inventory_items (po_number);
create index if not exists inventory_items_issue_type_idx on public.inventory_items (issue_type);
create index if not exists inventory_items_return_date_idx on public.inventory_items (return_date);
create index if not exists inventory_items_issued_to_idx on public.inventory_items (issued_to);
create index if not exists inventory_items_return_status_idx on public.inventory_items (return_status);
create index if not exists inventory_items_updated_at_idx on public.inventory_items (updated_at desc);

alter table public.inventory_items enable row level security;

drop policy if exists "Allow anon read inventory" on public.inventory_items;
drop policy if exists "Allow anon upsert inventory" on public.inventory_items;
drop policy if exists "Allow anon update inventory" on public.inventory_items;

create policy "Allow anon read inventory"
on public.inventory_items
for select
to anon
using (true);

create policy "Allow anon upsert inventory"
on public.inventory_items
for insert
to anon
with check (true);

create policy "Allow anon update inventory"
on public.inventory_items
for update
to anon
using (true)
with check (true);

drop policy if exists "Allow anon delete inventory" on public.inventory_items;

create policy "Allow anon delete inventory"
on public.inventory_items
for delete
to anon
using (true);

create table if not exists public.inventory_requests (
  id uuid primary key,
  item_id uuid,
  request_type text,
  item_name text,
  sku text,
  requested_by text,
  jobsite text,
  approved_by text,
  signature_name text,
  signature_data text,
  photo_data text,
  return_date date,
  issue_po_number text,
  quantity numeric default 0,
  unit text,
  company text,
  status text default 'Pending',
  items jsonb default '[]'::jsonb,
  payload jsonb not null,
  updated_at timestamptz default now()
);

alter table public.inventory_requests add column if not exists item_id uuid;
alter table public.inventory_requests add column if not exists request_type text;
alter table public.inventory_requests add column if not exists item_name text;
alter table public.inventory_requests add column if not exists sku text;
alter table public.inventory_requests add column if not exists requested_by text;
alter table public.inventory_requests add column if not exists jobsite text;
alter table public.inventory_requests add column if not exists approved_by text;
alter table public.inventory_requests add column if not exists signature_name text;
alter table public.inventory_requests add column if not exists signature_data text;
alter table public.inventory_requests add column if not exists photo_data text;
alter table public.inventory_requests add column if not exists return_date date;
alter table public.inventory_requests add column if not exists issue_po_number text;
alter table public.inventory_requests add column if not exists quantity numeric default 0;
alter table public.inventory_requests add column if not exists unit text;
alter table public.inventory_requests add column if not exists company text;
alter table public.inventory_requests add column if not exists status text default 'Pending';
alter table public.inventory_requests add column if not exists items jsonb default '[]'::jsonb;
alter table public.inventory_requests add column if not exists payload jsonb;
alter table public.inventory_requests add column if not exists updated_at timestamptz default now();

create index if not exists inventory_requests_item_id_idx on public.inventory_requests (item_id);
create index if not exists inventory_requests_status_idx on public.inventory_requests (status);
create index if not exists inventory_requests_updated_at_idx on public.inventory_requests (updated_at desc);

alter table public.inventory_requests enable row level security;

drop policy if exists "Allow anon read requests" on public.inventory_requests;
drop policy if exists "Allow anon insert requests" on public.inventory_requests;
drop policy if exists "Allow anon update requests" on public.inventory_requests;
drop policy if exists "Allow anon delete requests" on public.inventory_requests;

create policy "Allow anon read requests"
on public.inventory_requests
for select
to anon
using (true);

create policy "Allow anon insert requests"
on public.inventory_requests
for insert
to anon
with check (true);

create policy "Allow anon update requests"
on public.inventory_requests
for update
to anon
using (true)
with check (true);

create policy "Allow anon delete requests"
on public.inventory_requests
for delete
to anon
using (true);
