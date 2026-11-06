begin;
alter table public.payments add column provider text not null default 'demo' check(provider in ('demo','mercadopago'));
alter table public.payments add column currency text not null default 'BRL' check(currency='BRL');
create function public.update_tariff(p_category_id text,p_values jsonb) returns public.vehicle_categories language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.vehicle_categories; before_row jsonb;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if exists(select 1 from jsonb_object_keys(p_values) k where k not in ('base_price','price_per_km','weight_price','volume_price','operational_fee','protection_fee','active','name','description','protection','max_weight_kg','max_volume_m3','length_cm','width_cm','height_cm','fuel_km_per_litre')) then raise exception 'Parâmetro de tarifa desconhecido.'; end if;
 select to_jsonb(v) into before_row from public.vehicle_categories v where id=p_category_id for update;
 if before_row is null then raise exception 'Categoria não encontrada.'; end if;
 update public.vehicle_categories set fuel_km_per_litre=coalesce((p_values->>'fuel_km_per_litre')::numeric,fuel_km_per_litre),base_price=coalesce((p_values->>'base_price')::numeric,base_price),price_per_km=coalesce((p_values->>'price_per_km')::numeric,price_per_km),weight_price=coalesce((p_values->>'weight_price')::numeric,weight_price),volume_price=coalesce((p_values->>'volume_price')::numeric,volume_price),operational_fee=coalesce((p_values->>'operational_fee')::numeric,operational_fee),protection_fee=coalesce((p_values->>'protection_fee')::numeric,protection_fee),active=coalesce((p_values->>'active')::boolean,active),name=coalesce(p_values->>'name',name),description=coalesce(p_values->>'description',description),protection=coalesce(p_values->>'protection',protection),max_weight_kg=coalesce((p_values->>'max_weight_kg')::numeric,max_weight_kg),max_volume_m3=coalesce((p_values->>'max_volume_m3')::numeric,max_volume_m3),length_cm=coalesce((p_values->>'length_cm')::numeric,length_cm),width_cm=coalesce((p_values->>'width_cm')::numeric,width_cm),height_cm=coalesce((p_values->>'height_cm')::numeric,height_cm) where id=p_category_id returning * into c;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'tariff.update','vehicle_categories',c.id,jsonb_build_object('before',before_row,'after',to_jsonb(c))); return c;
end $$;
create function public.admin_report() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 return jsonb_build_object('pricing',(select value from public.system_settings where key='pricing'),'users',(select count(*) from public.profiles),'deliveries',(select count(*) from public.deliveries),'delivered',(select count(*) from public.deliveries where status='delivered'),'active',(select count(*) from public.deliveries where status not in ('delivered','cancelled')),'pending_approvals',(select count(*) from public.approval_requests where status in ('pending','in_review')),'demo_revenue',(select coalesce(sum(amount),0) from public.payments where status='confirmed' and is_demo),'live_revenue',(select coalesce(sum(amount),0) from public.payments where status='confirmed' and not is_demo),'by_status',(select coalesce(jsonb_object_agg(status,n),'{}') from (select status,count(*) n from public.deliveries group by status) s),'daily',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (select created_at::date AS "day",count(*) deliveries from public.deliveries group by 1 order by 1 desc limit 30) s));
end $$;
create function public.record_demo_payment(p_delivery_id uuid,p_method text) returns public.payments language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; p public.payments;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 if d.id is null then raise exception 'Entrega não encontrada.'; end if;
 select * into p from public.payments where delivery_id=d.id;
 if p.id is not null and p.status='confirmed' and p.is_demo then return p; end if;
 if d.status<>'awaiting_payment' or p.id is not null then raise exception 'Pagamento indisponível nesta etapa.'; end if;
 insert into public.payments(delivery_id,user_id,method,status,amount,is_demo,provider_reference,provider) values(d.id,d.client_id,p_method,'confirmed',d.price,true,'DEMO-'||d.id::text,'demo') returning * into p;
 update public.deliveries set status='awaiting_driver',updated_at=now() where id=d.id;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,'awaiting_driver','Pagamento DEMONSTRATIVO registrado. Nenhum valor real foi movimentado.');
 perform private.notify(d.client_id,'Pagamento demonstrativo confirmado',d.code||': nenhum valor real foi cobrado.','payment.confirmed'); return p;
end $$;
create function public.prepare_provider_payment(p_delivery_id uuid,p_method text,p_preference_id text) returns public.payments language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; p public.payments;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 if d.id is null or d.status<>'awaiting_payment' or p_preference_id is null or length(trim(p_preference_id))<3 then raise exception 'Entrega indisponível para pagamento.'; end if;
 select * into p from public.payments where delivery_id=d.id;
 if p.id is not null and (p.is_demo or p.status='confirmed') then raise exception 'Pagamento já existente.'; end if;
 insert into public.payments(delivery_id,user_id,method,status,amount,is_demo,provider_reference,provider) values(d.id,d.client_id,p_method,'pending',d.price,false,p_preference_id,'mercadopago') on conflict(delivery_id) do update set provider_reference=excluded.provider_reference,method=excluded.method,updated_at=now() returning * into p;
 return p;
end $$;
create function public.confirm_provider_payment(p_delivery_id uuid,p_transaction_id text,p_amount numeric,p_currency text) returns public.payments language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; p public.payments;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 select * into p from public.payments where delivery_id=p_delivery_id for update;
 if d.id is null or p.id is null or p.is_demo or p_currency is distinct from 'BRL' or p_amount is null or p_amount is distinct from d.price or p.amount is distinct from p_amount or p_transaction_id is null or length(trim(p_transaction_id))<1 then raise exception 'Pagamento incompatível com a entrega.'; end if;
 if p.status='confirmed' and p.provider_reference=p_transaction_id then return p; end if;
 if p.status='confirmed' or d.status<>'awaiting_payment' then raise exception 'Entrega já processada ou cancelada; analise o pagamento pelo provedor.'; end if;
 update public.payments set status='confirmed',provider_reference=p_transaction_id,updated_at=now() where id=p.id returning * into p;
 update public.deliveries set status='awaiting_driver',updated_at=now() where id=d.id;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,'awaiting_driver','Pagamento confirmado pelo provedor.');
 perform private.notify(d.client_id,'Pagamento confirmado',d.code||': aguardando entregador.','payment.confirmed'); return p;
end $$;
create function public.bootstrap_admin(p_user_id uuid) returns public.profiles language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.profiles;
begin
 perform pg_advisory_xact_lock(91561001);
 if exists(select 1 from public.profiles where role='admin') then raise exception 'Já existe administrador. Utilize o fluxo de aprovação.'; end if;
 select * into p from public.profiles where id=p_user_id and requested_role='admin' for update;
 if p.id is null or not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) or not exists(select 1 from public.documents where user_id=p_user_id and kind='identity' and status<>'rejected') then raise exception 'Primeiro administrador deve ser cadastrado, confirmar e-mail e enviar identidade; confira o documento manualmente antes do bootstrap.'; end if;
 update public.profiles set role='admin',updated_at=now() where id=p.id returning * into p;
 insert into public.documents as d (id,user_id,vehicle_id,kind,storage_path,mime_type,size_bytes,status,created_at) select id,user_id,vehicle_id,kind,storage_path,mime_type,size_bytes,'verified',created_at from public.documents where user_id=p.id and kind='identity' on conflict(id) do update set status='verified';
 insert into public.approval_requests(user_id,kind,status,justification) values(p.id,'admin','approved','Bootstrap inicial por operador com chave de serviço') on conflict(user_id,kind) do update set status='approved' returning id into p_user_id;
 insert into public.approval_history(request_id,actor_id,status,reason) values(p_user_id,null,'approved','Bootstrap inicial executado por operador de infraestrutura');
 insert into public.audit_logs(action,entity,entity_id,details) values('admin.bootstrap','profiles',p.id::text,'{"actor":"trusted_service_operator"}');
 perform private.notify(p.id,'Acesso administrativo configurado','Você é o primeiro administrador do Movee.','approval.approved'); return p;
end $$;
create function public.claim_outbox(p_limit int default 20) returns setof public.outbox language sql security definer set search_path=public,pg_temp as $$
 update public.outbox set status='processing',locked_at=now(),attempts=attempts+1 where id in (select id from public.outbox where ((status in ('pending','failed') and available_at<=now()) or (status='processing' and locked_at<now()-interval '15 minutes')) and attempts<8 order by created_at for update skip locked limit least(greatest(p_limit,1),100)) returning *
$$;
create function public.finish_outbox(p_id uuid,p_success boolean,p_error text default null) returns void language sql security definer set search_path=public,pg_temp as $$
 update public.outbox set status=case when p_success then 'sent' else 'failed' end,last_error=case when p_success then null else left(p_error,500) end,available_at=now()+interval '5 minutes',locked_at=null where id=p_id and status='processing'
$$;
create function public.log_document_access(p_document_id uuid) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.documents;
begin
 select * into d from public.documents where id=p_document_id and (user_id=auth.uid() or private.is_admin());
 if d.id is null then raise exception 'Documento indisponível.'; end if;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'document.access','documents',d.id::text,'{"access":"signed_url_requested"}'); return d.storage_path;
end $$;
create function public.get_pricing_settings() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 return (select value from public.system_settings where key='pricing');
end $$;
create function public.update_pricing_settings(p_values jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare merged jsonb; previous jsonb; k text; n numeric; w jsonb; wd jsonb;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if p_values is null or jsonb_typeof(p_values) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_values) x where x not in ('urgent_multiplier','extra_service_fee','max_extra_services','tolls_enabled','max_distance_km','fuel_price_per_litre','peak_multiplier','peak_hours','peak_weekdays','timezone','route_required')) then raise exception 'Configuração de preço inválida.'; end if;
 select value into previous from public.system_settings where key='pricing' for update;
 merged:=previous||p_values;
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
create function public.store_route_quote(p_user_id uuid,p_category_id text,p_pickup jsonb,p_destination jsonb,p_distance_km numeric,p_duration_minutes numeric,p_expires_at timestamptz) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
 if p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+interval '1 hour' then raise exception 'Validade de rota inválida.'; end if;
 insert into public.route_quotes(user_id,category_id,pickup,destination,distance_km,duration_minutes,expires_at) values(p_user_id,p_category_id,p_pickup,p_destination,p_distance_km,p_duration_minutes,p_expires_at) returning id into result;
 return result;
end $$;
commit;
