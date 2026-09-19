-- Run this whole file in Supabase Dashboard > SQL Editor.
create extension if not exists "pgcrypto";

create table if not exists public.sellers (
  id uuid primary key default gen_random_uuid(), shop_name text not null, seller_name text not null,
  phone text not null, location text not null, business_type text not null, questionnaire_token uuid, created_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(), name text not null, category text not null,
  phone_model text, notes text, normalized_name text not null unique, created_at timestamptz not null default now()
);
create table if not exists public.questionnaire_sessions (
  id uuid primary key default gen_random_uuid(), active boolean not null default true,
  product_ids uuid[] not null default '{}', product_snapshots jsonb not null default '[]', created_at timestamptz not null default now()
);
create table if not exists public.research_responses (
  id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.sellers(id) on delete cascade,
  product_id uuid not null references public.products(id), buying_price numeric not null check(buying_price >= 0), selling_price numeric not null check(selling_price >= 0),
  monthly_quantity integer not null check(monthly_quantity > 0), availability text not null check(availability in ('available','sometimes','often')),
  interested_in_supplier boolean not null default false, initial_quantity integer check(initial_quantity is null or initial_quantity > 0), notes text, questionnaire_token uuid, created_at timestamptz not null default now()
);

alter table public.sellers enable row level security;
alter table public.products enable row level security;
alter table public.questionnaire_sessions enable row level security;
alter table public.research_responses enable row level security;
create policy "researchers manage sellers" on public.sellers for all to authenticated using (true) with check (true);
create policy "researchers manage products" on public.products for all to authenticated using (true) with check (true);
create policy "researchers manage sessions" on public.questionnaire_sessions for all to authenticated using (true) with check (true);
create policy "researchers manage responses" on public.research_responses for all to authenticated using (true) with check (true);

-- Only exposes the specific questionnaire addressed by the bearer token, not admin tables.
create or replace function public.get_public_questionnaire(p_token uuid)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('id', id, 'active', active, 'productIds', product_ids, 'productSnapshots', product_snapshots)
  from public.questionnaire_sessions where id = p_token and active = true;
$$;
create or replace function public.submit_public_seller(p_token uuid,p_seller_id uuid,p_shop_name text,p_seller_name text,p_phone text,p_location text,p_business_type text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from questionnaire_sessions where id=p_token and active) then raise exception 'Invalid questionnaire'; end if;
  insert into sellers(id,shop_name,seller_name,phone,location,business_type,questionnaire_token) values(p_seller_id,p_shop_name,p_seller_name,p_phone,p_location,p_business_type,p_token);
end; $$;
create or replace function public.submit_public_response(p_token uuid,p_response_id uuid,p_seller_id uuid,p_product_id uuid,p_buying_price numeric,p_selling_price numeric,p_monthly_quantity integer,p_availability text,p_interested boolean,p_initial_quantity integer,p_notes text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from questionnaire_sessions where id=p_token and active and p_product_id = any(product_ids)) then raise exception 'Invalid questionnaire or product'; end if;
  if not exists(select 1 from sellers where id=p_seller_id and questionnaire_token=p_token) then raise exception 'Invalid seller'; end if;
  insert into research_responses(id,seller_id,product_id,buying_price,selling_price,monthly_quantity,availability,interested_in_supplier,initial_quantity,notes,questionnaire_token) values(p_response_id,p_seller_id,p_product_id,p_buying_price,p_selling_price,p_monthly_quantity,p_availability,p_interested,p_initial_quantity,p_notes,p_token);
end; $$;
revoke all on function public.get_public_questionnaire(uuid) from public;
revoke all on function public.submit_public_seller(uuid,uuid,text,text,text,text,text) from public;
revoke all on function public.submit_public_response(uuid,uuid,uuid,uuid,numeric,numeric,integer,text,boolean,integer,text) from public;
grant execute on function public.get_public_questionnaire(uuid) to anon, authenticated;
grant execute on function public.submit_public_seller(uuid,uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.submit_public_response(uuid,uuid,uuid,uuid,numeric,numeric,integer,text,boolean,integer,text) to anon, authenticated;

-- Create the requested researcher in Authentication > Users manually, or use the Dashboard invite flow.
-- Never paste sb_secret_... into .env, browser code, or this SQL file.
