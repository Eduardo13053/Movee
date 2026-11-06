-- Teste de integração transacional. Executar como postgres no SQL Editor APENAS em projeto de teste.
-- Insere usuários/objetos fictícios por SQL (não envia e-mails e não testa Auth real/Storage físico).
-- Todos os dados são descartados por ROLLBACK. UUIDs fixos não devem existir previamente.
begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
create function pg_temp.expect_error(command text,msg text) returns void language plpgsql as $$ begin begin execute command; exception when others then return; end; raise exception 'EXPECTED ERROR: %',msg; end $$;
create temp table test_ids(key text primary key,id uuid); grant all on test_ids to authenticated,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('10000000-0000-0000-0000-000000000001','client@movee.invalid',now(),'{"full_name":"Cliente Exemplo","cpf_cnpj":"52998224725","phone":"11999991234","birth_date":"1990-01-01","requested_role":"client","terms":true}'),
('10000000-0000-0000-0000-000000000002','driver@movee.invalid',now(),'{"full_name":"Entregador Exemplo","cpf_cnpj":"11144477735","phone":"11988881234","birth_date":"1990-01-01","requested_role":"driver","terms":true}'),
('10000000-0000-0000-0000-000000000003','admin@movee.invalid',now(),'{"full_name":"Admin Exemplo","cpf_cnpj":"12345678909","phone":"11977771234","birth_date":"1990-01-01","requested_role":"admin","terms":true}'),
('10000000-0000-0000-0000-000000000004','seller@movee.invalid',now(),'{"full_name":"Loja Exemplo","cpf_cnpj":"11222333000181","phone":"11966661234","birth_date":"1990-01-01","requested_role":"seller","terms":true}');
select pg_temp.assert_true((select count(*)=4 from public.profiles where id::text like '10000000%'),'perfis criados pelo trigger');
select pg_temp.assert_true((select bool_and(role='client') from public.profiles where id::text like '10000000%'),'metadata não concede papel admin/driver');
-- Metadados simulados de Storage para exercitar o vínculo de documento (sem upload físico).
insert into storage.objects(bucket_id,name) select 'movee-documents',id::text||'/identity.png' from public.profiles where id::text like '10000000%';
insert into public.documents(user_id,kind,storage_path,mime_type,size_bytes) select id,'identity',id::text||'/identity.png','image/png',100 from public.profiles where id::text like '10000000%';
select public.bootstrap_admin('10000000-0000-0000-0000-000000000003');
select pg_temp.expect_error($q$select public.bootstrap_admin('10000000-0000-0000-0000-000000000001')$q$,'bootstrap deve ocorrer uma única vez');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.assert_true((select count(*)=1 from public.profiles),'RLS perfis isola cliente');
select pg_temp.expect_error($q$update public.profiles set role='admin' where id=auth.uid()$q$,'cliente não pode promover papel');
select pg_temp.expect_error($q$select public.record_demo_payment(gen_random_uuid(),'pix')$q$,'pagamento de serviço não disponível a cliente');
select pg_temp.expect_error($q$select public.bootstrap_admin(auth.uid())$q$,'bootstrap de serviço não disponível a cliente');
insert into public.addresses(label,postal_code,street,number,neighborhood,city,state,is_default) values
('Casa','01001000','Praça da Sé','1','Sé','São Paulo','SP',true),('Trabalho','01001000','Praça da Sé','2','Sé','São Paulo','SP',false),('Faculdade','01001000','Praça da Sé','3','Sé','São Paulo','SP',false);
select pg_temp.expect_error($q$insert into public.addresses(label,postal_code,street,number,neighborhood,city,state) values('Quarto','01001000','Praça da Sé','4','Sé','São Paulo','SP')$q$,'limite três endereços');
update public.addresses set is_default=true where label='Trabalho';
select pg_temp.assert_true((select count(*)=1 from public.addresses where is_default),'somente um endereço principal');
select pg_temp.expect_error($q$select public.quote_delivery('bicycle','[{"description":"Caixas","quantity":1,"weight":50,"unit":"kg","length_cm":20,"width_cm":20,"height_cm":20}]',10,false,false,0,0)$q$,'peso incompatível');
select pg_temp.expect_error($q$select public.quote_delivery('bicycle','[{"description":"Caixas","quantity":1,"weight":-1,"unit":"kg","length_cm":20,"width_cm":20,"height_cm":20}]',10,false,false,0,0)$q$,'peso negativo');
select pg_temp.expect_error($q$select public.quote_delivery('bicycle',null,10,false,false,0,0)$q$,'mercadorias nulas');
select pg_temp.assert_true((public.quote_delivery('motorcycle','[{"description":"Caixa","quantity":2,"weight":1000,"unit":"g","length_cm":10,"width_cm":10,"height_cm":10}]',10,false,false,0,0)->>'total_weight_kg')::numeric=2,'peso unitário multiplicado pela quantidade');
insert into test_ids select 'delivery',(public.create_delivery(jsonb_build_object('category_id','motorcycle','items','[{"description":"Caixa","quantity":1,"weight":1000,"unit":"g","length_cm":10,"width_cm":10,"height_cm":10}]'::jsonb,'distance_km',10,'pickup','{"street":"Rua da Coleta","number":"10","neighborhood":"Centro","city":"São Paulo","state":"SP","postal_code":"01001000"}'::jsonb,'destination','{"street":"Rua da Entrega","number":"20","neighborhood":"Centro","city":"São Paulo","state":"SP","postal_code":"01002000"}'::jsonb,'recipient_name','Pessoa Exemplo','recipient_phone','11999991234','scheduled_at',now()+interval '1 day','urgent',false,'protection',false,'extras',0,'tolls',0))).id;
select pg_temp.assert_true((select status='awaiting_payment' from public.deliveries where id=(select id from test_ids where key='delivery')),'entrega aguarda pagamento');
-- Entregador preenche cadastro e veículo.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true((select count(*)=0 from public.deliveries),'entregador não designado não lê dados privados');
select pg_temp.assert_true((select count(*)=0 from public.addresses),'endereços isolados');
select public.save_driver('12345678901','AB',current_date+365);
insert into public.vehicles(category_id,brand,model,plate,year) values('motorcycle','Marca','Moto','ABC1D23',2025) returning id;
insert into test_ids select 'vehicle',id from public.vehicles limit 1;
reset role;
insert into storage.objects(bucket_id,name) values('movee-documents','10000000-0000-0000-0000-000000000002/cnh.png'),('movee-documents','10000000-0000-0000-0000-000000000002/vehicle.png');
insert into public.documents(user_id,kind,storage_path,mime_type,size_bytes) values('10000000-0000-0000-0000-000000000002','cnh','10000000-0000-0000-0000-000000000002/cnh.png','image/png',100);
insert into public.documents(user_id,vehicle_id,kind,storage_path,mime_type,size_bytes) select '10000000-0000-0000-0000-000000000002',id,'vehicle','10000000-0000-0000-0000-000000000002/vehicle.png','image/png',100 from test_ids where key='vehicle';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
insert into test_ids select 'approval',(public.submit_approval('driver','Quero atuar como entregador profissional.')).id;
select pg_temp.expect_error($q$select public.available_deliveries()$q$,'entregador pendente não consulta ofertas');
-- Administrador verifica documentos e aprova.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select pg_temp.expect_error($q$select public.review_account((select id from test_ids where key='approval'),'approved','Dados conferidos')$q$,'aprovação exige revisão de documentos');
select public.review_document(id,'verified','Documento conferido no teste') from public.documents where user_id='10000000-0000-0000-0000-000000000002';
select public.review_account((select id from test_ids where key='approval'),'approved','Dados conferidos');
select pg_temp.assert_true((public.admin_report()->>'pending_approvals')::int=0,'relatório administrativo');
-- Serviço registra pagamento demonstrativo com preço recalculado, sem cartão.
reset role;
set local role service_role;
select public.record_demo_payment((select id from test_ids where key='delivery'),'pix');
select public.record_demo_payment((select id from test_ids where key='delivery'),'pix');
select pg_temp.assert_true((select count(*)=1 from public.payments where delivery_id=(select id from test_ids where key='delivery')),'pagamento idempotente');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(jsonb_array_length(public.available_deliveries())=1,'oferta aprovada disponível');
select public.accept_delivery((select id from test_ids where key='delivery'),(select id from test_ids where key='vehicle'));
select pg_temp.expect_error($q$select public.accept_delivery((select id from test_ids where key='delivery'),(select id from test_ids where key='vehicle'))$q$,'entrega não aceita duas vezes');
select pg_temp.expect_error($q$select public.advance_delivery((select id from test_ids where key='delivery'),'delivered','Pular coleta','Recebedor Exemplo',(select id from test_ids where key='vehicle'))$q$,'não pula etapas');
select pg_temp.expect_error($q$select public.advance_delivery((select id from test_ids where key='delivery'),'collected','Coleta antes da conferência',null,(select id from test_ids where key='vehicle'))$q$,'coleta exige conferência física pelo cliente');
select pg_temp.expect_error($q$select public.advance_delivery((select id from test_ids where key='delivery'),'collected','Veículo diferente',null,'00000000-0000-0000-0000-000000000000')$q$,'exige veículo exato designado');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select public.confirm_pickup_vehicle((select id from test_ids where key='delivery'),false,'Modelo e placa divergentes');
select pg_temp.assert_true((select count(*)=1 from public.support_tickets where delivery_id=(select id from test_ids where key='delivery')),'divergência abre incidente');
select public.confirm_pickup_vehicle((select id from test_ids where key='delivery'),true,'Modelo e placa conferidos');
select pg_temp.assert_true((public.assigned_vehicle((select id from test_ids where key='delivery'))->>'plate')='ABC1D23','cliente consulta veículo designado');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select pg_temp.expect_error($q$update public.vehicles set active=false where id=(select id from test_ids where key='vehicle')$q$,'veículo não pode desativar durante entrega');
select public.advance_delivery((select id from test_ids where key='delivery'),'collected','Coleta registrada',null,(select id from test_ids where key='vehicle'));
select public.advance_delivery((select id from test_ids where key='delivery'),'in_transit','Em transporte',null,(select id from test_ids where key='vehicle'));
select public.advance_delivery((select id from test_ids where key='delivery'),'near_destination','Próximo ao destino',null,(select id from test_ids where key='vehicle'));
select pg_temp.expect_error($q$select public.advance_delivery((select id from test_ids where key='delivery'),'delivered','Sem recebedor',null,(select id from test_ids where key='vehicle'))$q$,'comprovante exige recebedor');
select public.advance_delivery((select id from test_ids where key='delivery'),'delivered','Entrega concluída','Pessoa Recebedora',(select id from test_ids where key='vehicle'));
select pg_temp.assert_true((select count(*)=1 from public.delivery_proofs where delivery_id=(select id from test_ids where key='delivery')),'comprovante criado');
-- Cliente acompanha e avalia entrega concluída.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select pg_temp.assert_true((public.track_delivery((select code from public.deliveries where id=(select id from test_ids where key='delivery')))->'delivery'->>'status')='delivered','rastreamento com histórico');
insert into public.reviews(delivery_id,driver_id,rating,comment) select id,'10000000-0000-0000-0000-000000000002',5,'Tudo certo no teste.' from test_ids where key='delivery';
select pg_temp.assert_true((select count(*)>0 from public.notifications),'notificações registradas');
select pg_temp.assert_true(public.track_delivery('MV-INEXISTENTE') is null,'busca ausente é vazia');
reset role;
select pg_temp.assert_true((select count(*)>0 from public.audit_logs),'auditoria administrativa registrada');
select pg_temp.assert_true((select count(*)>0 from public.outbox),'e-mails enfileirados');
do $$ begin raise notice 'PASS: cadastro, RLS, bootstrap, endereços, cotação, documentos, aprovação, pagamento, aceite, etapas, comprovante, avaliação, rastreamento, notificações e auditoria.'; end $$;
rollback;
