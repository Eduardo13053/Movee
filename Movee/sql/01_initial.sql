-- Movee: execute 01..20 uma vez em projeto Supabase NOVO. Não usa banco anterior.
begin;
create extension if not exists pgcrypto;
-- Fechar permissões padrão antes de criar funções/tabelas durante a instalação.
alter default privileges in schema public revoke all on tables from anon,authenticated;
alter default privileges in schema public revoke execute on functions from public;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table public.system_settings (
 key text primary key, value jsonb not null, updated_at timestamptz not null default now()
);
insert into public.system_settings values
 ('pricing','{"urgent_multiplier":1.25,"extra_service_fee":15,"max_extra_services":5,"tolls_enabled":false,"max_distance_km":1000,"route_required":false,"fuel_price_per_litre":6.20,"peak_multiplier":1.20,"peak_hours":[[7,9],[17,20]],"peak_weekdays":[1,2,3,4,5],"timezone":"America/Sao_Paulo"}'::jsonb,now()),
 ('retention','{"document_days_after_account_closure":180,"purpose":"Verificação de identidade e elegibilidade para transporte; acesso restrito."}'::jsonb,now());
commit;
