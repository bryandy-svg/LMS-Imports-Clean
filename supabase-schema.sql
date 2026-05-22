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
  return_date date,
  payload jsonb not null,
  updated_at timestamptz default now()
);

alter table public.inventory_items add column if not exists po_number text;
alter table public.inventory_items add column if not exists source_from text;
alter table public.inventory_items add column if not exists issue_type text;
alter table public.inventory_items add column if not exists issued_to text;
alter table public.inventory_items add column if not exists issued_from text;
alter table public.inventory_items add column if not exists return_date date;

create index if not exists inventory_items_sku_idx on public.inventory_items (sku);
create index if not exists inventory_items_po_number_idx on public.inventory_items (po_number);
create index if not exists inventory_items_issue_type_idx on public.inventory_items (issue_type);
create index if not exists inventory_items_return_date_idx on public.inventory_items (return_date);
create index if not exists inventory_items_updated_at_idx on public.inventory_items (updated_at desc);

alter table public.inventory_items enable row level security;

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
