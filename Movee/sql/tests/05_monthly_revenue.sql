-- SOMENTE em projeto descartável de testes, após SQL 01..19.
-- Fixtures financeiras e datas artificiais; nenhuma chamada de pagamento real.
-- O trigger de datas é desabilitado por instantes apenas para construir o histórico de teste.
-- Toda alteração é revertida por ROLLBACK.
begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end$$;
create function pg_temp.expect_error(command text,msg text) returns void language plpgsql as $$begin begin execute command; exception when others then return; end; raise exception 'EXPECTED ERROR: %',msg; end$$;
grant execute on function pg_temp.expect_error(text,text),pg_temp.assert_true(boolean,text) to anon,authenticated;
create temp table revenue_fixture(key text primary key,id uuid);
grant all on revenue_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('73000000-0000-4000-8000-000000000001','revenue-client@movee.invalid',now(),'{"full_name":"Cliente Receita","cpf_cnpj":"52998224725","phone":"11987654321","birth_date":"1990-01-01","requested_role":"client","terms":true}'),
('73000000-0000-4000-8000-000000000002','revenue-admin@movee.invalid',now(),'{"full_name":"Admin Receita","cpf_cnpj":"11144477735","phone":"11987654321","birth_date":"1990-01-01","requested_role":"admin","terms":true}');
update public.profiles set role='admin' where id='73000000-0000-4000-8000-000000000002';
create function pg_temp.revenue_delivery(p_key text) returns uuid language plpgsql as $$
declare result uuid; addr jsonb:='{"street":"Rua de Teste","number":"10","neighborhood":"Centro","city":"São Paulo","state":"SP","postal_code":"01001000"}';
begin
 insert into public.deliveries(client_id,category_id,pickup,destination,recipient_name,recipient_phone,distance_km,total_weight_kg,total_volume_m3,price,price_breakdown,scheduled_at)
 values('73000000-0000-4000-8000-000000000001','bicycle',addr,addr,'Pessoa Recebedora','11987654321',1,1,.001,10,'{}',now()+interval '1 day') returning id into result;
 insert into revenue_fixture values(p_key,result); return result;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000002',true);
select public.update_pricing_settings('{"commission_percent":30}');
reset role;
select pg_temp.revenue_delivery('january');
select pg_temp.assert_true((select commission_percent=30 and commission_amount=3 and price-commission_amount=7 from public.deliveries where id=(select id from revenue_fixture where key='january')),'R$10 gera R$3 empresa e R$7 entregador');
set local role authenticated;
select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000002',true);
select public.update_pricing_settings('{"commission_percent":25}');
reset role;
select pg_temp.revenue_delivery('february');
select pg_temp.assert_true((select commission_percent=30 and commission_amount=3 from public.deliveries where id=(select id from revenue_fixture where key='january')),'nova taxa não muda entrega anterior');
select pg_temp.assert_true((select commission_percent=25 and commission_amount=2.50 from public.deliveries where id=(select id from revenue_fixture where key='february')),'nova entrega captura taxa alterada');
select pg_temp.expect_error($q$update public.deliveries set commission_amount=1 where id=(select id from revenue_fixture where key='january')$q$,'snapshot de comissão imutável');
-- Confirmação de pagamento copia o snapshot da entrega, mesmo que a taxa atual seja outra.
insert into public.payments(delivery_id,user_id,method,status,amount,is_demo,provider,provider_reference)
select id,'73000000-0000-4000-8000-000000000001','pix','confirmed',10,false,'mercadopago','REVTEST-JAN' from revenue_fixture where key='january';
select pg_temp.assert_true((select commission_percent=30 and commission_amount=3 and confirmed_at is not null and not confirmation_time_estimated from public.payments where provider_reference='REVTEST-JAN'),'pagamento copia comissão original e registra confirmação');
select pg_temp.expect_error($q$update public.payments set confirmed_at=confirmed_at+interval '1 day' where provider_reference='REVTEST-JAN'$q$,'data de confirmação imutável');
select pg_temp.expect_error($q$update public.payments set commission_amount=1 where provider_reference='REVTEST-JAN'$q$,'comissão financeira imutável');
select pg_temp.revenue_delivery('demo');
select pg_temp.revenue_delivery('pending');
select pg_temp.revenue_delivery('failed');
select pg_temp.revenue_delivery('refunded');
select pg_temp.revenue_delivery('legacy');
-- Fixture histórica: não se presume a taxa de uma entrega anterior à implantação.
alter table public.deliveries disable trigger delivery_commission_snapshot;
update public.deliveries set commission_percent=null,commission_amount=null where id=(select id from revenue_fixture where key='legacy');
alter table public.deliveries enable trigger delivery_commission_snapshot;
alter table public.payments disable trigger payment_financial_snapshot;
update public.payments set confirmed_at='2050-02-01T02:59:59Z',confirmation_time_estimated=false where provider_reference='REVTEST-JAN';
insert into public.payments(delivery_id,user_id,method,status,amount,is_demo,provider,provider_reference,confirmed_at,commission_percent,commission_amount,confirmation_time_estimated)
select f.id,'73000000-0000-4000-8000-000000000001','pix',case f.key when 'pending' then 'pending' when 'failed' then 'failed' when 'refunded' then 'refunded' else 'confirmed' end,10,f.key='demo',case when f.key='demo' then 'demo' else 'mercadopago' end,'REVTEST-'||f.key,
case f.key when 'february' then '2050-02-01T03:00:00Z'::timestamptz when 'legacy' then '2050-04-01T12:00:00Z'::timestamptz when 'pending' then null when 'failed' then null else '2050-03-01T12:00:00Z'::timestamptz end,
case when f.key in ('pending','failed','legacy') then null else 25 end,
case when f.key in ('pending','failed','legacy') then null else 2.50 end,
f.key='legacy'
from revenue_fixture f where f.key<>'january';
alter table public.payments enable trigger payment_financial_snapshot;
set local role authenticated;
select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000002',true);
create temp table revenue_result as select public.admin_monthly_revenue(2050) r;
select pg_temp.assert_true((select jsonb_array_length(r->'months')=12 from revenue_result),'12 meses, inclusive meses vazios');
select pg_temp.assert_true((select r->>'basis'='confirmed_company_commission' and r->>'timezone'='America/Sao_Paulo' from revenue_result),'receita de comissão e fuso operacional explícitos');
select pg_temp.assert_true((select (r->>'total_gross_amount')::numeric=30 and (r->>'total_commission_amount')::numeric=5.50 and (r->>'total_driver_amount')::numeric=14.50 from revenue_result),'totais reais excluem simulações, falhas, pendentes e estornos');
select pg_temp.assert_true((select (r->>'total_payment_count')::int=3 and (r->>'total_commission_payment_count')::int=2 and (r->>'unconfigured_payment_count')::int=1 from revenue_result),'comissão histórica desconhecida é sinalizada');
select pg_temp.assert_true((select (r->>'demo_excluded_count')::int=1 and (r->>'refunded_excluded_count')::int=1 and (r->>'legacy_confirmation_count')::int=1 from revenue_result),'exclusões e datas históricas estimadas identificadas');
select pg_temp.assert_true((select (r->'months'->0->>'gross_amount')::numeric=10 and (r->'months'->0->>'commission_amount')::numeric=3 and (r->'months'->0->>'driver_amount')::numeric=7 from revenue_result),'02h59UTC pertence a janeiro em São Paulo');
select pg_temp.assert_true((select (r->'months'->1->>'gross_amount')::numeric=10 and (r->'months'->1->>'commission_amount')::numeric=2.50 from revenue_result),'03hUTC inicia fevereiro em São Paulo');
select pg_temp.assert_true((select (r->'months'->2->>'gross_amount')::numeric=0 and (r->'months'->11->>'commission_amount')::numeric=0 from revenue_result),'meses sem receita ficam zerados');
select pg_temp.assert_true((public.admin_monthly_revenue(2051)->>'total_commission_amount')::numeric=0 and jsonb_array_length(public.admin_monthly_revenue(2051)->'months')=12,'ano inteiro sem pagamentos retorna12 meses e zero');
select pg_temp.expect_error($q$select public.admin_monthly_revenue(1999)$q$,'ano abaixo do mínimo');
select pg_temp.expect_error($q$select public.admin_monthly_revenue(2101)$q$,'ano acima do máximo');
select pg_temp.expect_error($q$select public.update_pricing_settings('{"commission_percent":101}')$q$,'comissão acima de 100%');
select set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000001',true);
select pg_temp.expect_error($q$select public.admin_monthly_revenue(2050)$q$,'cliente não acessa relatório financeiro');
select pg_temp.expect_error($q$select public.update_pricing_settings('{"commission_percent":30}')$q$,'cliente não altera comissão');
reset role;
set local role anon;
select pg_temp.expect_error($q$select public.admin_monthly_revenue(2050)$q$,'anônimo não acessa relatório financeiro');
reset role;
do $$begin raise notice 'PASS: receita mensal30/70, snapshots, confirmação imutável, meses/SP, exclusões, legado, ano e permissões.'; end$$;
rollback;
