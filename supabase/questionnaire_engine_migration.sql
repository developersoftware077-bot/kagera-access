-- Kagera questionnaire engine upgrade. Run after catalogue_migration.sql and
-- questionnaire_catalogue_migration.sql. This migration is additive: it does
-- not create replacement tables, remove research records, or alter RLS.

alter table public.questionnaire_sessions
  add column if not exists catalogue_selection jsonb not null default '[]'::jsonb;

-- Ranges are deliberately stored as the seller's selected label, never as a
-- calculated midpoint. Existing numeric columns remain intact for verified
-- numeric interviews, but are optional for public range-based responses.
alter table public.research_responses
  alter column buying_price drop not null,
  alter column selling_price drop not null,
  alter column monthly_quantity drop not null,
  add column if not exists demand_level text,
  add column if not exists restock_frequency text,
  add column if not exists availability_detail text,
  add column if not exists unavailability_reasons text[] not null default '{}',
  add column if not exists customer_shortage_action text,
  add column if not exists buying_price_range text,
  add column if not exists selling_price_range text,
  add column if not exists acceptable_wholesale_price_range text,
  add column if not exists hypothetical_test_price numeric,
  add column if not exists hypothetical_price_response text,
  add column if not exists initial_quantity_range text,
  add column if not exists supplier_interest text,
  add column if not exists preferred_delivery text,
  add column if not exists whatsapp_updates_consent boolean,
  add column if not exists other_product text,
  add column if not exists other_model_specification text;

-- Selected product and optional selected models are exposed, rather than the
-- entire master catalogue. A product with an empty modelIds intentionally has
-- all of its models available for a seller to choose.
drop function if exists public.get_public_active_catalogue(uuid);
create or replace function public.get_public_active_catalogue(p_token uuid)
returns table(product_id uuid, category text, product_name text, product_model_id uuid, brand text, phone_model text, test_price numeric)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from questionnaire_sessions where id = p_token and active) then
    raise exception 'Invalid questionnaire';
  end if;
  return query
  with picked as (
    select coalesce(s.catalogue_selection, '[]'::jsonb) selection, s.product_ids
    from questionnaire_sessions s where s.id = p_token
  ), selected as (
    select (x->>'productId')::uuid as id, coalesce(x->'modelIds', '[]'::jsonb) as model_ids, nullif(x->>'testPrice','')::numeric as test_price
    from picked, lateral jsonb_array_elements(selection) x where jsonb_array_length(selection) > 0
    union all
    select unnest(product_ids), '[]'::jsonb, null::numeric from picked where jsonb_array_length(selection) = 0
  )
  select p.id, p.category, p.name, pm.id, pm.brand, pm.model, s.test_price
  from selected s
  join products p on p.id = s.id and p.is_active
  left join product_models pm on pm.product_id = p.id and pm.is_active
    and (jsonb_array_length(s.model_ids) = 0 or pm.id::text in (select jsonb_array_elements_text(s.model_ids)))
  order by p.category, p.name, pm.brand nulls first, pm.model nulls first;
end; $$;

create or replace function public.submit_public_catalogue_response(
  p_token uuid, p_response_id uuid, p_seller_id uuid, p_product_id uuid, p_product_model_id uuid,
  p_demand_level text, p_restock_frequency text, p_availability_detail text, p_unavailability_reasons text[],
  p_customer_shortage_action text, p_buying_price_range text, p_selling_price_range text,
  p_acceptable_wholesale_price_range text, p_hypothetical_test_price numeric, p_hypothetical_price_response text,
  p_supplier_interest text, p_initial_quantity_range text, p_preferred_delivery text, p_whatsapp_updates_consent boolean,
  p_other_product text, p_other_model_specification text, p_notes text
) returns void language plpgsql security definer set search_path = public as $$
declare picked jsonb; allowed_models jsonb;
begin
  select catalogue_selection into picked from questionnaire_sessions where id=p_token and active;
  if picked is null then raise exception 'Invalid questionnaire'; end if;
  if not exists (select 1 from sellers where id=p_seller_id and questionnaire_token=p_token) then raise exception 'Invalid seller'; end if;
  if jsonb_array_length(picked) = 0 then
    if not exists (select 1 from questionnaire_sessions where id=p_token and p_product_id = any(product_ids)) then raise exception 'Product is not in this questionnaire'; end if;
    allowed_models := '[]'::jsonb;
  else
    select x->'modelIds' into allowed_models from jsonb_array_elements(picked) x where (x->>'productId')::uuid = p_product_id limit 1;
  end if;
  if allowed_models is null then raise exception 'Product is not in this questionnaire'; end if;
  if p_product_model_id is not null and not exists (
    select 1 from product_models pm where pm.id=p_product_model_id and pm.product_id=p_product_id and pm.is_active
      and (jsonb_array_length(allowed_models)=0 or pm.id::text in (select jsonb_array_elements_text(allowed_models)))
  ) then raise exception 'Invalid product model'; end if;
  insert into research_responses(
    id,seller_id,product_id,product_model_id,availability,interested_in_supplier,notes,questionnaire_token,
    demand_level,restock_frequency,availability_detail,unavailability_reasons,customer_shortage_action,
    buying_price_range,selling_price_range,acceptable_wholesale_price_range,hypothetical_test_price,hypothetical_price_response,
    supplier_interest,initial_quantity_range,preferred_delivery,whatsapp_updates_consent,other_product,other_model_specification
  ) values (
    p_response_id,p_seller_id,p_product_id,p_product_model_id,
    case when p_availability_detail in ('Kila mara','Mara nyingi') then 'available' when p_availability_detail='Wakati mwingine hukosekana' then 'sometimes' else 'often' end,
    p_supplier_interest in ('Ndiyo','Labda'),p_notes,p_token,
    p_demand_level,p_restock_frequency,p_availability_detail,coalesce(p_unavailability_reasons,'{}'),p_customer_shortage_action,
    p_buying_price_range,p_selling_price_range,p_acceptable_wholesale_price_range,p_hypothetical_test_price,p_hypothetical_price_response,
    p_supplier_interest,p_initial_quantity_range,p_preferred_delivery,p_whatsapp_updates_consent,nullif(trim(p_other_product),''),nullif(trim(p_other_model_specification),'')
  );
end; $$;

revoke all on function public.submit_public_catalogue_response(uuid,uuid,uuid,uuid,uuid,text,text,text,text[],text,text,text,text,numeric,text,text,text,text,boolean,text,text,text) from public;
grant execute on function public.submit_public_catalogue_response(uuid,uuid,uuid,uuid,uuid,text,text,text,text[],text,text,text,text,numeric,text,text,text,text,boolean,text,text,text) to anon, authenticated;

-- Complete initial master catalogue. New entries are reusable configuration;
-- no seller or research-response data is inserted.
-- Normalize the older catalogue label in place so existing responses keep the
-- same product id instead of receiving a duplicate Phone Cover product.
update public.products
set category='Phone Accessories', normalized_name=lower('Phone Accessories|Phone Cover')
where category='Protection' and name='Phone Cover'
  and not exists (select 1 from public.products x where x.category='Phone Accessories' and x.name='Phone Cover');
update public.product_models pm set normalized_key=lower(trim(p.category)||'|'||trim(p.name)||'|'||trim(pm.brand)||'|'||trim(pm.model))
from public.products p where p.id=pm.product_id and p.category='Phone Accessories' and p.name='Phone Cover';

with entries(category,name) as (values
('Phone Accessories','Phone Cover'),('Screen Protection','Tempered Glass / Screen Protector'),
('Charging','Standard Charger'),('Charging','Fast Charger 10W'),('Charging','Fast Charger 18W'),('Charging','Fast Charger 20W'),('Charging','Fast Charger 25W'),('Charging','Fast Charger 33W'),('Charging','Fast Charger 45W'),('Charging','Fast Charger 67W'),('Charging','Type-C Charger'),('Charging','iPhone Charger'),('Charging','Dual USB Charger'),('Charging','Other Wall Charger'),
('Cables','Micro USB Cable'),('Cables','Type-C Cable'),('Cables','Type-C to Type-C Cable'),('Cables','Lightning Cable'),('Cables','USB-A to Type-C'),('Cables','USB-A to Micro USB'),('Cables','USB-A to Lightning'),('Cables','Fast Charging Cable'),('Cables','Data Cable'),('Cables','1 Metre Cable'),('Cables','2 Metre Cable'),('Cables','Other Cable'),
('Earphones / Audio','Wired Earphones'),('Earphones / Audio','Type-C Earphones'),('Earphones / Audio','Lightning Earphones'),('Earphones / Audio','Bluetooth Earbuds'),('Earphones / Audio','Bluetooth Neckband'),('Earphones / Audio','Bluetooth Headset'),('Earphones / Audio','Wireless Earbuds'),('Earphones / Audio','Other Audio'),
('Power Banks','5,000mAh'),('Power Banks','10,000mAh'),('Power Banks','20,000mAh'),('Power Banks','30,000mAh'),('Power Banks','Fast-charge Power Bank'),('Power Banks','Other Power Bank'),
('Phone Holders','Desk / Stand Holder'),('Phone Holders','Car Holder'),('Phone Holders','Motorcycle Holder'),('Phone Holders','Flexible Holder'),('Phone Holders','Ring Holder'),('Phone Holders','Magnetic Holder'),('Phone Holders','Other Holder'),
('Car Chargers','Single-port Car Charger'),('Car Chargers','Dual-port Car Charger'),('Car Chargers','Type-C Car Charger'),('Car Chargers','Fast Car Charger'),('Car Chargers','Other Car Charger'),
('Bluetooth Speakers','Mini Bluetooth Speaker'),('Bluetooth Speakers','Portable Bluetooth Speaker'),('Bluetooth Speakers','Medium Bluetooth Speaker'),('Bluetooth Speakers','Large Bluetooth Speaker'),('Bluetooth Speakers','Waterproof Bluetooth Speaker'),('Bluetooth Speakers','Other Speaker'),
('Smart Watches','Basic Smart Watch'),('Smart Watches','Bluetooth Calling Smart Watch'),('Smart Watches','Fitness Smart Watch'),('Smart Watches','Kids Smart Watch'),('Smart Watches','Other Smart Watch'),
('Memory / Storage','MicroSD 32GB'),('Memory / Storage','MicroSD 64GB'),('Memory / Storage','MicroSD 128GB'),('Memory / Storage','MicroSD 256GB'),('Memory / Storage','Flash Disk 32GB'),('Memory / Storage','Flash Disk 64GB'),('Memory / Storage','Flash Disk 128GB'),('Memory / Storage','Other Storage'),
('Adapters / USB Accessories','OTG Type-C'),('Adapters / USB Accessories','OTG Micro USB'),('Adapters / USB Accessories','USB Adapter'),('Adapters / USB Accessories','Type-C Adapter'),('Adapters / USB Accessories','Type-C to Lightning Adapter'),('Adapters / USB Accessories','USB Hub'),('Adapters / USB Accessories','SIM Adapter'),('Adapters / USB Accessories','Other Adapter'),
('Other Fast-moving Accessories','Selfie Stick'),('Other Fast-moving Accessories','Phone Tripod'),('Other Fast-moving Accessories','Phone Cleaning Kit'),('Other Fast-moving Accessories','Camera Lens Protector'),('Other Fast-moving Accessories','Cable Protector'),('Other Fast-moving Accessories','SIM Ejector'),('Other Fast-moving Accessories','Phone Pouch'),('Other Fast-moving Accessories','Other Product')
)
insert into products(name,category,phone_model,notes,normalized_name,is_active)
select name,category,null,'Initial Kagera research catalogue',lower(trim(category)||'|'||trim(name)),true from entries
on conflict(normalized_name) do update set is_active=true;

with model_data(category,product_name,brand,models) as (values
('Phone Accessories','Phone Cover','Samsung','A06|A05|A05s|A15|A16|A24|A25|A26|A34|A35|A54|A55|S21|S22|S23|S24|S25'),
('Phone Accessories','Phone Cover','Tecno','Spark 10|Spark 20|Spark 20 Pro|Spark 30|Spark 30C|Camon 20|Camon 30|Camon 40|Pop 8|Pop 9'),('Phone Accessories','Phone Cover','Infinix','Hot 30|Hot 40|Hot 50|Hot 50i|Note 30|Note 40|Smart 8|Smart 9'),('Phone Accessories','Phone Cover','Redmi','12|13|14C|Note 12|Note 13|Note 14'),('Phone Accessories','Phone Cover','Apple','iPhone 11|iPhone 12|iPhone 13|iPhone 14|iPhone 15|iPhone 16'),('Phone Accessories','Phone Cover','Other','Other model'),
('Screen Protection','Tempered Glass / Screen Protector','Samsung','A06|A05|A05s|A15|A16|A24|A25|A26|A34|A35|A54|A55'),('Screen Protection','Tempered Glass / Screen Protector','Tecno','Spark series|Camon series|Pop series'),('Screen Protection','Tempered Glass / Screen Protector','Infinix','Hot series|Note series|Smart series'),('Screen Protection','Tempered Glass / Screen Protector','Redmi','Redmi series'),('Screen Protection','Tempered Glass / Screen Protector','Apple','iPhone series'),('Screen Protection','Tempered Glass / Screen Protector','Other','Other model')
), exploded as (select category,product_name,brand,trim(model) model from model_data cross join lateral regexp_split_to_table(models,E'\\|') model)
insert into product_models(product_id,brand,model,is_active,normalized_key)
select p.id,e.brand,e.model,true,lower(trim(p.category)||'|'||trim(p.name)||'|'||trim(e.brand)||'|'||trim(e.model)) from exploded e join products p on p.category=e.category and p.name=e.product_name
on conflict(normalized_key) do update set is_active=true;
