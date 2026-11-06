begin;
create table public.documents (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
 vehicle_id uuid references public.vehicles(id) on delete cascade, kind text not null check(kind in ('identity','cnh','vehicle')),
 storage_path text not null unique check(length(storage_path)<300 and storage_path !~ '\.\.'),
 mime_type text not null check(mime_type in ('image/jpeg','image/png','application/pdf')), size_bytes int not null check(size_bytes between 100 and 5242880),
 status text not null default 'pending' check(status in ('pending','verified','rejected')), created_at timestamptz not null default now(),
 check((kind='vehicle')=(vehicle_id is not null))
);
commit;
