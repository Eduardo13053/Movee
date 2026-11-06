"""Browser interaction checks using intercepted API responses, NOT live Supabase tests.
Requires: pip install playwright; playwright install chromium (or system chromium).
Run with PHP serving public at http://127.0.0.1:8080.
"""
from playwright.sync_api import sync_playwright
import json, os
from datetime import datetime, timezone, timedelta
BASE=os.environ.get('MOVEE_TEST_URL','http://127.0.0.1:8080')
USER='11111111-1111-4111-8111-111111111111'; DELIVERY='22222222-2222-4222-8222-222222222222'
CAT={'id':'compact','name':'Carro compacto','max_weight_kg':150,'max_volume_m3':.6,'length_cm':100,'width_cm':80,'height_cm':75,'base_price':20,'price_per_km':2.2,'weight_price':.06,'volume_price':5,'operational_fee':4,'protection_fee':5,'description':'Caixas e compras.','protection':'Compartimento fechado','image':'assets/img/compact.svg','active':True}
ADDRESS={'id':'33333333-3333-4333-8333-333333333333','label':'Casa','postal_code':'01001000','street':'Praça da Sé','number':'100','complement':'','neighborhood':'Sé','city':'São Paulo','state':'SP','reference':'','is_default':True}
NOW=datetime.now(timezone.utc).isoformat()
D={'id':DELIVERY,'code':'MV-0123456789AB','client_id':USER,'driver_id':None,'category_id':'compact','status':'awaiting_driver','pickup':ADDRESS,'destination':ADDRESS,'recipient_name':'Maria Silva','recipient_phone':'11999999999','distance_km':10,'total_weight_kg':1,'total_volume_m3':.001,'price':42.06,'created_at':NOW,'scheduled_at':NOW}
class Mock:
 def __init__(self):self.role='client';self.calls=[];self.route_enabled=False;self.delivery_status='awaiting_driver';self.confirmed=False
 def route(self,route):
  v=route.request.post_data_json; self.calls.append(v); a=v['action']; role=self.role
  profile={'id':USER,'full_name':'João da Silva','cpf_cnpj':'52998224725','phone':'11999999999','birth_date':'1995-05-01','role':role,'requested_role':role,'terms_accepted_at':NOW}
  data=None
  if a=='session':data={'user':{'id':USER,'email':'joao@example.test'},'profile':profile,'csrf':'mock-token','configured':True,'payment_mode':'demo','sms_enabled':False,'route_enabled':self.route_enabled}
  elif a=='data':
   datasets={'vehicle_categories':[CAT],'addresses':[ADDRESS],'profiles':[profile],'deliveries':[{**D,'status':self.delivery_status,'driver_id':USER if self.delivery_status=='to_pickup' else None,'vehicle_id':'44444444-4444-4444-8444-444444444444' if self.delivery_status=='to_pickup' else None,'vehicle_confirmed_at':NOW if self.confirmed else None}],'vehicles':[{'id':'44444444-4444-4444-8444-444444444444','driver_id':USER,'category_id':'compact','brand':'Fiat','model':'Uno','plate':'ABC1D23','year':2020,'active':True}],'driver_profiles':[{'id':USER,'status':'approved','cnh_number':'12345678901','cnh_category':'B','cnh_expires_at':'2030-01-01'}],'notifications':[{'id':'55555555-5555-4555-8555-555555555555','title':'Cadastro concluído','body':'Seja bem-vindo.','read_at':None,'created_at':NOW}],'documents':[],'approval_requests':[],'support_tickets':[],'payments':[],'reviews':[]}
   data=datasets.get(v['table'],[]) if v['op']=='list' else [v.get('data',{})]
  elif a=='rpc':
   if v['name']=='available_deliveries':data=[{**D,'pickup_city':'São Paulo','destination_city':'Santo André'}]
   elif v['name']=='quote_delivery':data={'price':42.06,'breakdown':{'base':20,'distance':22,'weight':.06,'total':42.06},'total_weight_kg':1,'total_volume_m3':.001}
   elif v['name']=='create_delivery':data={**D,'status':'awaiting_payment'}
   elif v['name']=='assigned_vehicle':data={'id':'44444444-4444-4444-8444-444444444444','brand':'Fiat','model':'Uno','plate':'ABC1D23','category_id':'compact'}
   elif v['name']=='confirm_pickup_vehicle':self.confirmed=v['args']['p_matches'];data={}
   elif v['name']=='advance_delivery':
    assert v['args']['p_vehicle_id']=='44444444-4444-4444-8444-444444444444';data={}
   else:data={}
  elif a=='route':data={'distance_km':'10.123','duration_minutes':20,'route_token':'mock-signed-route','source':'geoapify'}
  elif a=='payment':data={'id':'66666666-6666-4666-8666-666666666666','status':'confirmed','is_demo':True,'amount':42.06}
  route.fulfill(status=200,content_type='application/json',body=json.dumps({'ok':True,'data':data}))

def run():
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_EXECUTABLE',os.environ.get('CHROMIUM_PATH','/usr/bin/chromium')),args=['--no-sandbox'])
  mock=Mock();ctx=browser.new_context(viewport={'width':1440,'height':1000});ctx.route('**/api/index.php',mock.route)
  page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  for width in [1440,390]:
   page.set_viewport_size({'width':width,'height':1000})
   for name,role in [('painel','client'),('entregador','driver'),('admin','admin'),('enderecos','client'),('veiculos','driver'),('perfil','client'),('notificacoes','client'),('pagamentos','client'),('solicitar','client'),('pagamento?entrega='+DELIVERY,'client')]:
    mock.role=role;path=(name.split('?')[0]+'.html'+('?' + name.split('?')[1] if '?' in name else ''));page.goto(BASE+'/'+path);page.wait_for_timeout(120)
    assert not errors,(path,errors)
    overflow=page.evaluate('document.documentElement.scrollWidth>innerWidth+1')
    assert not overflow,(path,width,'horizontal overflow')
  mock.role='admin';page.set_viewport_size({'width':1440,'height':1000});page.goto(BASE+'/admin.html');page.wait_for_timeout(100)
  for tab in ['approvals','deliveries','users','payments','tariffs','support','audit','overview']:
   page.locator('[data-admin-tab='+tab+']').click();assert not errors,errors
  page.goto(BASE+'/admin.html#tarifas');page.wait_for_timeout(100);assert page.locator('button[data-action=tariff-edit]').count()==1
  page.locator('[data-admin-tab=tariffs]').click();page.locator('[data-action=pricing-settings]').click();page.locator('[name=fuel_price_per_litre]').fill('7.20');page.locator('dialog button[type=submit]').click();page.wait_for_timeout(80);assert any(c.get('name')=='update_pricing_settings' for c in mock.calls if c['action']=='rpc')
  mock.role='client';mock.delivery_status='to_pickup';page.goto(BASE+'/painel.html');page.locator('[data-action=vehicle-check]').click();page.locator('[name=vehicle_matches]').select_option('yes');page.locator('[name=note]').fill('Marca, modelo e placa conferem no local.');page.locator('dialog button[type=submit]').click();page.wait_for_timeout(80);assert mock.confirmed
  mock.role='driver';page.goto(BASE+'/entregador.html');page.locator('[data-action=advance]').click();page.locator('dialog button[type=submit]').click();page.wait_for_timeout(80);assert any(c.get('name')=='advance_delivery' for c in mock.calls if c['action']=='rpc')
  mock.role='client';mock.delivery_status='awaiting_driver';page.goto(BASE+'/solicitar.html');page.wait_for_timeout(100)
  for name,value in {'description-0':'Caixa de livros','quantity-0':'1','weight-0':'1000','length_cm-0':'10','width_cm-0':'10','height_cm-0':'10'}.items():page.locator('[name="'+name+'"]').fill(value)
  page.locator('[name="unit-0"]').select_option('g');page.locator('#step-form button[type=submit]').click()
  page.locator('#saved-pickup').select_option(ADDRESS['id']);page.locator('[name=recipient_name]').fill('Maria Silva');page.locator('[name=recipient_phone]').fill('11999999999');page.locator('#step-form button[type=submit]').click()
  page.locator('[data-action=vehicle]').click();page.locator('#step-form button[type=submit]').click();page.locator('[name=distance_km]').fill('10');page.locator('#quote-form button[type=submit]').click();page.locator('#step-form button[type=submit]').click();page.locator('[name=confirmed]').check();page.locator('#step-form button[type=submit]').click();page.locator('[name=consent]').check();page.locator('#payment-form button[type=submit]').click();page.wait_for_timeout(100)
  assert page.locator('.code-chip').inner_text()==D['code'];assert not errors,errors
  weights=page.evaluate('MoveeDelivery.weightKg(1000000,"mg")');assert weights==1
  mock.route_enabled=True;page.goto(BASE+'/solicitar.html');page.wait_for_timeout(100)
  for name,value in {'description-0':'Caixa de livros','quantity-0':'1','weight-0':'1','length_cm-0':'10','width_cm-0':'10','height_cm-0':'10'}.items():page.locator('[name="'+name+'"]').fill(value)
  page.locator('#step-form button[type=submit]').click();page.locator('#saved-pickup').select_option(ADDRESS['id']);page.locator('[name=recipient_name]').fill('Maria Silva');page.locator('[name=recipient_phone]').fill('11999999999');page.locator('#step-form button[type=submit]').click();page.locator('[data-action=vehicle]').click();page.locator('#step-form button[type=submit]').click();page.locator('#quote-form button[type=submit]').click();page.wait_for_timeout(100)
  quote_calls=[c for c in mock.calls if c['action']=='rpc' and c.get('name')=='quote_delivery'];assert 'p_route_token' not in quote_calls[0]['args'];assert quote_calls[-1]['args']['p_route_token']=='mock-signed-route';assert quote_calls[-1]['args']['p_distance_km']==10.123;assert quote_calls[-1]['args']['p_scheduled_at']
  print('PASS: 20 application viewport/page checks; eight admin tabs + hash navigation; fuel/peak settings; assigned vehicle client confirmation and exact vehicle driver advance; seven-step demo order; automatic route token flow; mg conversion. All API responses mocked, no live external service tested.')
  ctx.close();browser.close()
if __name__=='__main__':run()
