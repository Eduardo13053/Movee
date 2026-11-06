begin;
create table public.route_quotes (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id), category_id text not null references public.vehicle_categories(id),
 pickup jsonb not null check(public.valid_address(pickup)), destination jsonb not null check(public.valid_address(destination)),
 distance_km numeric(12,3) not null check(distance_km>0 and distance_km<=10000), duration_minutes numeric(12,3) not null check(duration_minutes>0 and duration_minutes<=14400),
 expires_at timestamptz not null, created_at timestamptz not null default now()
);
create table public.deliveries (
 id uuid primary key default gen_random_uuid(), code text not null unique default ('MV-'||upper(encode(gen_random_bytes(6),'hex'))),
 client_id uuid not null references public.profiles(id), driver_id uuid references public.driver_profiles(id), vehicle_id uuid references public.vehicles(id), category_id text not null references public.vehicle_categories(id),
 status text not null default 'awaiting_payment' check(status in ('awaiting_payment','awaiting_driver','to_pickup','collected','in_transit','near_destination','delivered','cancelled')),
 pickup jsonb not null check(public.valid_address(pickup)), destination jsonb not null check(public.valid_address(destination)),
 recipient_name text not null check(length(recipient_name) between 3 and 160), recipient_phone text not null check(public.valid_phone(recipient_phone)),
 distance_km numeric(12,3) not null check(distance_km>0), total_weight_kg numeric(20,6) not null check(total_weight_kg>0), total_volume_m3 numeric(20,9) not null check(total_volume_m3>0),
 price numeric(14,2) not null check(price>=0), price_breakdown jsonb not null,
 scheduled_at timestamptz not null, notes text not null default '' check(length(notes)<=2000), special_instructions text not null default '' check(length(special_instructions)<=2000),
 urgent boolean not null default false, protection boolean not null default false, extras numeric not null default 0 check(extras between 0 and 5 and extras=trunc(extras)), tolls numeric not null default 0 check(tolls>=0),
 route_quote_id uuid references public.route_quotes(id),
 vehicle_confirmed_at timestamptz, vehicle_confirmed_by uuid references public.profiles(id),
 eta_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((driver_id is null)=(vehicle_id is null))
);
create table public.delivery_items (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null references public.deliveries(id) on delete cascade,
 description text not null check(length(description) between 2 and 500), quantity int not null check(quantity between 1 and 10000),
 unit_weight_kg numeric(20,6) not null check(unit_weight_kg>0), length_cm numeric not null check(length_cm>0), width_cm numeric not null check(width_cm>0), height_cm numeric not null check(height_cm>0)
);
create table public.delivery_events (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null references public.deliveries(id) on delete cascade,
 status text not null, note text not null default '' check(length(note)<=2000), created_at timestamptz not null default now()
);
commit;
