begin;
-- Deny by default. RLS também se aplica a chamadas diretas que ignorem o PHP.
do $$ declare t text; begin foreach t in array array['system_settings','profiles','driver_profiles','approval_requests','approval_history','addresses','vehicle_categories','vehicles','documents','route_quotes','deliveries','delivery_items','delivery_events','payments','notifications','outbox','audit_logs','reviews','delivery_proofs','support_tickets'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on table public.%I from anon, authenticated',t); end loop; end $$;
grant usage on schema public to anon,authenticated,service_role;
grant all on all tables in schema public to service_role;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy drivers_read on public.driver_profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy approvals_read on public.approval_requests for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy approval_history_read on public.approval_history for select to authenticated using(public.is_admin() or exists(select 1 from public.approval_requests a where a.id=request_id and a.user_id=auth.uid()));
create policy addresses_read on public.addresses for select to authenticated using(user_id=auth.uid());
create policy addresses_insert on public.addresses for insert to authenticated with check(user_id=auth.uid());
create policy addresses_update on public.addresses for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy addresses_delete on public.addresses for delete to authenticated using(user_id=auth.uid());
create policy categories_read on public.vehicle_categories for select to anon,authenticated using(active or public.is_admin());
create policy vehicles_read on public.vehicles for select to authenticated using(driver_id=auth.uid() or public.is_admin());
create policy vehicles_insert on public.vehicles for insert to authenticated with check(driver_id=auth.uid() and exists(select 1 from public.driver_profiles where id=auth.uid()));
create policy vehicles_update on public.vehicles for update to authenticated using(driver_id=auth.uid()) with check(driver_id=auth.uid());
create policy vehicles_delete on public.vehicles for delete to authenticated using(driver_id=auth.uid());
create policy documents_read on public.documents for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy documents_insert on public.documents for insert to authenticated with check(user_id=auth.uid() and status='pending');
create policy deliveries_read on public.deliveries for select to authenticated using(client_id=auth.uid() or driver_id=auth.uid() or public.is_admin());
create policy items_read on public.delivery_items for select to authenticated using(exists(select 1 from public.deliveries d where d.id=delivery_id and (d.client_id=auth.uid() or d.driver_id=auth.uid() or public.is_admin())));
create policy events_read on public.delivery_events for select to authenticated using(exists(select 1 from public.deliveries d where d.id=delivery_id and (d.client_id=auth.uid() or d.driver_id=auth.uid() or public.is_admin())));
create policy payments_read on public.payments for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notifications_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy reviews_read on public.reviews for select to authenticated using(client_id=auth.uid() or driver_id=auth.uid() or public.is_admin());
create policy reviews_insert on public.reviews for insert to authenticated with check(client_id=auth.uid());
create policy proofs_read on public.delivery_proofs for select to authenticated using(exists(select 1 from public.deliveries d where d.id=delivery_id and (d.client_id=auth.uid() or d.driver_id=auth.uid() or public.is_admin())));
create policy support_read on public.support_tickets for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy support_insert on public.support_tickets for insert to authenticated with check(user_id=auth.uid() and status='open' and admin_reply='');
create policy support_update on public.support_tickets for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy audits_read on public.audit_logs for select to authenticated using(public.is_admin());
create policy settings_read on public.system_settings for select to authenticated using(public.is_admin());
grant select on public.profiles,public.driver_profiles,public.approval_requests,public.approval_history,public.addresses,public.vehicles,public.documents,public.deliveries,public.delivery_items,public.delivery_events,public.payments,public.notifications,public.reviews,public.delivery_proofs,public.support_tickets,public.audit_logs,public.system_settings to authenticated;
grant select on public.vehicle_categories to anon,authenticated;
grant insert(user_id,label,postal_code,street,number,complement,neighborhood,city,state,reference,is_default) on public.addresses to authenticated;
grant update(label,postal_code,street,number,complement,neighborhood,city,state,reference,is_default) on public.addresses to authenticated;
grant delete on public.addresses to authenticated;
grant insert(driver_id,category_id,brand,model,plate,year,active) on public.vehicles to authenticated;
grant update(category_id,brand,model,plate,year,active) on public.vehicles to authenticated;
grant delete on public.vehicles to authenticated;
grant insert(user_id,vehicle_id,kind,storage_path,mime_type,size_bytes) on public.documents to authenticated;
grant update(read_at) on public.notifications to authenticated;
grant insert(delivery_id,client_id,driver_id,rating,comment) on public.reviews to authenticated;
grant insert(user_id,delivery_id,subject,message) on public.support_tickets to authenticated;
grant update(status,admin_reply) on public.support_tickets to authenticated;
-- Todos os RPCs devem ser explicitamente concedidos. Chave pública nunca é serviço.
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.valid_cpf(text),public.valid_cnpj(text),public.valid_tax_id(text),public.valid_phone(text),public.valid_full_name(text),public.valid_address(jsonb),public.weight_kg(numeric,text),public.is_admin() to anon,authenticated;
grant execute on function public.complete_profile(text,text,text,date,text,boolean),public.save_driver(text,text,date),public.submit_approval(text,text),public.review_document(uuid,text,text),public.review_account(uuid,text,text),public.create_delivery(jsonb),public.available_deliveries(),public.accept_delivery(uuid,uuid),public.advance_delivery(uuid,text,text,text,uuid),public.cancel_delivery(uuid,text),public.track_delivery(text),public.update_tariff(text,jsonb),public.admin_report(),public.get_pricing_settings(),public.update_pricing_settings(jsonb),public.assigned_vehicle(uuid),public.confirm_pickup_vehicle(uuid,boolean,text),public.log_document_access(uuid) to authenticated;
grant execute on function public.quote_delivery(text,jsonb,numeric,boolean,boolean,numeric,numeric,timestamptz,uuid) to anon,authenticated;
grant execute on all functions in schema public to service_role;
-- Upload de Storage somente pelo PHP com service_role após validar bytes; JWT de usuário não pode inserir objetos.
-- Storage privado; SVG/HTML/executáveis não são aceitos. O PHP também inspeciona assinatura MIME.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('movee-documents','movee-documents',false,5242880,array['image/jpeg','image/png','application/pdf']);
-- Sem SELECT/INSERT/UPDATE/DELETE de Storage para JWT público: BFF autoriza/audita via log_document_access e assina por serviço.
-- Sem UPDATE/DELETE público: URLs assinadas curtas, auditoria de consulta via BFF, retenção por operador.
commit;
