begin;
create table public.approval_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('driver','admin')),
 status text not null default 'pending' check(status in ('pending','in_review','approved','rejected','suspended')),
 justification text not null check(length(justification) between 10 and 2000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id,kind)
);
create table public.approval_history (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.approval_requests(id) on delete cascade,
 actor_id uuid references public.profiles(id) on delete set null,
 status text not null check(status in ('pending','in_review','approved','rejected','suspended')),
 reason text not null check(length(reason) between 3 and 2000), created_at timestamptz not null default now()
);
commit;
