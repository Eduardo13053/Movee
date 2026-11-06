begin;
create table public.driver_profiles (
 id uuid primary key references public.profiles(id) on delete cascade,
 cnh_number text check(cnh_number ~ '^\d{11}$'),
 cnh_category text check(cnh_category in ('A','B','AB','C','AC','D','AD','E','AE')),
 cnh_expires_at date check(cnh_expires_at<=current_date+3653),
 status text not null default 'pending' check(status in ('pending','in_review','approved','rejected','suspended')),
 created_at timestamptz not null default now()
);
commit;
