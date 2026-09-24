-- Kagera Accessories master catalogue. This migration is additive and idempotent.
-- It never drops tables, columns, policies, or existing data.

alter table public.products
  add column if not exists is_active boolean not null default true;

create table if not exists public.product_models (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  brand text not null,
  model text not null,
  is_active boolean not null default true,
  normalized_key text not null unique,
  created_at timestamptz not null default now(),
  constraint product_models_brand_not_blank check (length(trim(brand)) > 0),
  constraint product_models_model_not_blank check (length(trim(model)) > 0)
);

alter table public.product_models enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'product_models'
      and policyname = 'researchers manage product models'
  ) then
    create policy "researchers manage product models" on public.product_models
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- A stable selector surface for the future questionnaire:
-- category -> product -> brand -> phone model. Generic/N/A products return no model rows.
create or replace function public.get_active_catalogue()
returns table (
  product_id uuid, category text, product_name text, product_active boolean,
  product_model_id uuid, brand text, phone_model text, model_active boolean
) language sql stable security invoker set search_path = public as $$
  select p.id, p.category, p.name, p.is_active,
         pm.id, pm.brand, pm.model, pm.is_active
  from products p
  left join product_models pm on pm.product_id = p.id and pm.is_active
  where p.is_active
  order by p.category, p.name, pm.brand nulls first, pm.model nulls first;
$$;
grant execute on function public.get_active_catalogue() to authenticated;

-- Existing projects created before this migration used name-only normalized_name.
-- Repair only its key, never its identity or any research data.
update public.products
set normalized_name = lower(trim(category) || '|' || trim(name)), is_active = true
where normalized_name = lower(trim(name));

with master_products(category, name) as (
  values
  ('Protection','Phone Cover'), ('Screen Protection','Tempered Glass'),
  ('Charging','Standard Wall Charger'), ('Charging','Fast Charger 18W'), ('Charging','Fast Charger 20W'), ('Charging','Fast Charger 25W'), ('Charging','Fast Charger 33W'), ('Charging','Fast Charger 45W'), ('Charging','USB-C Wall Charger'), ('Charging','Dual USB Charger'), ('Charging','Multi-Port Charger'), ('Charging','Car Charger'),
  ('Cables','USB-C Cable'), ('Cables','Micro-USB Cable'), ('Cables','Lightning Cable'), ('Cables','USB-C to USB-C Cable'), ('Cables','USB-A to USB-C Cable'), ('Cables','USB-A to Micro-USB Cable'), ('Cables','USB-A to Lightning Cable'), ('Cables','3-in-1 Charging Cable'), ('Cables','Braided USB-C Cable'), ('Cables','Fast-Charging USB-C Cable'),
  ('Power','Power Bank 5,000mAh'), ('Power','Power Bank 10,000mAh'), ('Power','Power Bank 20,000mAh'), ('Power','Fast-Charging Power Bank'), ('Power','Mini Power Bank'), ('Power','Power Bank with Built-in Cable'), ('Power','Power Bank with Digital Display'), ('Power','Extension Socket'),
  ('Audio','Wired Earphones'), ('Audio','USB-C Earphones'), ('Audio','Lightning Earphones'), ('Audio','Bluetooth Earbuds'), ('Audio','TWS Earbuds'), ('Audio','Bluetooth Headphones'), ('Audio','Neckband Earphones'), ('Audio','Small Bluetooth Speaker'), ('Audio','Medium Bluetooth Speaker'), ('Audio','AUX Cable'),
  ('Connectivity','USB-C OTG Adapter'), ('Connectivity','Micro-USB OTG Adapter'), ('Connectivity','Lightning Adapter'), ('Connectivity','USB-C Card Reader'), ('Connectivity','Memory Card 32GB'), ('Connectivity','Memory Card 64GB'), ('Connectivity','Memory Card 128GB'), ('Connectivity','USB Flash Drive 32GB'), ('Connectivity','USB Flash Drive 64GB'),
  ('Phone Accessories','Phone Holder'), ('Phone Accessories','Car Phone Holder'), ('Phone Accessories','Phone Stand'), ('Phone Accessories','Ring Holder'), ('Phone Accessories','Pop Socket'), ('Phone Accessories','Selfie Stick'), ('Phone Accessories','Mini Tripod'), ('Phone Accessories','Phone Cleaning Kit'),
  ('Smart Devices','Smart Watch'), ('Smart Devices','Smart Watch Strap'),
  ('Gaming','Mobile Gaming Trigger'), ('Gaming','Phone Cooling Fan'), ('Gaming','Gaming Finger Sleeves')
)
insert into public.products(name, category, phone_model, notes, normalized_name, is_active)
select name, category, null, 'Initial Kagera research catalogue', lower(trim(category) || '|' || trim(name)), true
from master_products
on conflict (normalized_name) do update set is_active = true;

with source(category, product_name, brand, models) as (
  values
  ('Protection','Phone Cover','Samsung','Galaxy A05|Galaxy A06|Galaxy A15|Galaxy A16|Galaxy A17|Galaxy A24|Galaxy A25|Galaxy A26|Galaxy A35|Galaxy A55'),
  ('Protection','Phone Cover','Tecno','Spark 20|Spark 30|Camon 20|Camon 30'), ('Protection','Phone Cover','Infinix','Hot 40|Hot 50|Note 40|Note 50'), ('Protection','Phone Cover','Redmi','Note 13|Note 14'), ('Protection','Phone Cover','Apple','iPhone 11|iPhone 12|iPhone 13|iPhone 14|iPhone 15'), ('Protection','Phone Cover','Google','Pixel 6a|Pixel 7'),
  ('Screen Protection','Tempered Glass','Samsung','Galaxy A05|Galaxy A06|Galaxy A15|Galaxy A16|Galaxy A17|Galaxy A25|Galaxy A26|Galaxy A35'), ('Screen Protection','Tempered Glass','Tecno','Spark 20|Spark 30|Camon 30'), ('Screen Protection','Tempered Glass','Infinix','Hot 40|Hot 50|Note 40'), ('Screen Protection','Tempered Glass','Redmi','Note 13|Note 14'), ('Screen Protection','Tempered Glass','Apple','iPhone 11|iPhone 12|iPhone 13|iPhone 15|iPhone 16')
), expanded as (
  select category, product_name, brand, trim(model) as model
  from source cross join lateral regexp_split_to_table(models, E'\\|') as model
)
insert into public.product_models(product_id, brand, model, is_active, normalized_key)
select p.id, e.brand, e.model, true, lower(trim(p.category) || '|' || trim(p.name) || '|' || trim(e.brand) || '|' || trim(e.model))
from expanded e join public.products p on p.category = e.category and p.name = e.product_name
on conflict (normalized_key) do update set is_active = true;

-- Verification (expected: 62 products, 48 models, 10 categories, zero duplicate keys).
select
  (select count(*) from public.products where is_active) as active_products,
  (select count(*) from public.product_models where is_active) as active_product_models,
  (select count(distinct category) from public.products where is_active) as active_categories,
  (select count(*) from (select normalized_key from public.product_models group by normalized_key having count(*) > 1) d) as duplicate_model_keys;
