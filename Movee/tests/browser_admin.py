"""Admin addition UI checks with API fixtures. No live Supabase/Auth/provider claim.
Run PHP at MOVEE_TEST_URL; install Playwright and Chromium first.
"""
import copy,json,os,shutil
from pathlib import Path
from datetime import datetime, timezone, timedelta
from playwright.sync_api import sync_playwright
BASE=os.environ.get('MOVEE_TEST_URL','http://127.0.0.1:8080').rstrip('/')
QA=Path(os.environ.get('MOVEE_QA_DIR',str(Path(__file__).resolve().parents[1]/'var'/'qa')));QA.mkdir(parents=True,exist_ok=True)
UID='11111111-1111-4111-8111-111111111111';DID='22222222-2222-4222-8222-222222222222';DRIVER='33333333-3333-4333-8333-333333333333';REQ='44444444-4444-4444-8444-444444444444'
NOW=datetime.now(timezone.utc).isoformat();YEAR=datetime.now(timezone.utc).year
ADDR={'street':'Rua de Teste','number':'10','city':'São Paulo','state':'SP','postal_code':'01001000','neighborhood':'Centro'}
class Mock:
 def __init__(self):self.role='admin';self.calls=[];self.percent=30;self.approval_status='pending';self.fail_revenue=False
 def response(self,v):
  self.calls.append(copy.deepcopy(v));a=v['action']
  if a=='session':return {'user':{'id':UID,'email':'gestora@example.test'} if self.role else None,'profile':{'id':UID,'full_name':'Ana Gestora','role':self.role,'requested_role':self.role,'terms_accepted_at':NOW} if self.role else None,'csrf':'test-csrf','configured':True,'payment_mode':'demo','sms_enabled':False}
  if a=='data':
   t=v['table'];f=v.get('filters',{});rows={
    'vehicle_categories':[{'id':'motorcycle','name':'Moto','image':'assets/img/motorcycle.svg','active':True}],
    'profiles':[{'id':DRIVER,'full_name':'Entregador Teste','role':'client','requested_role':'driver','phone':'11987654321','created_at':NOW},{'id':'admin-applicant','full_name':'Admin Requerente','role':'client','requested_role':'admin','created_at':NOW}],
    'approval_requests':[{'id':REQ,'user_id':DRIVER,'kind':'driver','status':self.approval_status,'justification':'Solicitação de entregador para teste.','created_at':NOW},{'id':'req-admin','user_id':'admin-applicant','kind':'admin','status':'pending','justification':'Acesso administrativo para teste.','created_at':NOW}],
    'driver_profiles':[{'id':DRIVER,'cnh_number':'12345678901','cnh_category':'AB','cnh_expires_at':'2029-01-01','status':'pending'}],
    'documents':[{'id':'doc-1','user_id':DRIVER,'kind':'identity','status':'verified','created_at':NOW}],
    'approval_history':[{'id':'hist1','request_id':REQ,'status':'pending','reason':'Cadastro enviado para análise.','created_at':NOW}],
    'deliveries':[{'id':DID,'code':'MV-ABCDEF123456','client_id':'client-id','driver_id':DRIVER,'vehicle_id':'vehicle-id','category_id':'motorcycle','status':'to_pickup','price':'10.00','commission_percent':'30','commission_amount':'3.00','total_weight_kg':'1','pickup':ADDR,'destination':ADDR,'recipient_name':'Pessoa Recebedora','recipient_phone':'11987654321','created_at':NOW,'scheduled_at':NOW},{'id':'waiting-id','code':'MV-AAAAAA123456','client_id':'client-id','driver_id':None,'category_id':'motorcycle','status':'awaiting_driver','price':'20','total_weight_kg':'2','pickup':ADDR,'destination':ADDR,'created_at':(datetime.now(timezone.utc)-timedelta(days=2)).isoformat()}],
    'delivery_events':[{'id':'event1','delivery_id':DID,'status':'to_pickup','note':'A caminho da coleta de teste.','created_at':NOW}],
    'support_tickets':[{'id':'support1','delivery_id':DID,'user_id':'client-id','subject':'Veículo diferente','message':'A placa apresentada precisa de análise.','status':'open','created_at':NOW}],
    'payments':[],'reviews':[],'notifications':[],'audit_logs':[]}.get(t,[])
   if v.get('op','list')!='list':return v.get('data',{})
   rows=[r for r in rows if all(r.get(k)==value for k,value in f.items())]
   return rows[v.get('offset',0):v.get('offset',0)+v.get('limit',100)]
  if a=='document':return {'url':'https://example.test/private-document','expires_in':60}
  if a=='rpc':
   name=v['name'];args=v.get('args',{})
   if name=='admin_report':return {'deliveries':2,'delivered':0,'pending_approvals':1,'demo_revenue':0,'live_revenue':10,'daily':[],'pricing':{'commission_percent':self.percent}}
   if name=='admin_monthly_revenue':
    if self.fail_revenue:raise RuntimeError('Falha temporária de teste.')
    year=args['p_year'];empty=year!=YEAR
    months=[{'month':m,'month_start':f'{year}-{m:02d}-01','gross_amount':'0.00','commission_amount':'0.00','driver_amount':'0.00','payment_count':0,'commission_payment_count':0,'unconfigured_payment_count':0} for m in range(1,13)]
    if not empty:
     months[0].update(gross_amount='10.00',commission_amount='3.00',driver_amount='7.00',payment_count=1,commission_payment_count=1)
     months[6].update(gross_amount='100.00',commission_amount='30.00',driver_amount='70.00',payment_count=1,commission_payment_count=1)
     months[7].update(gross_amount='50.00',payment_count=1,unconfigured_payment_count=1)
    return {'year':year,'currency':'BRL','timezone':'America/Sao_Paulo','basis':'confirmed_company_commission','months':months,'total_gross_amount':'0.00' if empty else '160.00','total_commission_amount':'0.00' if empty else '33.00','total_driver_amount':'0.00' if empty else '77.00','total_payment_count':0 if empty else 3,'total_commission_payment_count':0 if empty else 2,'unconfigured_payment_count':0 if empty else 1,'demo_excluded_count':2,'refunded_excluded_count':1,'legacy_confirmation_count':0 if empty else 1,'commission_percent':self.percent}
   if name=='update_pricing_settings':self.percent=args['p_values']['commission_percent'];return {'commission_percent':self.percent}
   if name=='review_account':self.approval_status=args['p_status'];return {'id':REQ,'status':self.approval_status}
   if name=='assigned_vehicle':return {'id':'vehicle-id','category_id':'motorcycle','brand':'Marca','model':'Modelo','plate':'ABC1D23'}
   return {}
  return {}
 def route(self,route):
  try:route.fulfill(status=200,content_type='application/json',body=json.dumps({'ok':True,'data':self.response(route.request.post_data_json)}))
  except RuntimeError as e:route.fulfill(status=503,content_type='application/json',body=json.dumps({'ok':False,'error':{'message':str(e)}}))
results=[]
def check(ok,label):
 results.append({'check':label,'passed':bool(ok)})
 if not ok:raise AssertionError(label)
with sync_playwright() as p:
 executable=os.environ.get('CHROMIUM_EXECUTABLE') or shutil.which('chromium') or shutil.which('google-chrome')
 browser=p.chromium.launch(**({'executable_path':executable} if executable else {}),headless=True,args=['--no-sandbox'])
 page=browser.new_page();page.set_default_timeout(8000);mock=Mock();errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.route('**/api/index.php',mock.route)
 for width in [1440,390]:
  page.set_viewport_size({'width':width,'height':950})
  for path,needle in [('admin-entregas.html','Entregas da operação'),('admin-entregadores.html','Analisar entregadores'),('admin-rendimentos.html','Rendimentos mensais da empresa')]:
   page.goto(BASE+'/'+path);page.locator('#app-content').get_by_role('heading',name=needle,exact=True).wait_for()
   check(not page.evaluate('document.documentElement.scrollWidth>window.innerWidth+1'),f'{path} fits {width}px')
   check(page.locator('#app-sidebar a[href="admin-rendimentos.html"]').count()==1,'Finance navigation present '+path+str(width))
  page.screenshot(path=str(QA/f'admin-revenue-{width}.png'),full_page=True)
  check(page.locator('.revenue-month').count()==12,'Twelve months displayed '+str(width))
  check(page.locator('#revenue-table tbody tr').count()==12,'Accessible monthly table '+str(width))
  check('R$\xa033,00' in page.locator('.revenue-summary').inner_text() or '33,00' in page.locator('.revenue-summary').inner_text(),'Company commission total '+str(width))
  check('77,00' in page.locator('.revenue-summary').inner_text(),'Known driver shares only '+str(width))
  check(page.get_by_text('Esses valores constam no total bruto',exact=False).count()==1,'Unknown historical split notice '+str(width))
 # Year changes and explicit demo-only empty state.
 page.locator('#revenue-year').fill(str(YEAR-1));page.get_by_role('button',name='Consultar ano',exact=True).click();page.get_by_text('Nenhuma comissão real registrada neste ano.',exact=True).wait_for()
 check('demonstrativo(s) fora do resultado' in page.locator('#revenue-results').inner_text(),'Demo-only year has no fabricated income')
 check(mock.calls[-1]['args']['p_year']==YEAR-1,'Year sent to server RPC')
 page.locator('#revenue-year').fill(str(YEAR));page.get_by_role('button',name='Consultar ano',exact=True).click();page.locator('#revenue-table').wait_for()
 with page.expect_download() as download_info:page.get_by_role('button',name='Exportar CSV').click()
 check(download_info.value.suggested_filename==f'Movee-comissoes-{YEAR}.csv','CSV export downloads chosen year')
 # Changing commission preserves already-reported historical totals.
 page.get_by_role('button',name='Configurar comissão',exact=True).click();page.locator('dialog input[name="commission_percent"]').fill('25');page.get_by_role('button',name='Salvar comissão',exact=True).click();page.locator('dialog').wait_for(state='detached')
 check(any(c.get('name')=='update_pricing_settings' and c.get('args',{}).get('p_values',{}).get('commission_percent')==25 for c in mock.calls),'Commission update invokes protected RPC')
 check('33,00' in page.locator('.revenue-summary').inner_text(),'Existing commission result unchanged by new rate')
 # Error state has functional retry.
 mock.fail_revenue=True;page.get_by_role('button',name='Atualizar relatório',exact=True).click();page.get_by_text('Não foi possível consultar o relatório.',exact=True).wait_for();mock.fail_revenue=False;page.get_by_role('button',name='Tentar novamente',exact=True).click();page.locator('#revenue-table').wait_for();check(True,'Financial query error recovers on retry')
 # Delivery monitoring details, filtering and actual event history presentation.
 page.goto(BASE+'/admin-entregas.html');page.locator('#admin-orders-list').wait_for();check('Veículo diferente' in page.locator('#app-content').inner_text(),'Operational incidents are visible')
 page.locator('#admin-orders-code').fill('ABCDEF');check(page.locator('#admin-orders-list tbody tr').count()==1,'Delivery code filter works');page.get_by_role('button',name='Histórico',exact=True).click();page.get_by_text('A caminho da coleta de teste.',exact=True).wait_for();check(True,'Delivery history uses event data');page.locator('dialog .dialog-cancel').click()
 # Driver-only queue excludes admin applicants; documents, history and reasoned review work.
 page.goto(BASE+'/admin-entregadores.html');page.locator('#approval-list').wait_for();check('Admin Requerente' not in page.locator('#approval-list').inner_text(),'Driver queue excludes admin applications')
 page.get_by_role('button',name='Analisar documentos',exact=True).click();page.get_by_role('heading',name='Análise documental',exact=True).wait_for();check(page.get_by_role('button',name='Verificar',exact=True).count()==1,'Driver documents can be reviewed');page.locator('dialog .dialog-cancel').click()
 page.get_by_role('button',name='Histórico',exact=True).click();page.get_by_text('Cadastro enviado para análise.',exact=True).wait_for();page.locator('dialog .dialog-cancel').click();check(True,'Approval history visible')
 page.get_by_role('button',name='Decidir',exact=True).click();page.locator('dialog select[name="status"]').select_option('approved');page.locator('dialog textarea[name="reason"]').fill('Documentos e cadastro conferidos.');page.get_by_role('button',name='Registrar decisão',exact=True).click();page.locator('dialog').wait_for(state='detached');check(any(c.get('name')=='review_account' and c.get('args',{}).get('p_status')=='approved' for c in mock.calls),'Reasoned driver approval invokes real contract')
 page.get_by_role('button',name='Decidir',exact=True).click();page.locator('dialog select[name="status"]').select_option('rejected');page.locator('dialog textarea[name="reason"]').fill('Correções documentais necessárias.');page.get_by_role('button',name='Registrar decisão',exact=True).click();page.locator('dialog').wait_for(state='detached');check(any(c.get('name')=='review_account' and c.get('args',{}).get('p_status')=='rejected' for c in mock.calls),'Reasoned driver rejection invokes real contract')
 # Direct role guard prevents any admin RPC for a client.
 mock.role='client'
 for path in ['admin-entregas.html','admin-entregadores.html','admin-rendimentos.html']:
  mock.calls=[];page.goto(BASE+'/'+path);page.get_by_text('Área de acesso restrito.',exact=True).wait_for();check(not any(c.get('action')=='rpc' for c in mock.calls),'Client blocked from '+path)
 mock.role=None;page.goto(BASE+'/admin-rendimentos.html');page.wait_for_url('**/login.html?next=admin-rendimentos.html');check(True,'Login preserves new financial page continuation')
 check(not errors,'No uncaught JavaScript errors')
 browser.close()
report={'scope':'API fixtures; no live Supabase/Auth/Storage/provider tests','passed':sum(r['passed'] for r in results),'total':len(results),'checks':results,'errors':errors}
(QA/'admin-browser-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'passed':report['passed'],'total':report['total'],'errors':errors},ensure_ascii=False))
