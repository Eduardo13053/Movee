begin;
create function private.address_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 -- Lock de linha do perfil serializa cadastros simultâneos do mesmo titular.
 perform 1 from public.profiles where id=new.user_id for update;
 if tg_op='INSERT' and (select count(*) from public.addresses where user_id=new.user_id)>=3 then raise exception 'Limite de três endereços atingido.'; end if;
 if tg_op='UPDATE' and new.user_id<>old.user_id then raise exception 'Titular do endereço não pode mudar.'; end if;
 if new.is_default then update public.addresses set is_default=false where user_id=new.user_id and id<>new.id and is_default; end if;
 return new;
end $$;
create trigger addresses_guard before insert or update on public.addresses for each row execute function private.address_guard();
create function private.vehicle_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='UPDATE' and new is distinct from old and exists(select 1 from public.deliveries where vehicle_id=old.id and status in ('to_pickup','collected','in_transit','near_destination')) then raise exception 'Veículo designado para entrega em andamento não pode ser alterado ou desativado.'; end if;
 if tg_op='UPDATE' and (new.driver_id<>old.driver_id or new.id<>old.id) then raise exception 'Titular do veículo não pode mudar.'; end if;
 if tg_op='UPDATE' and (new.category_id,new.brand,new.model,new.plate,new.year) is distinct from (old.category_id,old.brand,old.model,old.plate,old.year) and exists(select 1 from public.documents where vehicle_id=old.id and status='verified') then raise exception 'Veículo verificado: solicite ao suporte a alteração de documentação.'; end if;
 return new;
end $$;
create trigger vehicles_guard before update on public.vehicles for each row execute function private.vehicle_guard();
create function private.document_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if split_part(new.storage_path,'/',1)<>new.user_id::text then raise exception 'Caminho de documento inválido.'; end if;
 if new.vehicle_id is not null and not exists(select 1 from public.vehicles where id=new.vehicle_id and driver_id=new.user_id) then raise exception 'Veículo não pertence ao titular.'; end if;
 if not exists(select 1 from storage.objects where bucket_id='movee-documents' and name=new.storage_path) then raise exception 'Arquivo não encontrado no armazenamento privado.'; end if;
 return new;
end $$;
create trigger documents_guard before insert on public.documents for each row execute function private.document_guard();
create function private.review_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.deliveries where id=new.delivery_id and client_id=new.client_id and driver_id=new.driver_id and status='delivered') then raise exception 'Avaliação permitida somente para sua entrega concluída.'; end if;
 return new;
end $$;
create trigger reviews_guard before insert on public.reviews for each row execute function private.review_guard();
create function private.support_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='INSERT' and new.delivery_id is not null and not exists(select 1 from public.deliveries where id=new.delivery_id and (client_id=new.user_id or driver_id=new.user_id)) then raise exception 'Entrega não vinculada ao solicitante.'; end if;
 if tg_op='UPDATE' then
  if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
  insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'support.update','support_tickets',new.id::text,jsonb_build_object('status',new.status,'reply',new.admin_reply));
  if new.admin_reply is distinct from old.admin_reply then perform private.notify(new.user_id,'Seu suporte recebeu uma resposta',new.subject||': acesse a central de ajuda.','support.replied'); end if;
 end if;
 return new;
end $$;
create trigger support_guard before insert or update on public.support_tickets for each row execute function private.support_guard();
create function private.on_confirmation() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if (new.email_confirmed_at is not null and old.email_confirmed_at is null) or (new.phone_confirmed_at is not null and old.phone_confirmed_at is null) then perform private.notify(new.id,'Canal confirmado','Seu canal de contato foi confirmado. Complete os documentos do perfil.','account.confirmed'); end if;
 return new;
end $$;
create trigger movee_confirmation after update of email_confirmed_at,phone_confirmed_at on auth.users for each row execute function private.on_confirmation();
commit;
