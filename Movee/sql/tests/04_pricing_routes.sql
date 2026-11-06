-- Frete com combustível/pico e vínculo de rota confiável. Dados fictícios, rollback.
begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'ASSERT: %',msg; end if; end $$;
create function pg_temp.expect_error(command text,msg text) returns void language plpgsql as $$ begin begin execute command; exception when others then return; end; raise exception 'EXPECTED ERROR: %',msg; end $$;
create temp table pricing_fixture(key text primary key,value jsonb); grant all on pricing_fixture to authenticated;
insert into pricing_fixture values
('items','[{"description":"Caixa","quantity":1,"weight":1,"unit":"kg","length_cm":10,"width_cm":10,"height_cm":10}]'),
('address','{"postal_code":"01001000","street":"Rua Exemplo","number":"1","complement":"","neighborhood":"Centro","city":"São Paulo","state":"SP","reference":""}');
insert into pricing_fixture select 'off_schedule',to_jsonb((date_trunc('week',now() at time zone 'America/Sao_Paulo')+interval '1 week 12 hours') at time zone 'America/Sao_Paulo');
insert into pricing_fixture select 'peak_schedule',to_jsonb((date_trunc('week',now() at time zone 'America/Sao_Paulo')+interval '1 week 8 hours') at time zone 'America/Sao_Paulo');
insert into pricing_fixture select 'off',public.quote_delivery('motorcycle',(select value from pricing_fixture where key='items'),35,false,false,0,0,(select (value#>>'{}')::timestamptz from pricing_fixture where key='off_schedule'));
insert into pricing_fixture select 'peak',public.quote_delivery('motorcycle',(select value from pricing_fixture where key='items'),35,false,false,0,0,(select (value#>>'{}')::timestamptz from pricing_fixture where key='peak_schedule'));
select pg_temp.assert_true((select (value->'breakdown'->>'fuel')::numeric=6.20 and (value->'breakdown'->>'peak_applied')::boolean=false from pricing_fixture where key='off'),'combustível = km / rendimento * preço litro');
select pg_temp.assert_true((select (value->'breakdown'->>'peak_applied')::boolean from pricing_fixture where key='peak'),'pico segunda-feira 8h São Paulo');
select pg_temp.assert_true((select (p.value->>'price')::numeric=(o.value->>'price')::numeric+round((o.value->>'price')::numeric*.20,2) from pricing_fixture p cross join pricing_fixture o where p.key='peak' and o.key='off'),'pico aplica20% sobre subtotal final');
select pg_temp.assert_true((public.quote_delivery('bicycle',(select value from pricing_fixture where key='items'),35,false,false,0,0,(select (value#>>'{}')::timestamptz from pricing_fixture where key='off_schedule'))->'breakdown'->>'fuel')::numeric=0,'bicicleta não cobra combustível');
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values('40000000-0000-0000-0000-000000000001','route@movee.invalid',now(),'{"full_name":"Cliente Roteirizado","cpf_cnpj":"52998224725","phone":"11999991234","birth_date":"1990-01-01","requested_role":"client","terms":true}');
insert into storage.objects(bucket_id,name) values('movee-documents','40000000-0000-0000-0000-000000000001/identity.png');
insert into public.documents(user_id,kind,storage_path,mime_type,size_bytes) values('40000000-0000-0000-0000-000000000001','identity','40000000-0000-0000-0000-000000000001/identity.png','image/png',100);
insert into pricing_fixture select 'route',to_jsonb(public.store_route_quote('40000000-0000-0000-0000-000000000001','motorcycle',(select value from pricing_fixture where key='address'),(select value from pricing_fixture where key='address'),35,60,now()+interval '15 minutes'));
update public.system_settings set value=value||'{"route_required":true}' where key='pricing';
set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
select pg_temp.expect_error($q$select * from public.route_quotes$q$,'rotas confiáveis não são editáveis/lidas diretamente pelo usuário');
select pg_temp.expect_error($q$select public.store_route_quote(auth.uid(),'motorcycle',(select value from pricing_fixture where key='address'),(select value from pricing_fixture where key='address'),1,1,now()+interval '10 minutes')$q$,'usuário não pode inserir distância supostamente confiável');
select pg_temp.expect_error($q$select public.quote_delivery('motorcycle',(select value from pricing_fixture where key='items'),35,false,false,0,0)$q$,'rota obrigatória não pode ser omitida');
select pg_temp.expect_error($q$select public.quote_delivery('motorcycle',(select value from pricing_fixture where key='items'),1,false,false,0,0,null,(select (value#>>'{}')::uuid from pricing_fixture where key='route'))$q$,'distância não pode divergir da rota');
select pg_temp.assert_true((public.quote_delivery('motorcycle',(select value from pricing_fixture where key='items'),35,false,false,0,0,null,(select (value#>>'{}')::uuid from pricing_fixture where key='route'))->'breakdown'->>'distance_source')='provider_route','rota confiável identificada no detalhamento');
insert into pricing_fixture select 'payload',jsonb_build_object('category_id','motorcycle','items',(select value from pricing_fixture where key='items'),'distance_km',35,'pickup',(select value from pricing_fixture where key='address'),'destination',(select value from pricing_fixture where key='address'),'recipient_name','Pessoa Exemplo','recipient_phone','11999991234','scheduled_at',(select value#>>'{}' from pricing_fixture where key='off_schedule'),'urgent',false,'protection',false,'extras',0,'tolls',0,'route_id',(select value#>>'{}' from pricing_fixture where key='route'));
select pg_temp.expect_error($q$select public.create_delivery(jsonb_set((select value from pricing_fixture where key='payload'),'{pickup,number}','"999"'))$q$,'troca de endereço após rota deve ser rejeitada');
select pg_temp.assert_true((public.create_delivery((select value from pricing_fixture where key='payload'))).route_quote_id=(select (value#>>'{}')::uuid from pricing_fixture where key='route'),'entrega guarda rota validada e cotação automática');
reset role;
do $$ begin raise notice 'PASS: combustível, pico por fuso/dia, bicicleta sem combustível, rota confiável serviço/owner/km/endereços e preço integrado.'; end $$;
rollback;
