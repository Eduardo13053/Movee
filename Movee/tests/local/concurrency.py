#!/usr/bin/env python3
"""PostgreSQL real: duas conexões disputam o 3º endereço e uma entrega.
Somente banco descartável de testes; dados fictícios fixos são removidos ao final.
PSQL_BIN e PGHOST/PGPORT/PGDATABASE/PGUSER configuram o cliente, sem senha impressa.
"""
import json, os, subprocess, time

PSQL=os.environ.get('PSQL_BIN','psql')
BASE=[PSQL,'-X','-v','ON_ERROR_STOP=1','-q','-t','-A']
CLIENT='30000000-0000-0000-0000-000000000001'
D1='30000000-0000-0000-0000-000000000002'; D2='30000000-0000-0000-0000-000000000003'
V1='30000000-0000-0000-0000-000000000011'; V2='30000000-0000-0000-0000-000000000012'
DELIVERY='30000000-0000-0000-0000-000000000021'

def run(sql):
 p=subprocess.run(BASE,input=sql,text=True,capture_output=True)
 if p.returncode: raise RuntimeError(p.stderr.strip())
 return p.stdout.strip()

def actor(uid):
 return f"set local role authenticated; select set_config('request.jwt.claim.sub','{uid}',true); select set_config('request.jwt.claims','{{\"sub\":\"{uid}\",\"role\":\"authenticated\"}}',true);"

def pair(sql1,sql2):
 # O primeiro conserva seu lock até o segundo estar concorrendo na mesma operação.
 p1=subprocess.Popen(BASE,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 p1.stdin.write(sql1);p1.stdin.close();p1.stdin=None
 time.sleep(.12)
 p2=subprocess.Popen(BASE,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 o2,e2=p2.communicate(sql2,timeout=15);o1,e1=p1.communicate(timeout=15)
 results=[{'ok':p1.returncode==0,'error':e1.strip()},{'ok':p2.returncode==0,'error':e2.strip()}]
 assert sum(x['ok'] for x in results)==1,results
 return results

cleanup=f"""
delete from public.delivery_events where delivery_id='{DELIVERY}';
delete from public.delivery_items where delivery_id='{DELIVERY}';
delete from public.deliveries where id='{DELIVERY}';
delete from public.outbox where payload->>'user_id' in ('{CLIENT}','{D1}','{D2}');
delete from storage.objects where name like '30000000-%';
delete from auth.users where id in ('{CLIENT}','{D1}','{D2}');
"""
try:
 run(cleanup)
 users=[]
 for uid,name,cpf,kind in [(CLIENT,'Cliente Concorrente','52998224725','client'),(D1,'Entregador Primeiro','11144477735','driver'),(D2,'Entregador Segundo','12345678909','driver')]:
  m=json.dumps({'full_name':name,'cpf_cnpj':cpf,'phone':'11999991234','birth_date':'1990-01-01','requested_role':kind,'terms':True})
  users.append(f"('{uid}','{uid}@movee.invalid',now(),'{m}')")
 run("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values"+','.join(users)+f""";
 update public.driver_profiles set cnh_number='12345678901',cnh_category='AB',cnh_expires_at=current_date+365,status='approved' where id in ('{D1}','{D2}');
 update public.profiles set role='driver' where id in ('{D1}','{D2}');
 insert into public.vehicles(id,driver_id,category_id,brand,model,plate,year) values ('{V1}','{D1}','motorcycle','Marca','Moto','ABC1D23',2025),('{V2}','{D2}','motorcycle','Marca','Moto','XYZ2E34',2025);
 insert into storage.objects(bucket_id,name) values ('movee-documents','{D1}/vehicle.png'),('movee-documents','{D2}/vehicle.png');
 insert into public.documents(user_id,vehicle_id,kind,storage_path,mime_type,size_bytes,status) values ('{D1}','{V1}','vehicle','{D1}/vehicle.png','image/png',100,'verified'),('{D2}','{V2}','vehicle','{D2}/vehicle.png','image/png',100,'verified');
 insert into public.addresses(user_id,label,postal_code,street,number,neighborhood,city,state) values ('{CLIENT}','Casa','01001000','Rua Exemplo','1','Centro','São Paulo','SP'),('{CLIENT}','Trabalho','01001000','Rua Exemplo','2','Centro','São Paulo','SP');
 insert into public.deliveries(id,client_id,category_id,status,pickup,destination,recipient_name,recipient_phone,distance_km,total_weight_kg,total_volume_m3,price,price_breakdown,scheduled_at) values('{DELIVERY}','{CLIENT}','motorcycle','awaiting_driver','{{"street":"Rua Exemplo","number":"1","neighborhood":"Centro","city":"São Paulo","state":"SP","postal_code":"01001000"}}','{{"street":"Rua Destino","number":"2","neighborhood":"Centro","city":"São Paulo","state":"SP","postal_code":"01001000"}}','Pessoa Exemplo','11999991234',10,1,.001,32.12,'{{}}',now()+interval '1 day');
 """)
 ins=lambda label:f"insert into public.addresses(label,postal_code,street,number,neighborhood,city,state) values('{label}','01001000','Rua Exemplo','3','Centro','São Paulo','SP');"
 addr=pair('begin;'+actor(CLIENT)+ins('Terceiro A')+'select pg_sleep(.6);commit;', 'begin;'+actor(CLIENT)+ins('Terceiro B')+'commit;')
 assert run(f"select count(*) from public.addresses where user_id='{CLIENT}'")=='3'
 jobs=pair('begin;'+actor(D1)+f"select public.accept_delivery('{DELIVERY}','{V1}');select pg_sleep(.6);commit;", 'begin;'+actor(D2)+f"select public.accept_delivery('{DELIVERY}','{V2}');commit;")
 assert run(f"select count(*) from public.deliveries where id='{DELIVERY}' and driver_id is not null and status='to_pickup'")=='1'
 print(json.dumps({'address_limit':{'passed':True,'successful_inserts':sum(x['ok'] for x in addr),'final_count':3},'delivery_claim':{'passed':True,'successful_claims':sum(x['ok'] for x in jobs),'assigned_count':1}},ensure_ascii=False))
finally:
 run(cleanup)
