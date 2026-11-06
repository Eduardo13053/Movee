-- APENAS projeto/base de testes descartável após01..20. Não envia e-mail real.
-- Simula o estado canônico de Auth para testar RLS, RPCs e confirmação de canal.
-- Dados e mudanças são removidos por ROLLBACK.
begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
create function pg_temp.expect_confirmation_error(command text,msg text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then
  if sqlerrm like '%Confirme seu e-mail%' then return; end if;
  raise exception 'ERRO DIFERENTE (%): %',msg,sqlerrm;
 end;
 raise exception 'EXPECTED CONFIRMATION ERROR: %',msg;
end $$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_confirmation_error(text,text) to authenticated,anon,service_role;

insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('20000000-0000-4000-8000-000000000001','unconfirmed@movee.invalid',null,'{"full_name":"Cliente Pendente","cpf_cnpj":"52998224725","phone":"11999991234","birth_date":"1990-01-01","requested_role":"client","terms":true,"email_confirmed_at":"2026-01-01"}'),
('20000000-0000-4000-8000-000000000002','confirmed@movee.invalid',now(),'{"full_name":"Cliente Confirmado","cpf_cnpj":"11144477735","phone":"11988881234","birth_date":"1990-01-01","requested_role":"client","terms":true}'),
('20000000-0000-4000-8000-000000000003','admin-pending@movee.invalid',null,'{"full_name":"Admin Pendente","cpf_cnpj":"12345678909","phone":"11977771234","birth_date":"1990-01-01","requested_role":"admin","terms":true}'),
('20000000-0000-4000-8000-000000000004','driver-pending@movee.invalid',null,'{"full_name":"Entregador Pendente","cpf_cnpj":"16899535009","phone":"11966661234","birth_date":"1990-01-01","requested_role":"driver","terms":true}'),
('20000000-0000-4000-8000-000000000005','seller-pending@movee.invalid',null,'{"full_name":"Loja Pendente","cpf_cnpj":"11222333000181","phone":"11955551234","birth_date":"1990-01-01","requested_role":"seller","terms":true}');
update public.profiles set role='admin' where id='20000000-0000-4000-8000-000000000003';
update public.profiles set role='driver' where id='20000000-0000-4000-8000-000000000004';
update public.driver_profiles set status='approved',cnh_number='12345678901',cnh_category='AB',cnh_expires_at=current_date+365 where id='20000000-0000-4000-8000-000000000004';
insert into public.addresses(user_id,label,postal_code,street,number,neighborhood,city,state) values
('20000000-0000-4000-8000-000000000001','Casa','01001000','Praça da Sé','1','Sé','São Paulo','SP'),
('20000000-0000-4000-8000-000000000002','Casa','01001000','Praça da Sé','2','Sé','São Paulo','SP');

set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(not public.email_is_verified(),'metadata não substitui confirmação nativa de Auth');
select pg_temp.assert_true((select count(*)=0 from public.profiles),'perfil protegido antes da confirmação');
select pg_temp.assert_true((select count(*)=0 from public.addresses),'endereços não são legíveis com JWT não confirmado');
select pg_temp.expect_confirmation_error($q$select public.complete_profile('Cliente Pendente','52998224725','11999991234','1990-01-01','client',true)$q$,'RPC definer de perfil não ignora e-mail');
select pg_temp.expect_confirmation_error($q$select public.track_delivery('MV-NAOEXISTE')$q$,'rastreamento exige confirmação mesmo sem resultado');
select pg_temp.expect_confirmation_error($q$select public.assigned_vehicle(gen_random_uuid())$q$,'veículo designado exige confirmação');
select pg_temp.expect_confirmation_error($q$insert into public.addresses(label,postal_code,street,number,neighborhood,city,state) values('Trabalho','01001000','Praça da Sé','3','Sé','São Paulo','SP')$q$,'insert direto é bloqueado');
update public.addresses set street='Rua Alterada' where user_id=auth.uid();
select pg_temp.assert_true((select count(*)=0 from public.addresses),'update direto não revela nem altera endereço oculto');

select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(not public.is_admin(),'papel admin antigo não dispensa e-mail confirmado');
select pg_temp.assert_true((select count(*)=0 from public.profiles),'admin não confirmado não lê usuários');
select pg_temp.expect_confirmation_error($q$select public.assigned_vehicle(gen_random_uuid())$q$,'admin não confirmado não consulta veículo');

select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000004',true);
select pg_temp.expect_confirmation_error($q$select public.available_deliveries()$q$,'entregador aprovado continua exigindo e-mail');
reset role;
select set_config('request.jwt.claim.sub','',true);
update public.driver_profiles set status='pending' where id='20000000-0000-4000-8000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000004',true);
select pg_temp.expect_confirmation_error($q$select public.save_driver('12345678901','AB',current_date+365)$q$,'RPC definer de entregador exige confirmação');

select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000005',true);
select pg_temp.assert_true(not public.email_is_verified(),'vendedor CPF/CNPJ também confirma e-mail');
select pg_temp.assert_true((select count(*)=0 from public.profiles),'vendedor não confirmado não lê conta');

select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.email_is_verified(),'conta confirmada existente permanece confirmada');
select pg_temp.assert_true((select count(*)=1 from public.profiles),'perfil confirmado continua visível ao próprio usuário');
insert into public.addresses(label,postal_code,street,number,neighborhood,city,state) values('Trabalho','01001000','Praça da Sé','4','Sé','São Paulo','SP');
select pg_temp.assert_true((select count(*)=2 from public.addresses),'CRUD autorizado preservado após confirmação');
select public.complete_profile('Cliente Confirmado','11144477735','11988881234','1990-01-01','client',true);
select pg_temp.assert_true(public.track_delivery('MV-NAOEXISTE') is null,'busca vazia legítima continua retornando null');

-- Um serviço Auth atualiza o estado canônico. A aplicação não cria código fixo/flag duplicado.
reset role;
select set_config('request.jwt.claim.sub','',true);
update auth.users set email_confirmed_at=now() where id='20000000-0000-4000-8000-000000000001';
update auth.users set email_confirmed_at=now() where id='20000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.email_is_verified(),'confirmação de Auth libera a conta sem flag paralelo');
select pg_temp.assert_true((select count(*)=1 from public.addresses),'endereço pré-existente aparece após confirmar');
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(public.is_admin(),'admin confirmado preserva autorização administrativa');
select pg_temp.assert_true((public.admin_monthly_revenue(extract(year from current_date)::int)->>'basis')='confirmed_company_commission','relatório30/70 continua autorizado');

reset role;
select set_config('request.jwt.claim.sub','',true);
set local role service_role;
insert into public.notifications(user_id,title,body) values('20000000-0000-4000-8000-000000000004','Serviço de teste','Rotina interna preservada antes da confirmação do destinatário.');
select pg_temp.assert_true((select count(*)=1 from public.notifications where title='Serviço de teste'),'serviço com UID nulo pode notificar conta pendente');
reset role;
set local role anon;
select pg_temp.assert_true((select count(*)=11 from public.vehicle_categories where active),'catálogo público continua disponível');
select pg_temp.assert_true(not public.email_is_verified(),'visitante público não possui confirmação de conta');
reset role;
do $$begin raise notice 'PASS: confirmação canônica, RLS, RPCs, papéis, conta liberada, serviços internos e catálogo público.'; end$$;
rollback;
