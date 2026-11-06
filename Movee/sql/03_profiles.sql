begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check(public.valid_full_name(full_name)),
 cpf_cnpj text not null unique check(cpf_cnpj ~ '^([0-9]{11}|[A-Z0-9]{12}[0-9]{2})$' and public.valid_tax_id(cpf_cnpj)),
 phone text not null check(public.valid_phone(phone)),
 birth_date date not null check(birth_date>=current_date-interval '120 years' and birth_date<=current_date-interval '18 years'),
 role text not null default 'client' check(role in ('client','driver','admin')),
 requested_role text not null default 'client' check(requested_role in ('client','seller','driver','admin')),
 check(requested_role='seller' or (cpf_cnpj ~ '^[0-9]{11}$' and public.valid_cpf(cpf_cnpj))),
 terms_accepted_at timestamptz not null, verification_channel text not null default 'email' check(verification_channel in ('email','sms')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create function private.is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;
create function public.is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as $$ select private.is_admin() $$;
-- Cliente não duplica dados pessoais: é um perfil com role=client.
commit;
