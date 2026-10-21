-- Add a read-only inventory permission without granting inventory mutations.
alter table public.user_access
  drop constraint if exists user_access_values_check;

alter table public.user_access
  add constraint user_access_values_check check (
    access <@ array[
      'dashboard','inventory','inventory_view','issued','borrowed','requests',
      'greenwaste','alerts','settings','manage_users'
    ]::text[]
  );

create policy "Inventory view-only users read inventory" on public.inventory_items
for select to authenticated using (
  coalesce(auth.jwt()->'app_metadata'->'access','[]'::jsonb) ? 'inventory_view'
);
