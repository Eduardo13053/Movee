"""Browser checks against the actual PHP server without Supabase credentials.
Run with PHP serving public/ at MOVEE_TEST_URL (default http://127.0.0.1:8080).
Does not mock Auth, submit a signup or claim external integration coverage.
Requires Python Playwright and Chromium. Outputs outside project in work/qa.
"""
import json, os, shutil
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE=os.environ.get('MOVEE_TEST_URL','http://127.0.0.1:8080').rstrip('/')
QA=Path(os.environ.get('MOVEE_QA_DIR',str(Path(__file__).resolve().parents[1]/'var'/'qa')));QA.mkdir(parents=True,exist_ok=True)
results=[];errors=[];requests=[]
def check(name, ok, detail=''):
    results.append({'check':name,'passed':bool(ok),'detail':detail})
    if not ok: print('FAIL:',name,detail)
def load(page,path):
    r=page.goto(BASE+'/'+path,wait_until='networkidle')
    page.locator('#site-header .brand').wait_for()
    check('HTTP '+path,r.status==200,str(r.status))
    return r
with sync_playwright() as p:
    executable=os.environ.get('CHROMIUM_EXECUTABLE') or shutil.which('chromium') or shutil.which('chromium-browser')
    launch={'headless':True,'args':['--no-sandbox']}
    if executable:launch['executable_path']=executable
    browser=p.chromium.launch(**launch)
    context=browser.new_context(viewport={'width':1440,'height':1000},locale='pt-BR')
    page=context.new_page()
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.on('requestfailed',lambda req:requests.append({'url':req.url,'failure':req.failure}))
    paths=['index.html','login.html','cadastro.html?tipo=cliente','cadastro.html?tipo=vendedor','cadastro.html?tipo=entregador','cadastro.html?tipo=administrador','recuperar.html','verificar.html','rastrear.html','ajuda.html','termos.html','privacidade.html']
    for width in [360,390,768,1440]:
        page.set_viewport_size({'width':width,'height':960})
        for path in paths:
            load(page,path)
            dims=page.evaluate('({viewport:innerWidth,doc:document.documentElement.scrollWidth,body:document.body.scrollWidth})')
            check(f'No horizontal overflow {width}px {path}',max(dims['doc'],dims['body'])<=width+1,str(dims))
            check(f'One primary heading {width}px {path}',page.locator('h1').count()==1)
            if path=='rastrear.html':
                check(f'Tracking initial instructions {width}px',page.locator('#tracking-intro').is_visible() and page.locator('#tracking-result').is_hidden())
                check(f'Tracking no automatic error {width}px',page.locator('#notice').is_hidden())
            if path=='ajuda.html':
                check(f'Support authenticated continuation {width}px',page.locator('#help-login a').get_attribute('href')=='login.html?next=ajuda.html')
                check(f'Support unauthenticated form disabled {width}px',page.locator('#support-form button[type=submit]').is_disabled())
            if path=='index.html' and width in [390,1440]:
                page.screenshot(path=str(QA/f'home-{width}.png'),full_page=True)
            if path=='login.html' and width==390:page.screenshot(path=str(QA/'login-390.png'),full_page=True)
            if path=='cadastro.html?tipo=vendedor' and width==390:page.screenshot(path=str(QA/'register-seller-390.png'),full_page=True)
        load(page,'index.html')
        if width<=850:
            toggle=page.locator('#menu-toggle');toggle.focus();page.keyboard.press('Enter')
            check(f'Mobile nav keyboard opens {width}px',toggle.get_attribute('aria-expanded')=='true' and page.locator('#main-nav').is_visible())
            page.keyboard.press('Tab')
            check(f'Mobile nav keyboard reaches links {width}px',page.evaluate('document.activeElement.closest("#main-nav")!==null'))
            page.keyboard.press('Escape')
            check(f'Mobile nav Escape closes and returns focus {width}px',toggle.get_attribute('aria-expanded')=='false' and toggle.evaluate('(e)=>e===document.activeElement'))
            page.keyboard.press('Enter')
            toggle.focus();page.keyboard.press('Enter')
            check(f'Mobile nav keyboard closes {width}px',toggle.get_attribute('aria-expanded')=='false')
        else:
            check('Desktop nav visible',page.locator('#main-nav').is_visible())
        page.locator('.skip-link').focus();page.keyboard.press('Enter')
        check(f'Skip link target {width}px',page.evaluate('location.hash==="#main"'))

    page.set_viewport_size({'width':390,'height':960})
    for kind in ['cliente','vendedor','entregador','administrador']:
        load(page,'cadastro.html?tipo='+kind)
        first=page.locator('[data-register-step="0"]');next0=first.locator('[data-next-step]')
        next0.click();check(f'{kind} required name blocks step',first.is_visible() and page.locator('#full_name').evaluate('(e)=>e.validity.valueMissing'))
        page.locator('#full_name').fill('João1 Silva');page.locator('#cpf_cnpj').fill('52998224725');page.locator('#birth_date').fill('1995-05-12');page.locator('#phone').fill('11999991234')
        if kind=='administrador':page.locator('#justification').fill('Solicito acesso para administrar a operação acadêmica de entregas.')
        next0.click();check(f'{kind} invalid name rejected',first.is_visible() and bool(page.locator('#full_name').evaluate('(e)=>e.validationMessage')))
        page.locator('#full_name').fill('João Pedro da Silva');page.locator('#cpf_cnpj').fill('11111111111');next0.click();check(f'{kind} invalid checksum rejected',first.is_visible() and bool(page.locator('#cpf_cnpj').evaluate('(e)=>e.validationMessage')))
        page.locator('#cpf_cnpj').fill('04252011000110' if kind=='vendedor' else '52998224725');page.locator('#phone').fill('20999991234');next0.click();check(f'{kind} invalid DDD rejected',first.is_visible() and bool(page.locator('#phone').evaluate('(e)=>e.validationMessage')))
        page.locator('#phone').fill('11999991234');page.locator('#birth_date').fill('2020-05-12');next0.click();check(f'{kind} underage rejected',first.is_visible() and page.locator('#birth_date').evaluate('(e)=>e.validity.rangeOverflow'))
        page.locator('#birth_date').fill('1995-05-12');next0.click();second=page.locator('[data-register-step="1"]');check(f'{kind} valid personal data advances',second.is_visible())
        if not second.is_visible():continue
        page.locator('#email').fill('ana@');page.locator('#password').fill('TesteSeguro1!');page.locator('#password_confirm').fill('TesteSeguro1!');second.locator('[data-next-step]').click();check(f'{kind} malformed email rejected',second.is_visible() and page.locator('#email').evaluate('(e)=>e.validity.typeMismatch'))
        page.locator('#email').fill('ana@example.com');page.locator('#password').fill('abcdefghij');page.locator('#password_confirm').fill('abcdefghij');second.locator('[data-next-step]').click();check(f'{kind} weak password rejected',second.is_visible() and bool(page.locator('#password').evaluate('(e)=>e.validationMessage')))
        page.locator('#password').fill('TesteSeguro1!');page.locator('#password_confirm').fill('Diferente1!');second.locator('[data-next-step]').click();check(f'{kind} password mismatch rejected',second.is_visible() and bool(page.locator('#password_confirm').evaluate('(e)=>e.validationMessage')))
        page.locator('#password_confirm').fill('TesteSeguro1!');second.locator('[data-next-step]').click();third=page.locator('[data-register-step="2"]');check(f'{kind} valid credentials advance review',third.is_visible())
        if not third.is_visible():continue
        check(f'{kind} review displays identity', 'João Pedro da Silva' in page.locator('#registration-review').inner_text())
        third.locator('button[type=submit]').click();check(f'{kind} terms required',page.locator('#terms').evaluate('(e)=>e.validity.valueMissing'))
        page.locator('#terms').check();third.locator('button[type=submit]').click();check(f'{kind} unconfigured Supabase fails visibly',page.locator('#notice').is_visible() and 'Supabase' in page.locator('#notice').inner_text())
        third.locator('[data-prev-step]').click();check(f'{kind} step back retains fields',second.is_visible() and page.locator('#email').input_value()=='ana@example.com')
        page.locator('[data-password="password"]').click();check(f'{kind} password show toggle',page.locator('#password').get_attribute('type')=='text')
        page.locator('[data-password="password"]').click();check(f'{kind} password hide toggle',page.locator('#password').get_attribute('type')=='password')
    load(page,'rastrear.html');page.locator('#tracking-code').fill('MV-EXEMPLO');page.locator('#tracking-form button').click();page.wait_for_url('**/login.html?next=rastrear.html');check('Tracking unauthenticated login continuation','next=rastrear.html' in page.url)
    load(page,'login.html?next=admin.html');check('Administrative login heading','administrativo' in page.locator('.auth-card h2').inner_text())
    check('No uncaught browser errors',not errors,str(errors))
    check('No failed resources',not requests,str(requests))
    browser.close()
report={'base':BASE,'backend':'actual PHP, Supabase unconfigured','results':results,'uncaught_errors':errors,'failed_requests':requests,'passed':sum(x['passed'] for x in results),'total':len(results),'excluded':['live signup/login/recovery/OTP','Supabase persistence/RLS/Storage','actual SMS/e-mail dispatch','real payment processing']}
(QA/'public-browser-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({'passed':report['passed'],'total':report['total'],'errors':errors,'failed':requests},ensure_ascii=False))
if report['passed']!=report['total']:raise SystemExit(1)
