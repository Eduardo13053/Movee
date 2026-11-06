begin;
create table public.addresses (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
 label text not null check(length(label) between 2 and 40), postal_code text not null check(postal_code ~ '^\d{8}$'),
 street text not null check(length(street) between 2 and 200), number text not null check(length(number) between 1 and 30),
 complement text not null default '' check(length(complement)<=100), neighborhood text not null check(length(neighborhood) between 2 and 100),
 city text not null check(length(city) between 2 and 100), state text not null check(state ~ '^(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)$'),
 reference text not null default '' check(length(reference)<=250), is_default boolean not null default false,
 created_at timestamptz not null default now()
);
commit;
