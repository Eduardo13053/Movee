begin;
create function private.on_signup() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare m jsonb:=new.raw_user_meta_data; r text:=coalesce(m->>'requested_role','client');
begin
 if coalesce((m->>'terms')::boolean,false) is not true then raise exception 'Aceite os termos e a política de privacidade.'; end if;
 if r not in ('client','seller','driver','admin') then raise exception 'Tipo de conta inválido.'; end if;
 if (m->>'birth_date')::date>current_date-interval '18 years' then raise exception 'Cadastro disponível para maiores de 18 anos.'; end if;
 insert into public.profiles(id,full_name,cpf_cnpj,phone,birth_date,role,requested_role,terms_accepted_at,verification_channel)
 values(new.id,trim(m->>'full_name'),upper(regexp_replace(m->>'cpf_cnpj','[^A-Za-z0-9]','','g')),regexp_replace(m->>'phone','\D','','g'),(m->>'birth_date')::date,'client',r,now(),coalesce(m->>'verification_channel','email'));
 if r='driver' then insert into public.driver_profiles(id) values(new.id); end if;
 perform private.notify(new.id,'Bem-vindo ao Movee','Confirme seu canal e complete os documentos do cadastro.','account.created');
 return new;
end $$;
create trigger movee_signup after insert on auth.users for each row execute function private.on_signup();
create function public.complete_profile(p_full_name text,p_cpf_cnpj text,p_phone text,p_birth_date date,p_requested_role text,p_terms boolean) returns public.profiles language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.profiles;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid() for update;
 if p.id is null then raise exception 'Perfil não encontrado.'; end if;
 if p_requested_role<>p.requested_role or upper(regexp_replace(p_cpf_cnpj,'[^A-Za-z0-9]','','g'))<>p.cpf_cnpj then raise exception 'CPF e tipo solicitado não podem ser alterados pelo usuário.'; end if;
 if p_terms is not true or p_birth_date>current_date-interval '18 years' then raise exception 'Dados ou aceite inválidos.'; end if;
 update public.profiles set full_name=trim(p_full_name),phone=regexp_replace(p_phone,'\D','','g'),birth_date=p_birth_date,updated_at=now() where id=auth.uid() returning * into p;
 return p;
end $$;
create function public.save_driver(p_cnh_number text,p_cnh_category text,p_cnh_expires_at date) returns public.driver_profiles language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.driver_profiles;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and requested_role='driver') then raise exception 'Cadastro de entregador necessário.'; end if;
 if p_cnh_number is null or p_cnh_category is null or p_cnh_expires_at is null or p_cnh_expires_at<current_date then raise exception 'CNH vencida.'; end if;
 select * into d from public.driver_profiles where id=auth.uid() for update;
 if d.status in ('approved','suspended') then raise exception 'Para alterar CNH aprovada ou suspensa, solicite suporte e nova análise.'; end if;
 if (d.cnh_number,d.cnh_category,d.cnh_expires_at) is distinct from (p_cnh_number,p_cnh_category,p_cnh_expires_at) then update public.documents set status='pending' where user_id=auth.uid() and kind='cnh'; end if;
 update public.driver_profiles set cnh_number=p_cnh_number,cnh_category=p_cnh_category,cnh_expires_at=p_cnh_expires_at,status='pending' where id=auth.uid() returning * into d;
 return d;
end $$;
create function public.submit_approval(p_kind text,p_justification text) returns public.approval_requests language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.approval_requests; u public.profiles;
begin
 select * into u from public.profiles where id=auth.uid() for update;
 if u.id is null or u.requested_role<>p_kind or p_kind not in ('driver','admin') then raise exception 'Solicitação não permitida.'; end if;
 if length(trim(p_justification))<10 then raise exception 'Justificativa deve ter pelo menos 10 caracteres.'; end if;
 if not exists(select 1 from public.documents where user_id=u.id and kind='identity' and status<>'rejected') then raise exception 'Envie documento de identidade.'; end if;
 if p_kind='driver' then
  if not exists(select 1 from public.driver_profiles where id=u.id and cnh_number is not null and cnh_category is not null and cnh_expires_at>=current_date) then raise exception 'Preencha os dados da CNH.'; end if;
  if not exists(select 1 from public.documents where user_id=u.id and kind='cnh' and status<>'rejected') then raise exception 'Envie a foto da CNH.'; end if;
  if not exists(select 1 from public.vehicles v join public.documents d on d.vehicle_id=v.id and d.kind='vehicle' and d.status<>'rejected' where v.driver_id=u.id and v.active) then raise exception 'Cadastre e documente ao menos um veículo.'; end if;
 end if;
 select * into a from public.approval_requests where user_id=u.id and kind=p_kind;
 if a.status='pending' then return a; end if;
 if a.status in ('approved','suspended','in_review') then raise exception 'Solicitação já está em análise, aprovada ou suspensa.'; end if;
 insert into public.approval_requests(user_id,kind,justification) values(u.id,p_kind,trim(p_justification)) on conflict(user_id,kind) do update set status='pending',justification=excluded.justification,updated_at=now() returning * into a;
 if p_kind='driver' then update public.driver_profiles set status='pending' where id=u.id; end if;
 insert into public.approval_history(request_id,actor_id,status,reason) values(a.id,u.id,'pending','Solicitação enviada para análise');
 perform private.notify(u.id,'Solicitação recebida','Acompanhe a análise pelo seu perfil.','approval.submitted');
 insert into public.outbox(event,payload) values('approval.admin_notice',jsonb_build_object('to','MoveeEntregas@gmail.com','request_id',a.id,'kind',p_kind,'path','/admin.html'));
 return a;
end $$;
create function public.review_document(p_document_id uuid,p_status text,p_reason text) returns public.documents language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.documents;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if p_status not in ('verified','rejected') or length(trim(p_reason))<3 then raise exception 'Informe uma decisão e justificativa.'; end if;
 update public.documents set status=p_status where id=p_document_id returning * into d;
 if d.id is null then raise exception 'Documento não encontrado.'; end if;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'document.review','documents',d.id::text,jsonb_build_object('status',p_status,'reason',p_reason));
 perform private.notify(d.user_id,'Documento analisado',p_reason,'document.reviewed'); return d;
end $$;
create function public.review_account(p_request_id uuid,p_status text,p_reason text) returns public.approval_requests language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.approval_requests;
begin
 if not private.is_admin() then raise exception 'Acesso administrativo necessário.'; end if;
 if p_status not in ('in_review','approved','rejected','suspended') or length(trim(p_reason))<3 then raise exception 'Decisão e justificativa obrigatórias.'; end if;
 select * into a from public.approval_requests where id=p_request_id for update;
 if a.id is null or a.user_id=auth.uid() then raise exception 'Solicitação inexistente ou autoaprovação proibida.'; end if;
 if p_status='approved' then
  if not exists(select 1 from public.documents where user_id=a.user_id and kind='identity' and status='verified') then raise exception 'Verifique a identidade antes de aprovar.'; end if;
  if a.kind='driver' and (not exists(select 1 from public.documents where user_id=a.user_id and kind='cnh' and status='verified') or not exists(select 1 from public.driver_profiles where id=a.user_id and cnh_number is not null and cnh_category is not null and cnh_expires_at>=current_date) or not exists(select 1 from public.vehicles v join public.documents d on d.vehicle_id=v.id and d.kind='vehicle' and d.status='verified' where v.driver_id=a.user_id and v.active)) then raise exception 'CNH e documentação de veículo válidas e verificadas são obrigatórias.'; end if;
 end if;
 update public.approval_requests set status=p_status,updated_at=now() where id=a.id returning * into a;
 if a.kind='driver' then update public.driver_profiles set status=p_status where id=a.user_id; end if;
 update public.profiles set role=case when p_status='approved' then a.kind else 'client' end,updated_at=now() where id=a.user_id;
 insert into public.approval_history(request_id,actor_id,status,reason) values(a.id,auth.uid(),p_status,p_reason);
 insert into public.audit_logs(actor_id,action,entity,entity_id,details) values(auth.uid(),'account.review','approval_requests',a.id::text,jsonb_build_object('status',p_status,'reason',p_reason));
 perform private.notify(a.user_id,'Atualização da sua solicitação',p_reason,'approval.'||p_status); return a;
end $$;
commit;
