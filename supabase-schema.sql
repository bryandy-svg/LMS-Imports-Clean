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

-- Dedicated authenticated user access and Piti Greenwaste ticket storage.
-- This section is additive: it does not delete or modify inventory/request rows.

create table if not exists public.user_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  access text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_access_values_check check (
    access <@ array['dashboard','inventory','issued','borrowed','requests','greenwaste','alerts','settings','manage_users']::text[]
  )
);

create table if not exists public.greenwaste_tickets (
  id uuid primary key,
  ticket_number text not null unique,
  driver_name text not null,
  ticket_at timestamptz not null,
  truck_number text not null,
  plate_number text not null,
  cubic_yards numeric(12,2) not null default 0 check (cubic_yards >= 0),
  materials text not null,
  customer_name text not null,
  email_address text,
  contact_number text,
  jobsite text,
  building_number text,
  gross_weight numeric(14,2) not null default 0 check (gross_weight >= 0),
  tare_weight numeric(14,2) not null default 0 check (tare_weight >= 0),
  net_weight numeric(14,2) not null default 0 check (net_weight >= 0),
  tons numeric(14,3) not null default 0 check (tons >= 0),
  billing_unit text,
  billing_quantity numeric(14,3) not null default 0 check (billing_quantity >= 0),
  billing_rate numeric(14,2) not null default 0 check (billing_rate >= 0),
  billing_amount numeric(14,2) not null default 0 check (billing_amount >= 0),
  driver_signature text,
  customer_signature text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

-- Additive upgrade for databases that already have the ticket table.
-- Existing ticket rows and payloads are preserved.
alter table public.greenwaste_tickets add column if not exists jobsite text;
alter table public.greenwaste_tickets add column if not exists email_address text;
alter table public.greenwaste_tickets add column if not exists contact_number text;
alter table public.greenwaste_tickets add column if not exists billing_unit text;
alter table public.greenwaste_tickets add column if not exists billing_quantity numeric(14,3) not null default 0;
alter table public.greenwaste_tickets add column if not exists billing_rate numeric(14,2) not null default 0;
alter table public.greenwaste_tickets add column if not exists billing_amount numeric(14,2) not null default 0;

create index if not exists greenwaste_tickets_ticket_at_idx on public.greenwaste_tickets (ticket_at desc);
create index if not exists greenwaste_tickets_customer_name_idx on public.greenwaste_tickets (customer_name);
create index if not exists greenwaste_tickets_jobsite_idx on public.greenwaste_tickets (jobsite);
create index if not exists greenwaste_tickets_truck_number_idx on public.greenwaste_tickets (truck_number);
create index if not exists greenwaste_tickets_created_by_idx on public.greenwaste_tickets (created_by);
create index if not exists user_access_created_by_idx on public.user_access (created_by);

alter table public.user_access enable row level security;
alter table public.greenwaste_tickets enable row level security;

revoke all on table public.user_access from anon;
revoke all on table public.greenwaste_tickets from anon;
grant select on table public.user_access to authenticated;
grant select, insert, update, delete on table public.greenwaste_tickets to authenticated;

drop policy if exists "Users read own access" on public.user_access;
drop policy if exists "User managers read access" on public.user_access;
drop policy if exists "Users read permitted access rows" on public.user_access;
create policy "Users read permitted access rows" on public.user_access
for select to authenticated
using (
  (select auth.uid()) = user_id
  or coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'manage_users'
);

drop policy if exists "Greenwaste users read tickets" on public.greenwaste_tickets;
create policy "Greenwaste users read tickets" on public.greenwaste_tickets
for select to authenticated
using (coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'greenwaste');

drop policy if exists "Greenwaste users create tickets" on public.greenwaste_tickets;
create policy "Greenwaste users create tickets" on public.greenwaste_tickets
for insert to authenticated
with check (
  coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'greenwaste'
  and created_by = (select auth.uid())
);

drop policy if exists "Greenwaste users update tickets" on public.greenwaste_tickets;
create policy "Greenwaste users update tickets" on public.greenwaste_tickets
for update to authenticated
using (coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'greenwaste')
with check (coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'greenwaste');

drop policy if exists "Greenwaste users delete tickets" on public.greenwaste_tickets;
create policy "Greenwaste users delete tickets" on public.greenwaste_tickets
for delete to authenticated
using (coalesce((select auth.jwt()) -> 'app_metadata' -> 'access', '[]'::jsonb) ? 'greenwaste');

-- Copy any legacy Greenwaste JSON records into the dedicated table.
-- ON CONFLICT prevents duplicates; original inventory_requests rows are preserved.
insert into public.greenwaste_tickets (
  id, ticket_number, driver_name, ticket_at, truck_number, plate_number,
  cubic_yards, materials, customer_name, email_address, contact_number, jobsite, building_number,
  gross_weight, tare_weight, net_weight, tons, billing_unit, billing_quantity, billing_rate, billing_amount,
  driver_signature, customer_signature, created_at, updated_at, payload
)
select
  id,
  coalesce(nullif(payload->>'ticketNumber',''), 'LEGACY-' || id::text),
  coalesce(nullif(payload->>'driverName',''), 'Unknown'),
  coalesce(nullif(payload->>'createdAt','')::timestamptz, updated_at, now()),
  coalesce(nullif(payload->>'truckNumber',''), 'Unknown'),
  coalesce(nullif(payload->>'plateNumber',''), 'Unknown'),
  coalesce(nullif(payload->>'cubicYards','')::numeric, 0),
  coalesce(nullif(payload->>'materials',''), 'Unknown'),
  coalesce(nullif(payload->>'customerName',''), 'Unknown'),
  nullif(payload->>'emailAddress',''),
  nullif(payload->>'contactNumber',''),
  nullif(payload->>'jobsite',''),
  nullif(payload->>'buildingNumber',''),
  coalesce(nullif(payload->>'gross','')::numeric, 0),
  coalesce(nullif(payload->>'tare','')::numeric, 0),
  coalesce(nullif(payload->>'net','')::numeric, 0),
  coalesce(nullif(payload->>'tons','')::numeric, 0),
  nullif(payload->>'billingUnit',''),
  coalesce(nullif(payload->>'billingQuantity','')::numeric, 0),
  coalesce(nullif(payload->>'billingRate','')::numeric, 0),
  coalesce(nullif(payload->>'billingAmount','')::numeric, 0),
  nullif(payload->>'driverSignature',''),
  nullif(payload->>'customerSignature',''),
  coalesce(nullif(payload->>'createdAt','')::timestamptz, updated_at, now()),
  coalesce(nullif(payload->>'updatedAt','')::timestamptz, updated_at, now()),
  payload
from public.inventory_requests
where payload->>'recordType' = 'piti_greenwaste_ticket'
   or payload->>'requestType' = 'Piti Greenwaste Ticket'
on conflict (id) do nothing;
