begin;
create table public.vehicle_categories (
 id text primary key check(id ~ '^[a-z_]+$'), name text not null,
 max_weight_kg numeric(16,6) not null check(max_weight_kg>0), max_volume_m3 numeric(16,6) not null check(max_volume_m3>0),
 length_cm numeric not null check(length_cm>0), width_cm numeric not null check(width_cm>0), height_cm numeric not null check(height_cm>0),
 base_price numeric(12,2) not null check(base_price>=0), price_per_km numeric(12,2) not null check(price_per_km>=0),
 weight_price numeric(12,4) not null default 0 check(weight_price>=0), volume_price numeric(12,2) not null default 0 check(volume_price>=0),
 operational_fee numeric(12,2) not null default 0 check(operational_fee>=0), protection_fee numeric(12,2) not null default 0 check(protection_fee>=0),
 fuel_km_per_litre numeric(8,3) not null check((id='bicycle' and fuel_km_per_litre=0) or (id<>'bicycle' and fuel_km_per_litre>0 and fuel_km_per_litre<=100)),
 description text not null, protection text not null, image text not null, active boolean not null default true
);
-- Tarifas fictícias para TCC. Ajustar antes de operação comercial.
insert into public.vehicle_categories values
('bicycle','Bicicleta',5,.04,40,35,30,8,1.2,.15,2,0,2,0,'Documentos e pequenos volumes.','Bolsa de transporte','assets/img/bicycle.svg',true),
('motorcycle','Moto',20,.12,60,50,40,12,1.8,.12,3,2,3,35,'Agilidade para volumes leves.','Baú fechado','assets/img/motorcycle.svg',true),
('compact','Carro compacto',150,.6,100,80,75,20,2.2,.06,5,4,5,12,'Caixas e compras do dia a dia.','Compartimento fechado','assets/img/compact.svg',true),
('utility','Carro utilitário',300,1.5,150,100,100,30,2.8,.05,6,6,7,10,'Cargas urbanas compactas.','Compartimento fechado','assets/img/utility.svg',true),
('fiorino','Fiorino ou similar',650,3.1,180,130,130,40,3.2,.04,7,8,9,10,'Carga protegida para comércios.','Baú fechado','assets/img/fiorino.svg',true),
('small_van','Van pequena',1000,6,250,150,160,55,3.8,.035,8,10,12,8,'Mais espaço para sua operação.','Compartimento fechado','assets/img/small-van.svg',true),
('large_van','Van grande',1500,12,350,170,200,75,4.5,.03,9,15,15,7,'Volumes maiores com proteção.','Compartimento fechado','assets/img/large-van.svg',true),
('pickup','Caminhonete',1000,3,220,150,90,50,3.6,.04,6,10,10,8,'Materiais e cargas resistentes.','Cobertura opcional','assets/img/pickup.svg',true),
('small_truck','Caminhão pequeno',3000,20,420,200,220,110,5.5,.025,10,25,20,6,'Mudanças e carga fracionada.','Baú fechado','assets/img/small-truck.svg',true),
('medium_truck','Caminhão médio',8000,40,650,230,260,180,7,.02,12,40,30,4,'Capacidade para cargas comerciais.','Baú fechado','assets/img/medium-truck.svg',true),
('large_truck','Caminhão grande',14000,65,900,240,280,280,9,.015,14,60,45,3,'Grandes volumes planejados.','Baú fechado','assets/img/large-truck.svg',true);
commit;
