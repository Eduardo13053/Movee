-- Movee 20: confirmação de e-mail obrigatória para a conta autenticada.
-- Instalação nova: execute01..20. Banco já atualizadoaté19: executesomente20.
-- A fonte de verdade é auth.users.email_confirmed_at; metadata não confirma e-mail.
-- Ative Confirm email em Supabase Auth e configure o template/SMTP entregue no site.
begin;

create or replace function private.email_is_verified() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null)
$$;
revoke all on function private.email_is_verified() from public,anon,authenticated;

-- Wrapper mínimo para políticas: o schema private continua sem acesso público.
create or replace function public.email_is_verified() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select private.email_is_verified()
$$;
revoke all on function public.email_is_verified() from public;
grant execute on function public.email_is_verified() to anon,authenticated,service_role;

create or replace function private.require_confirmed_email() returns void
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not private.email_is_verified() then
  raise exception 'Confirme seu e-mail antes de acessar a conta.' using errcode='P0001';
 end if;
end $$;
revoke all on function private.require_confirmed_email() from public,anon,authenticated;

-- Mesmo um papel administrativo antigo precisa do canal de e-mail confirmado.
create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select private.email_is_verified() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')
$$;
revoke all on function private.is_admin() from public,anon,authenticated;

-- Políticas permissivas anteriores continuam determinando propriedade/papel.
-- Esta política RESTRITIVA é combinada com todas elas e bloqueia JWT não confirmado.
do $$declare t text;
begin
 foreach t in array array['system_settings','profiles','driver_profiles','approval_requests','approval_history','addresses','vehicles','documents','route_quotes','deliveries','delivery_items','delivery_events','payments','notifications','outbox','audit_logs','reviews','delivery_proofs','support_tickets'] loop
  execute format('drop policy if exists email_confirmation_required on public.%I',t);
  execute format('create policy email_confirmation_required on public.%I as restrictive for all to authenticated using(public.email_is_verified()) with check(public.email_is_verified())',t);
 end loop;
end $$;

-- Funções SECURITY DEFINER também estão cobertas ao escrever dados de negócio.
-- auth.uid() nulo identifica rotinas internas de Auth/serviço: signup, fila e webhook
-- não representam uma sessão de usuário e mantêm o fluxo já protegido por grants.
create or replace function private.guard_verified_account_write() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is not null then perform private.require_confirmed_email(); end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function private.guard_verified_account_write() from public,anon,authenticated;
do $$declare t text;
begin
 foreach t in array array['system_settings','profiles','driver_profiles','approval_requests','approval_history','addresses','vehicles','documents','route_quotes','deliveries','delivery_items','delivery_events','payments','notifications','outbox','audit_logs','reviews','delivery_proofs','support_tickets'] loop
  execute format('drop trigger if exists a_require_confirmed_email on public.%I',t);
  execute format('create trigger a_require_confirmed_email before insert or update or delete on public.%I for each row execute function private.guard_verified_account_write()',t);
 end loop;
end $$;

-- RPCs de consulta com SECURITY DEFINER exigem confirmação antes da leitura.

create or replace function public.available_deliveries() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform private.require_confirmed_email();
 if not exists(select 1 from public.driver_profiles dp join public.profiles p on p.id=dp.id where dp.id=auth.uid() and dp.status='approved' and p.role='driver' and dp.cnh_expires_at>=current_date) then raise exception 'Entregador aprovado e CNH válida necessários.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'code',d.code,'category_id',d.category_id,'total_weight_kg',d.total_weight_kg,'total_volume_m3',d.total_volume_m3,'price',d.price,'commission_percent',d.commission_percent,'commission_amount',d.commission_amount,'driver_amount',case when d.commission_amount is not null then d.price-d.commission_amount else null end,'scheduled_at',d.scheduled_at,'created_at',d.created_at,'pickup_city',d.pickup->>'city','destination_city',d.destination->>'city','distance_km',d.distance_km) order by d.created_at desc) from public.deliveries d where d.status='awaiting_driver' and d.driver_id is null and exists(select 1 from public.vehicles v join public.documents doc on doc.vehicle_id=v.id and doc.status='verified' where v.driver_id=auth.uid() and v.active and v.category_id=d.category_id)),'[]'::jsonb);
end $$;
revoke all on function public.available_deliveries() from public,anon;
grant execute on function public.available_deliveries() to authenticated,service_role;


create or replace function public.assigned_vehicle(p_delivery_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries;
begin
 perform private.require_confirmed_email();
 select * into d from public.deliveries where id=p_delivery_id and (client_id=auth.uid() or driver_id=auth.uid() or private.is_admin());
 if d.id is null then raise exception 'Entrega não encontrada ou sem permissão.'; end if;
 return (select jsonb_build_object('id',v.id,'category_id',v.category_id,'brand',v.brand,'model',v.model,'plate',v.plate,'vehicle_confirmed_at',d.vehicle_confirmed_at) from public.vehicles v where v.id=d.vehicle_id);
end $$;
revoke all on function public.assigned_vehicle(uuid) from public,anon;
grant execute on function public.assigned_vehicle(uuid) to authenticated,service_role;


create or replace function public.track_delivery(p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.deliveries; name text;
begin
 perform private.require_confirmed_email();
 select * into d from public.deliveries where code=upper(trim(p_code)) and (client_id=auth.uid() or driver_id=auth.uid() or private.is_admin());
 if d.id is null then return null; end if;
 select split_part(full_name,' ',1) into name from public.profiles where id=d.driver_id;
 return jsonb_build_object('delivery',jsonb_build_object('code',d.code,'status',d.status,'eta_at',d.eta_at,'created_at',d.created_at,'driver_name',name,'vehicle_confirmed_at',d.vehicle_confirmed_at,'vehicle',(select jsonb_build_object('id',v.id,'category_id',v.category_id,'brand',v.brand,'model',v.model,'plate',v.plate) from public.vehicles v where v.id=d.vehicle_id)),'events',coalesce((select jsonb_agg(jsonb_build_object('status',e.status,'note',e.note,'created_at',e.created_at) order by e.created_at,e.id) from public.delivery_events e where delivery_id=d.id),'[]'::jsonb));
end $$;
revoke all on function public.track_delivery(text) from public,anon;
grant execute on function public.track_delivery(text) to authenticated,service_role;


comment on function public.email_is_verified() is 'Confirmação canônica em Supabase Auth; não usa metadata editável nem códigos fixos.';
commit;
