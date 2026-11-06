begin;
create index profiles_requested_role_idx on public.profiles(requested_role);
create index driver_status_idx on public.driver_profiles(status);
create index approval_status_idx on public.approval_requests(kind,status,created_at);
create index approval_history_request_idx on public.approval_history(request_id,created_at);
create index addresses_owner_idx on public.addresses(user_id);
create unique index addresses_one_default_idx on public.addresses(user_id) where is_default;
create index vehicles_driver_idx on public.vehicles(driver_id,category_id) where active;
create index documents_owner_idx on public.documents(user_id,kind,status);
create index documents_vehicle_idx on public.documents(vehicle_id) where vehicle_id is not null;
create index route_quotes_owner_idx on public.route_quotes(user_id,expires_at);
create index deliveries_client_idx on public.deliveries(client_id,created_at desc);
create index deliveries_driver_idx on public.deliveries(driver_id,created_at desc);
create index deliveries_available_idx on public.deliveries(category_id,created_at) where status='awaiting_driver' and driver_id is null;
create index delivery_items_parent_idx on public.delivery_items(delivery_id);
create index delivery_events_parent_idx on public.delivery_events(delivery_id,created_at);
create index payments_user_idx on public.payments(user_id,created_at);
create index notifications_user_idx on public.notifications(user_id,created_at desc);
create index outbox_queue_idx on public.outbox(status,available_at) where status in ('pending','failed','processing');
create index audits_actor_idx on public.audit_logs(actor_id,created_at desc);
create index reviews_driver_idx on public.reviews(driver_id);
create index support_user_idx on public.support_tickets(user_id,created_at);
create index support_status_idx on public.support_tickets(status,created_at);
-- security_invoker exige PostgreSQL 15+, padrão atual do Supabase.
create view public.driver_approvals with(security_invoker=true) as select a.id,a.user_id,p.full_name,a.status,a.created_at,a.justification from public.approval_requests a join public.profiles p on p.id=a.user_id where a.kind='driver';
create view public.admin_approvals with(security_invoker=true) as select a.id,a.user_id,p.full_name,a.status,a.created_at,a.justification from public.approval_requests a join public.profiles p on p.id=a.user_id where a.kind='admin';
create view public.clients with(security_invoker=true) as select id,full_name,requested_role,created_at from public.profiles where requested_role in ('client','seller');
grant select on public.driver_approvals,public.admin_approvals,public.clients to authenticated;
comment on table public.profiles is 'Dados pessoais únicos ligados ao Supabase Auth. Papel não alterável pelo usuário. seller é subtipo de cliente.';
comment on column public.profiles.cpf_cnpj is 'CPF para pessoas; vendedor pode usar CPF ou CNPJ numérico/alfanumérico válido.';
comment on table public.documents is 'Somente metadados; arquivos no bucket privado movee-documents. Retenção documentada em docs/DATABASE.md.';
comment on column public.deliveries.distance_km is 'Estimativa manual informada: sem mapa, geocodificação ou GPS reais nesta configuração.';
comment on column public.payments.is_demo is 'true identifica simulação sem cobrança real; confirmação live somente via serviço e provedor.';
-- Valores especiais de numeric não representam peso, distância, dimensões ou dinheiro.
do $$ declare r record; begin
 for r in select c.table_name,c.column_name from information_schema.columns c where c.table_schema='public' and c.data_type in ('numeric','decimal','real','double precision') loop
  execute format('alter table public.%I add constraint %I check (%I::text not in (''NaN'',''Infinity'',''-Infinity''))',r.table_name,r.table_name||'_'||r.column_name||'_finite',r.column_name);
 end loop;
end $$;
alter table public.vehicle_categories add constraint category_dimensions_sane check(greatest(length_cm,width_cm,height_cm)<=10000);
alter table public.vehicle_categories add constraint category_capacity_sane check(max_weight_kg<=100000 and max_volume_m3<=1000);
alter table public.vehicle_categories add constraint category_text_limits check(length(name) between 2 and 100 and length(description)<=1000 and length(protection)<=1000);
alter table public.vehicle_categories add constraint category_tariff_limits check(greatest(base_price,price_per_km,weight_price,volume_price,operational_fee,protection_fee)<=1000000);
commit;
