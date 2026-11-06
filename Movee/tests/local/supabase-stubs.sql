-- APENAS PostgreSQL LOCAL de testes vazio. NUNCA executar no Supabase.
do $$begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; end$$;
do $$begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end$$;
do $$begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if; end$$;
create schema auth;
create table auth.users(id uuid primary key,email text,phone text,email_confirmed_at timestamptz,phone_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid(),auth.role() to anon,authenticated,service_role;
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner_id text,metadata jsonb default '{}',unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert,update,delete on storage.objects to authenticated,service_role;
grant all on storage.buckets to service_role;
create function storage.foldername(name text) returns text[] language sql immutable as $$select (string_to_array(name,'/'))[1:greatest(array_length(string_to_array(name,'/'),1)-1,0)]$$;
grant execute on function storage.foldername(text) to anon,authenticated,service_role;
