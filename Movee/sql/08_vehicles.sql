begin;
create table public.vehicles (
 id uuid primary key default gen_random_uuid(), driver_id uuid not null default auth.uid() references public.driver_profiles(id) on delete cascade,
 category_id text not null references public.vehicle_categories(id), brand text not null check(length(brand) between 2 and 80), model text not null check(length(model) between 2 and 80),
 plate text unique check(plate ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'), year int not null check(year between 1980 and extract(year from current_date)::int+1),
 active boolean not null default true, created_at timestamptz not null default now(),
 check(category_id='bicycle' or plate is not null)
);
commit;
