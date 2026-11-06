begin;
create function public.quote_delivery(p_category_id text,p_items jsonb,p_distance_km numeric,p_urgent boolean,p_protection boolean,p_extras numeric,p_tolls numeric,p_scheduled_at timestamptz default null,p_route_id uuid default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.vehicle_categories; i jsonb; w numeric:=0; vol numeric:=0; iw numeric; q int; l numeric; wd numeric; h numeric; cfg jsonb; subtotal numeric; result numeric; b jsonb; fuel numeric; peak_fee numeric; peak_applied boolean:=false; local_time timestamp; peak_window jsonb; hour_num numeric; scheduled timestamptz:=coalesce(p_scheduled_at,now()); rq public.route_quotes;
begin
 select * into c from public.vehicle_categories where id=p_category_id and active;
 select value into cfg from public.system_settings where key='pricing';
 if p_route_id is not null then
  select * into rq from public.route_quotes where id=p_route_id and user_id=auth.uid() and category_id=p_category_id and expires_at>now();
  if rq.id is null or p_distance_km is distinct from rq.distance_km then raise exception 'Cotação de rota inválida, expirada ou distância divergente.'; end if;
 elsif coalesce((cfg->>'route_required')::boolean,false) then raise exception 'Calcule a rota real antes de cotar o frete.'; end if;
 if scheduled<now()-interval '5 minutes' or scheduled>now()+interval '1 year' then raise exception 'Agendamento fora do período permitido.'; end if;
 local_time:=scheduled at time zone (cfg->>'timezone');
 hour_num:=extract(hour from local_time)+extract(minute from local_time)/60;
 if exists(select 1 from jsonb_array_elements_text(cfg->'peak_weekdays') as peak_day(day_value) where peak_day.day_value::int=extract(isodow from local_time)::int) then
  for peak_window in select value from jsonb_array_elements(cfg->'peak_hours') loop
   if hour_num>=(peak_window->>0)::numeric and hour_num<(peak_window->>1)::numeric then peak_applied:=true; end if;
  end loop;
 end if;
 fuel:=case when c.fuel_km_per_litre>0 then round(p_distance_km/c.fuel_km_per_litre*(cfg->>'fuel_price_per_litre')::numeric,2) else 0 end;
 if c.id is null then raise exception 'Categoria indisponível.'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Informe de 1 a 30 mercadorias.'; end if;
 if p_distance_km is null or p_distance_km<=0 or p_distance_km>(cfg->>'max_distance_km')::numeric or p_distance_km::text='NaN' then raise exception 'Distância estimada inválida.'; end if;
 if p_extras is null or p_extras<0 or p_extras>(cfg->>'max_extra_services')::numeric or p_extras<>trunc(p_extras) then raise exception 'Quantidade de serviços extras inválida.'; end if;
 if p_tolls is null or p_tolls<0 or p_tolls>10000 or (p_tolls<>0 and not (cfg->>'tolls_enabled')::boolean) then raise exception 'Pedágios exigem configuração e cotação externa; use zero nesta versão.'; end if;
 for i in select value from jsonb_array_elements(p_items) loop
  if length(trim(i->>'description')) not between 2 and 500 or i->>'description' is null then raise exception 'Descreva cada mercadoria.'; end if;
  if (i->>'quantity')::numeric<>trunc((i->>'quantity')::numeric) then raise exception 'Quantidade deve ser inteira.'; end if;
  q:=(i->>'quantity')::int; iw:=public.weight_kg((i->>'weight')::numeric,i->>'unit');
  l:=(i->>'length_cm')::numeric; wd:=(i->>'width_cm')::numeric; h:=(i->>'height_cm')::numeric;
  if q is null or q not between 1 and 10000 or iw<.000001 or iw>14000 or l is null or wd is null or h is null or least(l,wd,h)<.001 or greatest(l,wd,h)>10000 or l::text='NaN' or wd::text='NaN' or h::text='NaN' then raise exception 'Peso, quantidade ou dimensões inválidos. Peso mínimo 1 mg.'; end if;
  if l>c.length_cm or wd>c.width_cm or h>c.height_cm then raise exception 'Dimensões incompatíveis com o veículo selecionado.'; end if;
  w:=w+iw*q; vol:=vol+l*wd*h*q/1000000;
 end loop;
 if w>c.max_weight_kg or vol>c.max_volume_m3 then raise exception 'Peso ou volume total ultrapassa a capacidade do veículo.'; end if;
 b:=jsonb_build_object('base',c.base_price,'fuel',fuel,'fuel_price_per_litre',(cfg->>'fuel_price_per_litre')::numeric,'fuel_km_per_litre',c.fuel_km_per_litre,'scheduled_time',scheduled,'pricing_timezone',cfg->>'timezone','peak_applied',peak_applied,'distance',round(p_distance_km*c.price_per_km,2),'weight',round(w*c.weight_price,2),'volume',round(vol*c.volume_price,2),'operational',c.operational_fee,'protection',case when p_protection then c.protection_fee else 0 end,'extras',p_extras*(cfg->>'extra_service_fee')::numeric,'tolls',p_tolls,'distance_source',case when p_route_id is null then 'manual_estimate' else 'provider_route' end,'tariffs','fictitious_configurable');
 subtotal:=fuel+c.base_price+round(p_distance_km*c.price_per_km,2)+round(w*c.weight_price,2)+round(vol*c.volume_price,2)+c.operational_fee+(case when p_protection then c.protection_fee else 0 end)+p_extras*(cfg->>'extra_service_fee')::numeric+p_tolls;
 result:=round(subtotal*(case when p_urgent then (cfg->>'urgent_multiplier')::numeric else 1 end),2);
 b:=b||jsonb_build_object('urgency',result-subtotal);
 peak_fee:=case when peak_applied then round(result*((cfg->>'peak_multiplier')::numeric-1),2) else 0 end;
 result:=result+peak_fee; b:=b||jsonb_build_object('peak',peak_fee,'total',result);
 return jsonb_build_object('price',result,'breakdown',b,'total_weight_kg',w,'total_volume_m3',vol);
end $$;
create function public.create_delivery(p_payload jsonb) returns public.deliveries language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; u public.profiles; q jsonb; i jsonb; schedule timestamptz; route_id uuid; rq public.route_quotes;
begin
 select * into u from public.profiles where id=auth.uid();
 if u.id is null or u.role<>'client' or u.requested_role not in ('client','seller') then raise exception 'Utilize uma conta de cliente para solicitar entregas.'; end if;
 if not exists(select 1 from auth.users where id=u.id and email_confirmed_at is not null and (u.verification_channel='email' or (phone_confirmed_at is not null and regexp_replace(phone,'[^0-9]','','g')=(case when length(u.phone) in (10,11) then '55'||u.phone else u.phone end)))) then raise exception 'Confirme o canal escolhido antes de solicitar uma entrega.'; end if;
 if not exists(select 1 from public.documents where user_id=u.id and kind='identity' and status<>'rejected') then raise exception 'Envie um documento oficial de identidade no perfil.'; end if;
 route_id:=nullif(p_payload->>'route_id','')::uuid;
 if route_id is not null then
  select * into rq from public.route_quotes where id=route_id and user_id=auth.uid() and category_id=p_payload->>'category_id' and expires_at>now();
  if rq.id is null or rq.pickup is distinct from p_payload->'pickup' or rq.destination is distinct from p_payload->'destination' then raise exception 'Os endereços devem coincidir com a rota real calculada.'; end if;
 end if;
 schedule:=(p_payload->>'scheduled_at')::timestamptz;
 if schedule is null or schedule<now()-interval '5 minutes' or schedule>now()+interval '1 year' then raise exception 'Data de agendamento inválida.'; end if;
 if not coalesce(public.valid_address(p_payload->'pickup'),false) or not coalesce(public.valid_address(p_payload->'destination'),false) then raise exception 'Preencha os endereços completos.'; end if;
 q:=public.quote_delivery(p_payload->>'category_id',p_payload->'items',(p_payload->>'distance_km')::numeric,coalesce((p_payload->>'urgent')::boolean,false),coalesce((p_payload->>'protection')::boolean,false),coalesce((p_payload->>'extras')::numeric,0),coalesce((p_payload->>'tolls')::numeric,0),schedule,route_id);
 insert into public.deliveries(client_id,category_id,pickup,destination,recipient_name,recipient_phone,distance_km,total_weight_kg,total_volume_m3,price,price_breakdown,scheduled_at,notes,special_instructions,urgent,protection,extras,tolls,route_quote_id,eta_at)
 values(u.id,p_payload->>'category_id',p_payload->'pickup',p_payload->'destination',trim(p_payload->>'recipient_name'),regexp_replace(p_payload->>'recipient_phone','\D','','g'),(p_payload->>'distance_km')::numeric,(q->>'total_weight_kg')::numeric,(q->>'total_volume_m3')::numeric,(q->>'price')::numeric,q->'breakdown',schedule,coalesce(p_payload->>'notes',''),coalesce(p_payload->>'special_instructions',''),coalesce((p_payload->>'urgent')::boolean,false),coalesce((p_payload->>'protection')::boolean,false),coalesce((p_payload->>'extras')::numeric,0),coalesce((p_payload->>'tolls')::numeric,0),route_id,schedule+make_interval(mins=>greatest(30,ceil((p_payload->>'distance_km')::numeric*2+15)::int))) returning * into d;
 for i in select value from jsonb_array_elements(p_payload->'items') loop
  insert into public.delivery_items(delivery_id,description,quantity,unit_weight_kg,length_cm,width_cm,height_cm) values(d.id,trim(i->>'description'),(i->>'quantity')::int,public.weight_kg((i->>'weight')::numeric,i->>'unit'),(i->>'length_cm')::numeric,(i->>'width_cm')::numeric,(i->>'height_cm')::numeric);
 end loop;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,d.status,'Solicitação criada. Aguardando etapa de pagamento.');
 perform private.notify(u.id,'Entrega solicitada',d.code||': confira o pagamento para disponibilizar a entrega.','delivery.created'); return d;
end $$;
create function public.available_deliveries() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.driver_profiles dp join public.profiles p on p.id=dp.id where dp.id=auth.uid() and dp.status='approved' and p.role='driver' and dp.cnh_expires_at>=current_date) then raise exception 'Entregador aprovado e CNH válida necessários.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'code',d.code,'category_id',d.category_id,'total_weight_kg',d.total_weight_kg,'total_volume_m3',d.total_volume_m3,'price',d.price,'scheduled_at',d.scheduled_at,'created_at',d.created_at,'pickup_city',d.pickup->>'city','destination_city',d.destination->>'city','distance_km',d.distance_km) order by d.created_at desc) from public.deliveries d where d.status='awaiting_driver' and d.driver_id is null and exists(select 1 from public.vehicles v join public.documents doc on doc.vehicle_id=v.id and doc.status='verified' where v.driver_id=auth.uid() and v.active and v.category_id=d.category_id)),'[]'::jsonb);
end $$;
create function public.accept_delivery(p_delivery_id uuid,p_vehicle_id uuid) returns public.deliveries language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; v public.vehicles; dp public.driver_profiles;
begin
 select * into dp from public.driver_profiles where id=auth.uid() for share;
 if dp.id is null or dp.status<>'approved' or dp.cnh_number is null or dp.cnh_category is null or dp.cnh_expires_at is null or dp.cnh_expires_at<current_date or not exists(select 1 from public.profiles where id=auth.uid() and role='driver') then raise exception 'Seu cadastro deve estar aprovado e a CNH válida.'; end if;
 select * into v from public.vehicles where id=p_vehicle_id and driver_id=auth.uid() and active for share;
 if v.id is null or not exists(select 1 from public.documents where vehicle_id=v.id and kind='vehicle' and status='verified') then raise exception 'Veículo indisponível ou documento não verificado.'; end if;
 if (v.category_id='motorcycle' and dp.cnh_category not in ('A','AB','AC','AD','AE')) or (v.category_id in ('small_truck','medium_truck','large_truck') and dp.cnh_category not in ('C','AC','D','AD','E','AE')) or (v.category_id not in ('bicycle','motorcycle','small_truck','medium_truck','large_truck') and dp.cnh_category='A') then raise exception 'Categoria de CNH incompatível com o veículo.'; end if;
 select * into d from public.deliveries where id=p_delivery_id for update;
 if d.id is null or d.status<>'awaiting_driver' or d.driver_id is not null then raise exception 'Esta entrega já foi aceita ou está indisponível.'; end if;
 if d.category_id<>v.category_id then raise exception 'Veículo incompatível com a categoria solicitada.'; end if;
 if not exists(select 1 from public.vehicle_categories c where c.id=d.category_id and c.active and c.max_weight_kg>=d.total_weight_kg and c.max_volume_m3>=d.total_volume_m3 and not exists(select 1 from public.delivery_items di where di.delivery_id=d.id and (di.length_cm>c.length_cm or di.width_cm>c.width_cm or di.height_cm>c.height_cm))) then raise exception 'Categoria desativada ou capacidade alterada: solicite revisão da entrega.'; end if;
 update public.deliveries set driver_id=auth.uid(),vehicle_id=v.id,status='to_pickup',updated_at=now() where id=d.id returning * into d;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,d.status,'Entregador a caminho da coleta.');
 perform private.notify(d.client_id,'Entregador designado',d.code||': o entregador está a caminho da coleta.','delivery.assigned'); return d;
end $$;
create function public.advance_delivery(p_delivery_id uuid,p_status text,p_note text,p_recipient_name text default null,p_vehicle_id uuid default null) returns public.deliveries language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; expected text;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 if d.id is null or d.driver_id<>auth.uid() or auth.uid() is null then raise exception 'Você não é o entregador desta entrega.'; end if;
 if p_vehicle_id is null or p_vehicle_id is distinct from d.vehicle_id then raise exception 'Utilize exatamente o veículo designado para esta entrega.'; end if;
 if p_status='collected' and (d.vehicle_confirmed_at is null or d.vehicle_confirmed_by is distinct from d.client_id) then raise exception 'O cliente deve conferir e confirmar modelo e placa antes da coleta.'; end if;
 if not exists(select 1 from public.driver_profiles where id=auth.uid() and status='approved') then raise exception 'Cadastro sem autorização para atualizar entregas. Solicite suporte.'; end if;
 expected:=case d.status when 'to_pickup' then 'collected' when 'collected' then 'in_transit' when 'in_transit' then 'near_destination' when 'near_destination' then 'delivered' else null end;
 if expected is null or p_status<>expected then raise exception 'Transição de status inválida.'; end if;
 if length(coalesce(p_note,''))>2000 then raise exception 'Observação muito longa.'; end if;
 if p_status='delivered' then
  if length(trim(coalesce(p_recipient_name,''))) not between 3 and 160 then raise exception 'Informe o nome de quem recebeu a mercadoria.'; end if;
  insert into public.delivery_proofs(delivery_id,driver_id,recipient_name,notes) values(d.id,auth.uid(),trim(p_recipient_name),coalesce(p_note,''));
 end if;
 update public.deliveries set status=p_status,updated_at=now() where id=d.id returning * into d;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,p_status,coalesce(p_note,''));
 perform private.notify(d.client_id,case when p_status='delivered' then 'Entrega concluída' else 'Sua entrega avançou' end,d.code||': consulte o histórico de acompanhamento.','delivery.'||p_status); return d;
end $$;
create function public.cancel_delivery(p_delivery_id uuid,p_reason text) returns public.deliveries language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 if d.id is null or not coalesce((d.client_id=auth.uid() or private.is_admin()),false) then raise exception 'Entrega indisponível.'; end if;
 if length(trim(p_reason))<3 then raise exception 'Informe o motivo do cancelamento.'; end if;
 if d.status in ('delivered','cancelled') or (not private.is_admin() and d.status not in ('awaiting_payment','awaiting_driver')) then raise exception 'Cancelamento indisponível nesta etapa; solicite suporte.'; end if;
 update public.deliveries set status='cancelled',updated_at=now() where id=d.id returning * into d;
 insert into public.delivery_events(delivery_id,status,note) values(d.id,'cancelled',p_reason);
 -- Nenhum estorno real é inventado: pagamento demonstrativo é marcado; operação real exige provedor.
 update public.payments set status='refunded',updated_at=now() where delivery_id=d.id and is_demo and status='confirmed';
 if private.is_admin() then insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'delivery.cancel','deliveries',d.id::text,jsonb_build_object('reason',p_reason)); end if;
 perform private.notify(d.client_id,'Entrega cancelada',d.code||': '||p_reason,'delivery.cancelled'); return d;
end $$;
create function public.track_delivery(p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; name text;
begin
 select * into d from public.deliveries where code=upper(trim(p_code)) and (client_id=auth.uid() or driver_id=auth.uid() or private.is_admin());
 if d.id is null then return null; end if;
 select split_part(full_name,' ',1) into name from public.profiles where id=d.driver_id;
 return jsonb_build_object('delivery',jsonb_build_object('code',d.code,'status',d.status,'eta_at',d.eta_at,'created_at',d.created_at,'driver_name',name,'vehicle_confirmed_at',d.vehicle_confirmed_at,'vehicle',(select jsonb_build_object('id',v.id,'category_id',v.category_id,'brand',v.brand,'model',v.model,'plate',v.plate) from public.vehicles v where v.id=d.vehicle_id)),'events',coalesce((select jsonb_agg(jsonb_build_object('status',e.status,'note',e.note,'created_at',e.created_at) order by e.created_at,e.id) from public.delivery_events e where delivery_id=d.id),'[]'::jsonb));
end $$;
create function public.assigned_vehicle(p_delivery_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries;
begin
 select * into d from public.deliveries where id=p_delivery_id and (client_id=auth.uid() or driver_id=auth.uid() or private.is_admin());
 if d.id is null then raise exception 'Entrega não encontrada ou sem permissão.'; end if;
 return (select jsonb_build_object('id',v.id,'category_id',v.category_id,'brand',v.brand,'model',v.model,'plate',v.plate,'vehicle_confirmed_at',d.vehicle_confirmed_at) from public.vehicles v where v.id=d.vehicle_id);
end $$;
create function public.confirm_pickup_vehicle(p_delivery_id uuid,p_matches boolean,p_note text) returns public.deliveries language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries;
begin
 select * into d from public.deliveries where id=p_delivery_id for update;
 if auth.uid() is null or d.id is null or d.client_id<>auth.uid() or d.status<>'to_pickup' then raise exception 'Apenas o cliente pode conferir o veículo antes da coleta.'; end if;
 if p_matches is null or p_note is null or length(trim(p_note)) not between 3 and 2000 then raise exception 'Informe o resultado da conferência e uma observação.'; end if;
 if p_matches then
  update public.deliveries set vehicle_confirmed_at=now(),vehicle_confirmed_by=auth.uid(),updated_at=now() where id=d.id returning * into d;
  insert into public.delivery_events(delivery_id,status,note) values(d.id,d.status,'Cliente confirmou modelo e placa do veículo designado.');
  perform private.notify(d.driver_id,'Veículo confirmado pelo cliente',d.code||': a coleta foi liberada para o veículo designado.','delivery.vehicle_confirmed');
 else
  if d.vehicle_confirmed_at is null and exists(select 1 from public.support_tickets where delivery_id=d.id and subject='Divergência de veículo na coleta' and status in ('open','in_progress')) then return d; end if;
  update public.deliveries set vehicle_confirmed_at=null,vehicle_confirmed_by=null,updated_at=now() where id=d.id returning * into d;
  insert into public.support_tickets(user_id,delivery_id,subject,message) values(d.client_id,d.id,'Divergência de veículo na coleta','Veículo divergente: '||p_note);
  insert into public.delivery_events(delivery_id,status,note) values(d.id,d.status,'Cliente informou divergência de veículo; coleta bloqueada para análise do suporte.');
  perform private.notify(d.client_id,'Coleta bloqueada para conferência',d.code||': o suporte recebeu a divergência de veículo.','delivery.vehicle_mismatch');
  perform private.notify(d.driver_id,'Divergência de veículo informada',d.code||': a coleta permanece bloqueada. Consulte o suporte.','delivery.vehicle_mismatch');
  insert into public.notifications(user_id,title,body) select id,'Divergência de veículo',d.code||': consulte o chamado de suporte.' from public.profiles where role='admin';
 end if;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'delivery.vehicle_check','deliveries',d.id::text,jsonb_build_object('matches',p_matches,'note',p_note,'vehicle_id',d.vehicle_id));
 return d;
end $$;
commit;
