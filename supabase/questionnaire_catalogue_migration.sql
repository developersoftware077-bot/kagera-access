-- Add model-aware, optional catalogue answers to the existing research flow.
alter table public.research_responses
  add column if not exists product_model_id uuid references public.product_models(id) on delete restrict;

create index if not exists research_responses_product_model_id_idx
  on public.research_responses(product_model_id);

create or replace function public.get_public_active_catalogue(p_token uuid)
returns table(product_id uuid, category text, product_name text, product_model_id uuid, brand text, phone_model text)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from questionnaire_sessions where id = p_token and active) then
    raise exception 'Invalid questionnaire';
  end if;
  return query
  select p.id, p.category, p.name, pm.id, pm.brand, pm.model
  from products p left join product_models pm on pm.product_id = p.id and pm.is_active
  where p.is_active
  order by p.category, p.name, pm.brand nulls first, pm.model nulls first;
end; $$;
revoke all on function public.get_public_active_catalogue(uuid) from public;
grant execute on function public.get_public_active_catalogue(uuid) to anon, authenticated;

create or replace function public.submit_public_catalogue_response(
  p_token uuid, p_response_id uuid, p_seller_id uuid, p_product_id uuid, p_product_model_id uuid,
  p_buying_price numeric, p_selling_price numeric, p_monthly_quantity integer, p_availability text,
  p_interested boolean, p_initial_quantity integer, p_notes text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from questionnaire_sessions where id = p_token and active) then raise exception 'Invalid questionnaire'; end if;
  if not exists (select 1 from sellers where id = p_seller_id and questionnaire_token = p_token) then raise exception 'Invalid seller'; end if;
  if not exists (select 1 from products where id = p_product_id and is_active) then raise exception 'Invalid product'; end if;
  if p_product_model_id is not null and not exists (select 1 from product_models where id = p_product_model_id and product_id = p_product_id and is_active) then raise exception 'Invalid product model'; end if;
  insert into research_responses(id, seller_id, product_id, product_model_id, buying_price, selling_price, monthly_quantity, availability, interested_in_supplier, initial_quantity, notes, questionnaire_token)
  values(p_response_id, p_seller_id, p_product_id, p_product_model_id, p_buying_price, p_selling_price, p_monthly_quantity, p_availability, p_interested, p_initial_quantity, p_notes, p_token);
end; $$;
revoke all on function public.submit_public_catalogue_response(uuid,uuid,uuid,uuid,uuid,numeric,numeric,integer,text,boolean,integer,text) from public;
grant execute on function public.submit_public_catalogue_response(uuid,uuid,uuid,uuid,uuid,numeric,numeric,integer,text,boolean,integer,text) to anon, authenticated;
