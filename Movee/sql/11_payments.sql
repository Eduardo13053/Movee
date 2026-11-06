begin;
create table public.payments (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null unique references public.deliveries(id), user_id uuid not null references public.profiles(id),
 method text not null check(method in ('pix','credit','debit')), status text not null default 'pending' check(status in ('pending','confirmed','failed','refunded')),
 amount numeric(14,2) not null check(amount>=0), is_demo boolean not null default true, provider_reference text unique,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
commit;
