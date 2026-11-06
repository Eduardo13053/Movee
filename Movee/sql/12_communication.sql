begin;
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null, read_at timestamptz, created_at timestamptz not null default now()
);
create table public.outbox (
 id uuid primary key default gen_random_uuid(), event text not null, payload jsonb not null,
 status text not null default 'pending' check(status in ('pending','processing','sent','failed')),
 attempts int not null default 0, locked_at timestamptz, last_error text, available_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table public.audit_logs (
 id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id) on delete set null,
 action text not null, entity text not null, entity_id text, details jsonb not null default '{}', created_at timestamptz not null default now()
);
create table public.reviews (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null unique references public.deliveries(id), client_id uuid not null default auth.uid() references public.profiles(id), driver_id uuid not null references public.driver_profiles(id),
 rating int not null check(rating between 1 and 5), comment text not null default '' check(length(comment)<=1000), created_at timestamptz not null default now()
);
create table public.delivery_proofs (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null unique references public.deliveries(id), driver_id uuid not null references public.driver_profiles(id),
 recipient_name text not null check(length(recipient_name) between 3 and 160), notes text not null default '', created_at timestamptz not null default now()
);
create table public.support_tickets (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references public.profiles(id), delivery_id uuid references public.deliveries(id),
 subject text not null check(length(subject) between 5 and 150), message text not null check(length(message) between 10 and 4000),
 status text not null default 'open' check(status in ('open','in_progress','closed')), admin_reply text not null default '' check(length(admin_reply)<=4000), created_at timestamptz not null default now()
);
create function private.notify(p_user uuid,p_title text,p_body text,p_event text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.notifications(user_id,title,body) values(p_user,p_title,p_body);
 insert into public.outbox(event,payload) values(p_event,jsonb_build_object('user_id',p_user,'title',p_title,'body',p_body));
end $$;
commit;
