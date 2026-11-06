-- Movee atualização 19: comissão de 30% da empresa / 70% do entregador.
-- Instalação final nova: execute01..20. Versão anterior até18: aplique19 e20; até19: somente20.
-- Não aplica a comissão atual retroativamente a entregas/pagamentos antigos.
begin;

alter table public.deliveries add column if not exists commission_percent numeric(5,2);
alter table public.deliveries add column if not exists commission_amount numeric(14,2);
alter table public.payments add column if not exists confirmed_at timestamptz;
alter table public.payments add column if not exists confirmation_time_estimated boolean not null default false;
alter table public.payments add column if not exists commission_percent numeric(5,2);
alter table public.payments add column if not exists commission_amount numeric(14,2);

-- Acrescenta o padrão pedido pelo proprietário, preservando configuração já alterada.
update public.system_settings set value=value||'{"commission_percent":30}'::jsonb,updated_at=now()
 where key='pricing' and not(value ? 'commission_percent');

-- Apenas a data anterior disponível é recuperável; a comissão antiga continua desconhecida.
update public.payments set confirmed_at=coalesce(updated_at,created_at),confirmation_time_estimated=true
 where status in ('confirmed','refunded') and confirmed_at is null;

do $$begin
 if not exists(select 1 from pg_constraint where conname='deliveries_commission_snapshot_check' and conrelid='public.deliveries'::regclass) then
  alter table public.deliveries add constraint deliveries_commission_snapshot_check check(
   (commission_percent is null and commission_amount is null) or
   (commission_percent is not null and commission_amount is not null and commission_percent between 0 and 100
    and commission_percent::text not in ('NaN','Infinity','-Infinity') and commission_amount>=0
    and commission_amount::text not in ('NaN','Infinity','-Infinity') and commission_amount=round(price*commission_percent/100,2))
  );
 end if;
 if not exists(select 1 from pg_constraint where conname='payments_commission_snapshot_check' and conrelid='public.payments'::regclass) then
  alter table public.payments add constraint payments_commission_snapshot_check check(
   (commission_percent is null and commission_amount is null) or
   (commission_percent is not null and commission_amount is not null and commission_percent between 0 and 100
    and commission_percent::text not in ('NaN','Infinity','-Infinity') and commission_amount>=0
    and commission_amount::text not in ('NaN','Infinity','-Infinity') and commission_amount=round(amount*commission_percent/100,2))
  );
 end if;
end$$;

create or replace function private.capture_delivery_commission() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare rate numeric;
begin
 if tg_op='UPDATE' then
  if new.commission_percent is distinct from old.commission_percent or new.commission_amount is distinct from old.commission_amount or new.price is distinct from old.price then
   raise exception 'O valor e a comissão da entrega criada não podem ser alterados.';
  end if;
  return new;
 end if;
 select (value->>'commission_percent')::numeric into rate from public.system_settings where key='pricing';
 rate:=coalesce(rate,30);
 if rate<0 or rate>100 or rate::text in ('NaN','Infinity','-Infinity') then raise exception 'Percentual de comissão inválido.'; end if;
 new.commission_percent:=rate;
 new.commission_amount:=round(new.price*rate/100,2);
 return new;
end $$;
drop trigger if exists delivery_commission_snapshot on public.deliveries;
create trigger delivery_commission_snapshot before insert or update on public.deliveries
 for each row execute function private.capture_delivery_commission();

create or replace function private.capture_payment_confirmation() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare snapshot public.deliveries;
begin
 if tg_op='UPDATE' and old.confirmed_at is not null then
  if new.confirmed_at is distinct from old.confirmed_at or new.commission_percent is distinct from old.commission_percent
   or new.commission_amount is distinct from old.commission_amount or new.confirmation_time_estimated is distinct from old.confirmation_time_estimated
   or new.amount is distinct from old.amount then
   raise exception 'A data, o valor e a comissão de um pagamento confirmado são imutáveis.';
  end if;
  return new;
 end if;
 if new.status='confirmed' then
  select * into snapshot from public.deliveries where id=new.delivery_id;
  if snapshot.id is null or snapshot.price is distinct from new.amount then raise exception 'Pagamento incompatível com o valor da entrega.'; end if;
  new.confirmed_at:=now();
  new.confirmation_time_estimated:=false;
  new.commission_percent:=snapshot.commission_percent;
  new.commission_amount:=snapshot.commission_amount;
 else
  new.confirmed_at:=null;
  new.confirmation_time_estimated:=false;
  new.commission_percent:=null;
  new.commission_amount:=null;
 end if;
 return new;
end $$;
drop trigger if exists payment_financial_snapshot on public.payments;
create trigger payment_financial_snapshot before insert or update on public.payments
 for each row execute function private.capture_payment_confirmation();

create index if not exists payments_real_confirmed_month_idx on public.payments(confirmed_at)
 where status='confirmed' and not is_demo;

create or replace function public.admin_monthly_revenue(p_year integer) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb; period_start timestamptz; period_end timestamptz;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if p_year is null or p_year not between 2000 and 2100 then raise exception 'Informe um ano inteiro entre 2000 e 2100.'; end if;
 period_start:=make_date(p_year,1,1)::timestamp at time zone 'America/Sao_Paulo';
 period_end:=make_date(p_year+1,1,1)::timestamp at time zone 'America/Sao_Paulo';
 with eligible as (
  select p.*,extract(month from p.confirmed_at at time zone 'America/Sao_Paulo')::integer as revenue_month
  from public.payments p where p.status='confirmed' and not p.is_demo and p.confirmed_at>=period_start and p.confirmed_at<period_end
 ), monthly as (
  select revenue_month,sum(amount) as gross_amount,
   coalesce(sum(commission_amount),0) as commission_amount,
   coalesce(sum(amount-commission_amount) filter(where commission_amount is not null),0) as driver_amount,
   count(*) as payment_count,count(*) filter(where commission_amount is not null) as commission_payment_count,
   count(*) filter(where commission_amount is null) as unconfigured_payment_count
  from eligible group by revenue_month
 ), months as (
  select m,make_date(p_year,m,1) as month_start,coalesce(t.gross_amount,0) as gross_amount,
   coalesce(t.commission_amount,0) as commission_amount,coalesce(t.driver_amount,0) as driver_amount,
   coalesce(t.payment_count,0) as payment_count,coalesce(t.commission_payment_count,0) as commission_payment_count,
   coalesce(t.unconfigured_payment_count,0) as unconfigured_payment_count
  from generate_series(1,12) m left join monthly t on t.revenue_month=m
 )
 select jsonb_build_object(
  'year',p_year,'currency','BRL','timezone','America/Sao_Paulo','basis','confirmed_company_commission',
  'commission_percent',coalesce((select (value->>'commission_percent')::numeric from public.system_settings where key='pricing'),30),
  'months',(select jsonb_agg(jsonb_build_object('month',m,'month_start',month_start,'gross_amount',gross_amount,'commission_amount',commission_amount,
    'driver_amount',driver_amount,'payment_count',payment_count,'commission_payment_count',commission_payment_count,'unconfigured_payment_count',unconfigured_payment_count) order by m) from months),
  'total_gross_amount',(select coalesce(sum(gross_amount),0) from months),
  'total_commission_amount',(select coalesce(sum(commission_amount),0) from months),
  'total_driver_amount',(select coalesce(sum(driver_amount),0) from months),
  'total_payment_count',(select coalesce(sum(payment_count),0) from months),
  'total_commission_payment_count',(select coalesce(sum(commission_payment_count),0) from months),
  'unconfigured_payment_count',(select coalesce(sum(unconfigured_payment_count),0) from months),
  'legacy_confirmation_count',(select count(*) from eligible where confirmation_time_estimated),
  'demo_excluded_count',(select count(*) from public.payments p where p.status='confirmed' and p.is_demo and p.confirmed_at>=period_start and p.confirmed_at<period_end),
  'refunded_excluded_count',(select count(*) from public.payments p where p.status='refunded' and not p.is_demo and p.confirmed_at>=period_start and p.confirmed_at<period_end)
 ) into result;
 return result;
end $$;
revoke all on function public.admin_monthly_revenue(integer) from public,anon;
grant execute on function public.admin_monthly_revenue(integer) to authenticated,service_role;

comment on column public.deliveries.commission_percent is 'Percentual preservado na criação. Padrão inicial 30% Movee; alteração administrativa afeta somente novas entregas.';
comment on column public.payments.confirmed_at is 'Instante imutável da confirmação. Registros antigos podem usar uma data anterior estimada, indicada pela coluna específica.';
comment on column public.payments.commission_amount is 'Receita de comissão da Movee, separada do total do frete e de repasses. Nulo significa histórico sem comissão conhecida.';

-- Configuração auditada; a nova taxa vale somente para futuras entregas.
create or replace function public.update_pricing_settings(p_values jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare merged jsonb; previous jsonb; k text; n numeric; w jsonb; wd jsonb;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if p_values is null or jsonb_typeof(p_values) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_values) x where x not in ('urgent_multiplier','extra_service_fee','max_extra_services','tolls_enabled','max_distance_km','fuel_price_per_litre','peak_multiplier','peak_hours','peak_weekdays','timezone','route_required','commission_percent')) then raise exception 'Configuração de preço inválida.'; end if;
 select value into previous from public.system_settings where key='pricing' for update;
 merged:=previous||p_values;
 if jsonb_typeof(merged->'commission_percent') is distinct from 'number' or (merged->>'commission_percent')::numeric not between 0 and 100 or (merged->>'commission_percent')::numeric<>round((merged->>'commission_percent')::numeric,2) then raise exception 'Comissão deve ser um percentual de 0 a 100, com até duas casas decimais.'; end if;
 foreach k in array array['urgent_multiplier','extra_service_fee','max_extra_services','max_distance_km','fuel_price_per_litre','peak_multiplier'] loop
  n:=(merged->>k)::numeric;
  if n is null or n::text in ('NaN','Infinity','-Infinity') or n<0 or n>10000 then raise exception 'Valor numérico inválido: %',k; end if;
 end loop;
 if (merged->>'urgent_multiplier')::numeric<1 or (merged->>'urgent_multiplier')::numeric>5 or (merged->>'peak_multiplier')::numeric<1 or (merged->>'peak_multiplier')::numeric>5 or (merged->>'fuel_price_per_litre')::numeric>100 or (merged->>'extra_service_fee')::numeric>1000 or (merged->>'max_extra_services')::numeric not between 0 and 5 or (merged->>'max_extra_services')::numeric<>trunc((merged->>'max_extra_services')::numeric) or (merged->>'max_distance_km')::numeric<=0 then raise exception 'Parâmetros fora dos limites de preço.'; end if;
 if merged->>'timezone' is distinct from 'America/Sao_Paulo' or jsonb_typeof(merged->'tolls_enabled') is distinct from 'boolean' or jsonb_typeof(merged->'route_required') is distinct from 'boolean' then raise exception 'Fuso ou opções inválidas.'; end if;
 if jsonb_typeof(merged->'peak_hours') is distinct from 'array' or jsonb_array_length(merged->'peak_hours')>8 or jsonb_typeof(merged->'peak_weekdays') is distinct from 'array' or jsonb_array_length(merged->'peak_weekdays')>7 then raise exception 'Janelas de pico inválidas.'; end if;
 for w in select value from jsonb_array_elements(merged->'peak_hours') loop
  if jsonb_typeof(w) is distinct from 'array' or jsonb_array_length(w)<>2 or jsonb_typeof(w->0) is distinct from 'number' or jsonb_typeof(w->1) is distinct from 'number' or (w->>0)::numeric<0 or (w->>1)::numeric>24 or (w->>0)::numeric>=(w->>1)::numeric or (w->>0)::numeric<>trunc((w->>0)::numeric) or (w->>1)::numeric<>trunc((w->>1)::numeric) then raise exception 'Janela de pico deve ser [hora inicial,hora final].'; end if;
 end loop;
 for wd in select value from jsonb_array_elements(merged->'peak_weekdays') loop
  if jsonb_typeof(wd) is distinct from 'number' or wd::text::numeric not between 1 and 7 or wd::text::numeric<>trunc(wd::text::numeric) then raise exception 'Dias de pico devem ser ISO 1 a 7.'; end if;
 end loop;
 update public.system_settings set value=merged,updated_at=now() where key='pricing';
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'pricing.update','system_settings','pricing',jsonb_build_object('before',previous,'after',merged));
 return merged;
end $$;

revoke all on function public.update_pricing_settings(jsonb) from public,anon;
grant execute on function public.update_pricing_settings(jsonb) to authenticated,service_role;

-- Oportunidades preservam a redação de dados pessoais e mostram a divisão contratada.
create or replace function public.available_deliveries() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.driver_profiles dp join public.profiles p on p.id=dp.id where dp.id=auth.uid() and dp.status='approved' and p.role='driver' and dp.cnh_expires_at>=current_date) then raise exception 'Entregador aprovado e CNH válida necessários.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'code',d.code,'category_id',d.category_id,'total_weight_kg',d.total_weight_kg,'total_volume_m3',d.total_volume_m3,'price',d.price,'commission_percent',d.commission_percent,'commission_amount',d.commission_amount,'driver_amount',case when d.commission_amount is not null then d.price-d.commission_amount else null end,'scheduled_at',d.scheduled_at,'created_at',d.created_at,'pickup_city',d.pickup->>'city','destination_city',d.destination->>'city','distance_km',d.distance_km) order by d.created_at desc) from public.deliveries d where d.status='awaiting_driver' and d.driver_id is null and exists(select 1 from public.vehicles v join public.documents doc on doc.vehicle_id=v.id and doc.status='verified' where v.driver_id=auth.uid() and v.active and v.category_id=d.category_id)),'[]'::jsonb);
end $$;

revoke all on function public.available_deliveries() from public,anon;
grant execute on function public.available_deliveries() to authenticated,service_role;
commit;
