-- Safe additive upgrade for Piti Greenwaste tickets.
-- This does not delete, replace, or modify any existing ticket data.
alter table public.greenwaste_tickets
  add column if not exists email_address text;

alter table public.greenwaste_tickets
  add column if not exists contact_number text;

alter table public.greenwaste_tickets
  add column if not exists billing_unit text;

alter table public.greenwaste_tickets
  add column if not exists billing_quantity numeric(14,3) not null default 0;

alter table public.greenwaste_tickets
  add column if not exists billing_rate numeric(14,2) not null default 0;

alter table public.greenwaste_tickets
  add column if not exists billing_amount numeric(14,2) not null default 0;

comment on column public.greenwaste_tickets.email_address is
  'Customer email address copied from the ticket payload.';

comment on column public.greenwaste_tickets.contact_number is
  'Customer contact number copied from the ticket payload.';

comment on column public.greenwaste_tickets.billing_unit is
  'Billing unit such as CY, TON, LB, LOAD, EACH, or FLAT.';
