-- Mall Lot Inventory safety and reporting upgrade (additive / no data deletion)
-- Run once in Supabase SQL Editor. Existing inventory rows are preserved.

begin;

-- 1. Remove anonymous access to the inventory register. Public mobile requests may
-- still be submitted, but anonymous visitors cannot list/change/delete inventory.
drop policy if exists "Allow anon read inventory" on public.inventory_items;
drop policy if exists "Allow anon upsert inventory" on public.inventory_items;
drop policy if exists "Allow anon update inventory" on public.inventory_items;
drop policy if exists "Allow anon delete inventory" on public.inventory_items;
revoke all on table public.inventory_items from anon;

drop policy if exists "Allow anon read requests" on public.inventory_requests;
drop policy if exists "Allow anon update requests" on public.inventory_requests;
drop policy if exists "Allow anon delete requests" on public.inventory_requests;
revoke select, update, delete on table public.inventory_requests from anon;
grant insert on table public.inventory_requests to anon;

-- Public mobile request form receives only the minimum catalog fields needed to
-- request an in-stock item. Costs, suppliers, movement history and private notes
-- are never returned to an anonymous visitor.
create or replace function public.get_requestable_inventory()
returns table (payload jsonb, updated_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', i.id,
    'name', i.name,
    'sku', i.sku,
    'quantity', i.quantity,
    'unit', i.payload->>'unit',
    'category', i.payload->>'category',
    'barcode', i.payload->>'barcode',
    'location', i.payload->>'location',
    'bin', i.payload->>'bin',
    'photoData', i.payload->>'photoData',
    'updatedAt', i.updated_at
  ), i.updated_at
  from public.inventory_items i
  where coalesce(i.quantity, 0) > 0
  order by i.name, i.sku;
$$;

revoke all on function public.get_requestable_inventory() from public;
grant execute on function public.get_requestable_inventory() to anon, authenticated;

-- 2. Permanent, append-only stock transaction ledger.
create table if not exists public.inventory_stock_movements (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references public.inventory_items(id) on delete set null,
  item_name text,
  sku text,
  movement_type text not null default 'adjustment',
  quantity_before numeric not null default 0,
  quantity_change numeric not null,
  quantity_after numeric not null,
  unit text,
  location text,
  reason text not null default 'Inventory updated',
  reference_number text,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now(),
  constraint inventory_stock_movements_balance_check
    check (quantity_after = quantity_before + quantity_change)
);

create index if not exists inventory_stock_movements_item_created_idx
  on public.inventory_stock_movements (item_id, created_at desc);
create index if not exists inventory_stock_movements_created_idx
  on public.inventory_stock_movements (created_at desc);
create index if not exists inventory_stock_movements_sku_idx
  on public.inventory_stock_movements (lower(sku));

alter table public.inventory_stock_movements enable row level security;
revoke all on table public.inventory_stock_movements from anon;
grant select on table public.inventory_stock_movements to authenticated;

drop policy if exists "Assigned users read stock movements" on public.inventory_stock_movements;
create policy "Assigned users read stock movements"
on public.inventory_stock_movements for select to authenticated using (
  lower(coalesce(auth.jwt()->>'email','')) = 'bryan.dy@lmsfm.com'
  or coalesce(auth.jwt()->'app_metadata'->'access','[]'::jsonb) ?| array['inventory','issued','borrowed','requests','manage_users']
);

-- Ledger rows cannot be edited or deleted by the browser. They are written only
-- by the trigger/function below, giving an immutable audit history.
create or replace function public.audit_inventory_quantity_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before numeric := coalesce(old.quantity, 0);
  v_after numeric := coalesce(new.quantity, 0);
  v_reason text := nullif(current_setting('app.inventory_reason', true), '');
  v_location text := nullif(current_setting('app.inventory_location', true), '');
  v_reference text := nullif(current_setting('app.inventory_reference', true), '');
begin
  if tg_op = 'INSERT' then v_before := 0; end if;
  if tg_op = 'UPDATE' and v_before = v_after then return new; end if;

  insert into public.inventory_stock_movements (
    item_id, item_name, sku, movement_type, quantity_before, quantity_change,
    quantity_after, unit, location, reason, reference_number, actor_id, actor_email
  ) values (
    new.id,
    new.name,
    new.sku,
    case when tg_op = 'INSERT' then 'opening_balance'
         when v_after > v_before then 'receipt_or_return'
         else 'issue_or_adjustment' end,
    v_before,
    v_after - v_before,
    v_after,
    new.payload->>'unit',
    coalesce(v_location, new.payload->>'location'),
    coalesce(v_reason, case when tg_op = 'INSERT' then 'Opening balance imported from existing inventory' else 'Inventory quantity updated' end),
    v_reference,
    auth.uid(),
    auth.jwt()->>'email'
  );
  return new;
end;
$$;

drop trigger if exists inventory_quantity_audit_trigger on public.inventory_items;
create trigger inventory_quantity_audit_trigger
after insert or update of quantity on public.inventory_items
for each row execute function public.audit_inventory_quantity_change();
revoke all on function public.audit_inventory_quantity_change() from public;

-- 3. Atomic stock change: locks one item, applies the delta, rejects negative
-- stock, updates the JSON payload, and creates the ledger entry in one transaction.
create or replace function public.apply_inventory_stock_change(
  p_item_id uuid,
  p_quantity_change numeric,
  p_reason text,
  p_location text default null,
  p_reference_number text default null
)
returns public.inventory_items
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_after numeric;
begin
  if p_quantity_change is null or p_quantity_change = 0 then
    raise exception 'Quantity change must not be zero.';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'A reason is required for every stock change.';
  end if;

  select * into v_item from public.inventory_items where id = p_item_id for update;
  if not found then raise exception 'Inventory item not found.'; end if;

  v_after := coalesce(v_item.quantity, 0) + p_quantity_change;
  if v_after < 0 then
    raise exception 'Insufficient stock. Available: %, requested change: %', v_item.quantity, p_quantity_change;
  end if;

  perform set_config('app.inventory_reason', trim(p_reason), true);
  perform set_config('app.inventory_location', coalesce(p_location, ''), true);
  perform set_config('app.inventory_reference', coalesce(p_reference_number, ''), true);

  update public.inventory_items
  set quantity = v_after,
      payload = jsonb_set(
        jsonb_set(coalesce(payload, '{}'::jsonb), '{quantity}', to_jsonb(v_after), true),
        '{updatedAt}', to_jsonb(now()::text), true
      ),
      updated_at = now()
  where id = p_item_id
  returning * into v_item;

  return v_item;
end;
$$;

revoke all on function public.apply_inventory_stock_change(uuid,numeric,text,text,text) from public;
grant execute on function public.apply_inventory_stock_change(uuid,numeric,text,text,text) to authenticated;

-- 4. Duplicate protection. Existing duplicate records remain untouched. New items
-- and SKU changes are blocked when the normalized SKU already belongs to another item.
create or replace function public.prevent_duplicate_inventory_sku()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.sku is not distinct from old.sku then
    return new;
  end if;
  if nullif(regexp_replace(lower(trim(coalesce(new.sku, ''))), '[^a-z0-9]+', '', 'g'), '') is null then
    return new;
  end if;
  if exists (
    select 1 from public.inventory_items i
    where i.id <> new.id
      and regexp_replace(lower(trim(coalesce(i.sku, ''))), '[^a-z0-9]+', '', 'g') =
          regexp_replace(lower(trim(new.sku)), '[^a-z0-9]+', '', 'g')
  ) then
    raise exception 'Duplicate SKU blocked: %. Open the existing inventory item instead.', new.sku;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_duplicate_inventory_sku_trigger on public.inventory_items;
create trigger prevent_duplicate_inventory_sku_trigger
before insert or update of sku on public.inventory_items
for each row execute function public.prevent_duplicate_inventory_sku();
revoke all on function public.prevent_duplicate_inventory_sku() from public;

-- 5-6. Read-only reconciliation and data-quality views for reporting.
create or replace view public.inventory_reconciliation as
select
  i.id,
  i.sku,
  i.name,
  i.payload->>'category' as category,
  i.payload->>'unit' as unit,
  i.quantity as quantity_on_hand,
  coalesce(sum(m.quantity_change) filter (where m.quantity_change > 0), 0) as total_received,
  coalesce(abs(sum(m.quantity_change) filter (where m.quantity_change < 0)), 0) as total_issued,
  coalesce(sum(m.quantity_change), 0) as ledger_net_change,
  coalesce(nullif(i.payload->>'unitCost', '')::numeric, 0) as unit_cost,
  i.quantity * coalesce(nullif(i.payload->>'unitCost', '')::numeric, 0) as inventory_value,
  max(m.created_at) as last_movement_at
from public.inventory_items i
left join public.inventory_stock_movements m on m.item_id = i.id
group by i.id, i.sku, i.name, i.payload, i.quantity;

create or replace view public.inventory_data_quality as
select
  i.id,
  i.sku,
  i.name,
  array_remove(array[
    case when nullif(trim(i.sku), '') is null then 'Missing SKU' end,
    case when nullif(trim(i.name), '') is null then 'Missing description' end,
    case when nullif(trim(i.payload->>'category'), '') is null then 'Missing category' end,
    case when nullif(trim(i.payload->>'photoData'), '') is null then 'Missing photo' end,
    case when nullif(trim(i.payload->>'location'), '') is null then 'Missing location' end,
    case when nullif(trim(i.payload->>'bin'), '') is null then 'Missing bin' end,
    case when nullif(trim(i.payload->>'supplier'), '') is null then 'Missing supplier' end,
    case when coalesce(i.payload->'costUnavailable', 'false'::jsonb) <> 'true'::jsonb
      and coalesce(nullif(i.payload->>'unitCost', '')::numeric, 0) <= 0 then 'Missing unit cost' end,
    case when coalesce(nullif(i.payload->>'reorderPoint', '')::numeric, 0) <= 0 then 'Missing reorder level' end
  ], null) as issues,
  i.updated_at
from public.inventory_items i;

grant select on public.inventory_reconciliation, public.inventory_data_quality to authenticated;
revoke all on public.inventory_reconciliation, public.inventory_data_quality from anon;

commit;
