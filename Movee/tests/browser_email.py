"""Email confirmation UI checks with intercepted API responses. No real mail/Auth calls.
Run PHP first; MOVEE_TEST_URL defaults http://127.0.0.1:8080.
"""
import copy,json,os,shutil
from pathlib import Path
from playwright.sync_api import sync_playwright
BASE=os.environ.get('MOVEE_TEST_URL','http://127.0.0.1:8080').rstrip('/')
QA=Path(os.environ.get('MOVEE_QA_DIR',str(Path(__file__).resolve().parents[1]/'var'/'qa')));QA.mkdir(parents=True,exist_ok=True)
TOKEN='a'*64
USER={'id':'11111111-1111-4111-8111-111111111111','email':'pessoa@example.test','email_confirmed':True,'phone_confirmed':False}
PROFILE={'id':USER['id'],'role':'client','requested_role':'client','full_name':'Pessoa de Teste','phone':'11999999999','verification_channel':'email'}
class Fake:
 def __init__(self): self.calls=[];self.confirmed=False;self.expired=False;self.login_unconfirmed=False;self.sms=False;self.registration_session=False
 def session(self): return {'user':copy.deepcopy(USER) if self.confirmed else None,'profile':copy.deepcopy(PROFILE) if self.confirmed else None,'configured':True,'csrf':'test-csrf','sms_enabled':self.sms,'payment_mode':'demo','route_enabled':False}
 def answer(self,v):
  self.calls.append(copy.deepcopy(v));a=v['action']
  if a=='session':return self.session()
  if a=='verify':
   if self.expired:return None,422,{'message':'Link inválido ou expirado.','code':'confirmation_invalid'}
   self.confirmed=True;r=self.session()
   if v.get('channel')=='sms':r['user']['phone_confirmed']=True
   return r
  if a=='login':
   if self.login_unconfirmed:return None,403,{'message':'Confirme seu e-mail antes de entrar.','code':'confirmation_required'}
   self.confirmed=True;return self.session()
  if a=='register':return {'session':{'unsafe':'test-only'},'user':USER,'requires_verification':False} if self.registration_session else {'requires_verification':True}
  if a in ['resend','recover']:return {'sent':True}
  if a=='reset_password':return {'updated':True}
  if a=='data':return []
  if a=='rpc':return None
  raise AssertionError('Unhandled fake API action '+a)
 def route(self,route):
  v=route.request.post_data_json;r=self.answer(v)
  if isinstance(r,tuple):route.fulfill(status=r[1],content_type='application/json',body=json.dumps({'ok':False,'error':r[2]}))
  else:route.fulfill(status=200,content_type='application/json',body=json.dumps({'ok':True,'data':r}))
results=[];errors=[]
def check(ok,label):
 results.append({'check':label,'passed':bool(ok)})
 if not ok:raise AssertionError(label)
def mounted(browser,fake,width=1440,pending=None):
 ctx=browser.new_context(viewport={'width':width,'height':950})
 if pending:ctx.add_init_script('sessionStorage.setItem("movee.verification",'+json.dumps(json.dumps(pending))+');')
 page=ctx.new_page();page.on('pageerror',lambda error:errors.append(str(error)));page.route('**/api/index.php',fake.route)
 return ctx,page
with sync_playwright() as p:
 executable=os.environ.get('CHROMIUM_EXECUTABLE') or shutil.which('chromium') or shutil.which('chromium-browser')
 launch={'headless':True,'args':['--no-sandbox']}
 if executable:launch['executable_path']=executable
 browser=p.chromium.launch(**launch)
 for width in [390,1440]:
  fake=Fake();ctx,page=mounted(browser,fake,width)
  page.goto(BASE+'/verificar.html?token_hash='+TOKEN+'&type=signup&next=solicitar.html');page.locator('#confirm-email-link').wait_for(state='visible')
  check('token_hash' not in page.url and TOKEN not in page.url,'secret stripped from URL '+str(width))
  check(not any(c['action']=='verify' for c in fake.calls),'GET never consumes proof '+str(width))
  check(page.evaluate('sessionStorage.getItem("movee.verification")') is None,'link works without retained email '+str(width))
  check(page.locator('meta[name=referrer]').get_attribute('content')=='no-referrer','confirmation page refuses referrer '+str(width))
  check(not page.evaluate('document.documentElement.scrollWidth>innerWidth'),'confirmation fits viewport '+str(width))
  page.screenshot(path=str(QA/f'email-link-{width}.png'),full_page=True)
  page.locator('#confirm-email-link').click();page.locator('#confirmation-success').wait_for(state='visible')
  req=[c for c in fake.calls if c['action']=='verify'][0]
  check(req.get('token_hash')==TOKEN and req.get('type')=='signup' and 'email' not in req and 'access_token' not in req,'link sends proof only after explicit click '+str(width))
  check(page.locator('#confirmation-continue').get_attribute('href')=='solicitar.html','confirmation preserves continuation '+str(width))
  check(page.locator('#confirmation-success-title').inner_text()=='E-mail confirmado!','verified result displayed '+str(width))
  ctx.close()
 fake=Fake();fake.expired=True;ctx,page=mounted(browser,fake)
 page.goto(BASE+'/verificar.html?token_hash='+TOKEN+'&type=signup');page.locator('#confirm-email-link').click();page.locator('#notice').wait_for(state='visible')
 check('expirou' in page.locator('#notice').inner_text(),'expired link has clear error')
 check(page.locator('#confirmation-success').is_hidden(),'expired link never shows success')
 page.locator('#verify-form #email').fill('pessoa@example.test');page.locator('#resend-code').click();page.wait_for_timeout(100)
 check(any(c['action']=='resend' for c in fake.calls),'expired link can request another email')
 fake.expired=False;page.locator('#token').fill('123456');page.locator('#verify-form [type=submit]').click();page.locator('#confirmation-success').wait_for(state='visible')
 check(page.locator('#notice').is_hidden(),'successful fallback clears stale link errors');ctx.close()
 fake=Fake();ctx,page=mounted(browser,fake)
 page.goto(BASE+'/verificar.html?token_hash=short&type=signup');page.locator('#notice').wait_for(state='visible')
 check(not any(c['action']=='verify' for c in fake.calls),'malformed proof not sent')
 check('token_hash' not in page.url,'malformed proof removed from URL');ctx.close()
 fake=Fake();ctx,page=mounted(browser,fake)
 page.goto(BASE+'/verificar.html#access_token=untrusted&refresh_token=untrusted');page.locator('#notice').wait_for(state='visible')
 check('#' not in page.url and page.locator('#email-link-panel').is_hidden(),'fragment credentials rejected and cleared');ctx.close()
 fake=Fake();ctx,page=mounted(browser,fake)
 page.goto(BASE+'/verificar.html?token_hash='+TOKEN+'&type=recovery');page.locator('#confirm-email-link').click();page.locator('#reset-form').wait_for(state='visible')
 check([c for c in fake.calls if c['action']=='verify'][0].get('type')=='recovery','recovery link validates correct proof type')
 page.locator('#new-password').fill('Movee@2026nova');page.locator('#new-password-confirm').fill('Movee@2026nova');page.locator('#reset-form [type=submit]').click();page.wait_for_url('**/login.html')
 check(any(c['action']=='reset_password' for c in fake.calls),'recovery link retains password reset flow');ctx.close()
 fake=Fake();ctx,page=mounted(browser,fake)
 page.goto(BASE+'/verificar.html');page.locator('#verify-form #email').fill('pessoa@example.test');page.locator('#token').fill('123456');page.locator('#verify-form [type=submit]').click();page.locator('#confirmation-success').wait_for(state='visible')
 req=[c for c in fake.calls if c['action']=='verify'][0]
 check(req.get('email')=='pessoa@example.test' and req.get('token')=='123456' and 'token_hash' not in req,'email OTP fallback remains available');ctx.close()
 fake=Fake();fake.confirmed=True;fake.sms=True;ctx,page=mounted(browser,fake,pending={'channel':'sms','phone':'11999999999','email':USER['email']})
 page.goto(BASE+'/verificar.html?channel=sms');page.locator('#channel').select_option('sms');page.locator('#phone').fill('11999999999');page.locator('#token').fill('123456');page.locator('#verify-form [type=submit]').click();page.locator('#confirmation-success').wait_for(state='visible')
 check([c for c in fake.calls if c['action']=='verify'][0].get('channel')=='sms','secondary phone OTP preserved')
 check(page.locator('#confirmation-success-title').inner_text()=='Telefone confirmado.','SMS success identified as phone');ctx.close()
 fake=Fake();fake.login_unconfirmed=True;ctx,page=mounted(browser,fake)
 page.goto(BASE+'/login.html?next=solicitar.html');page.locator('#email').fill(USER['email']);page.locator('#password').fill('Movee@2026nova');page.locator('#login-form [type=submit]').click();page.locator('#login-confirmation-help').wait_for(state='visible')
 check('/login.html' in page.url,'unconfirmed login remains blocked')
 check('Confirme seu e-mail' in page.locator('#notice').inner_text(),'unconfirmed login explains required email')
 retained=json.loads(page.evaluate('sessionStorage.getItem("movee.verification")'))
 check(retained['email']==USER['email'] and retained['next']=='solicitar.html','confirmation help retains email and requested operation')
 check('next=solicitar.html' in page.locator('#login-confirmation-link').get_attribute('href'),'login confirmation help preserves return');ctx.close()
 fake=Fake();fake.registration_session=True;ctx,page=mounted(browser,fake)
 page.goto(BASE+'/cadastro.html');page.locator('#full_name').fill('Pessoa de Teste');page.locator('#cpf_cnpj').fill('52998224725');page.locator('#birth_date').fill('1990-01-01');page.locator('#phone').fill('11999999999');page.locator('[data-register-step="0"] [data-next-step]').click()
 page.locator('#email').fill(USER['email']);page.locator('#password').fill('Movee@2026nova');page.locator('#password_confirm').fill('Movee@2026nova');page.locator('[data-register-step="1"] [data-next-step]').click();page.locator('#terms').check();page.locator('#register-form [type=submit]').click();page.wait_for_url('**/verificar.html')
 check('/verificar.html' in page.url and not fake.confirmed,'signup always routes to email confirmation, never directly into profile');ctx.close()
 check(not errors,'no uncaught JavaScript errors')
 browser.close()
report={'scope':'UI API fixtures only; no real Auth or email delivery','passed':sum(r['passed'] for r in results),'total':len(results),'checks':results,'errors':errors}
(QA/'email-browser-results.json').write_text(json.dumps(report,indent=2,ensure_ascii=False));print(json.dumps({'passed':report['passed'],'total':report['total'],'errors':errors}))
