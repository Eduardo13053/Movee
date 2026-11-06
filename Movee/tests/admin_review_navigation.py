"""Focused independent admin checks: login continuation, access guard and stale-year race.
API fixtures validate browser behavior only; they do not test remote Supabase Auth.
Requires a running PHP server and optional Playwright tooling from requirements-dev.txt.
"""
import asyncio
import json
import os
import shutil
from urllib.parse import parse_qs, urlparse
from playwright.async_api import async_playwright

BASE = os.environ.get('MOVEE_TEST_URL', 'http://127.0.0.1:8080').rstrip('/')
EXECUTABLE = os.environ.get('CHROMIUM_EXECUTABLE') or shutil.which('chromium')
PAGES = ['admin-entregas.html', 'admin-entregadores.html', 'admin-rendimentos.html']


def report(year):
    value = f'{year % 10}.00'
    months = [dict(month=i, month_start=f'{year}-{i:02}-01', gross_amount='0.00',
                   commission_amount='0.00', driver_amount='0.00', payment_count=0,
                   commission_payment_count=0, unconfigured_payment_count=0)
              for i in range(1, 13)]
    months[0].update(gross_amount='10.00', commission_amount=value,
                     driver_amount=f'{10 - year % 10}.00', payment_count=1,
                     commission_payment_count=1)
    return dict(year=year, currency='BRL', timezone='America/Sao_Paulo',
                basis='confirmed_company_commission', commission_percent='30',
                months=months, total_gross_amount='10.00',
                total_commission_amount=value, total_driver_amount=f'{10 - year % 10}.00',
                total_payment_count=1, total_commission_payment_count=1,
                unconfigured_payment_count=0, legacy_confirmation_count=0,
                demo_excluded_count=0, refunded_excluded_count=0)


async def main():
    passed = 0
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=EXECUTABLE, args=['--no-sandbox'])
        context = await browser.new_context(viewport={'width': 390, 'height': 844})
        for path in PAGES:
            page = await context.new_page()
            await page.goto(BASE + '/' + path)
            await page.wait_for_url('**/login.html?next=*')
            assert parse_qs(urlparse(page.url).query)['next'] == [path]
            passed += 1
            await page.close()
        await context.close()

        for role in ['client', 'driver']:
            context = await browser.new_context(viewport={'width': 390, 'height': 844})
            requests = []

            async def fixture(route, role=role):
                payload = route.request.post_data_json
                requests.append(payload)
                session = dict(user={'id': '11111111-1111-4111-8111-111111111111',
                                     'email': 'fixture@example.test'},
                               profile={'role': role, 'requested_role': role,
                                        'full_name': 'Pessoa de Teste'},
                               csrf='fixture-csrf', configured=True)
                await route.fulfill(json={'ok': True, 'data': session})

            await context.route('**/api/index.php', fixture)
            page = await context.new_page()
            await page.goto(BASE + '/admin-rendimentos.html')
            await page.get_by_role('heading', name='Área de acesso restrito.').wait_for()
            assert not any(x.get('name') == 'admin_monthly_revenue' for x in requests)
            passed += 1
            await context.close()

        context = await browser.new_context(viewport={'width': 390, 'height': 844})

        async def admin_fixture(route):
            payload = route.request.post_data_json
            if payload['action'] == 'session':
                data = dict(user={'id': '11111111-1111-4111-8111-111111111111',
                                  'email': 'fixture@example.test'},
                            profile={'role': 'admin', 'requested_role': 'admin',
                                     'full_name': 'Pessoa de Teste'}, csrf='fixture-csrf', configured=True)
            else:
                assert payload.get('name') == 'admin_monthly_revenue'
                year = payload['args']['p_year']
                await asyncio.sleep(0.35 if year == 2025 else 0.01)
                data = report(year)
            await route.fulfill(json={'ok': True, 'data': data})

        await context.route('**/api/index.php', admin_fixture)
        page = await context.new_page()
        await page.goto(BASE + '/admin-rendimentos.html')
        await page.locator('#revenue-table').wait_for()
        await page.locator('#revenue-year').fill('2025')
        await page.get_by_role('button', name='Consultar ano', exact=True).click()
        await page.locator('#revenue-year').fill('2024')
        await page.get_by_role('button', name='Consultar ano', exact=True).click()
        await page.locator('#revenue-table').wait_for()
        await page.wait_for_timeout(450)
        assert await page.locator('#revenue-year').input_value() == '2024'
        assert '4,00' in await page.locator('.revenue-summary .metric.highlight strong').inner_text()
        passed += 1
        assert await page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        passed += 1
        assert await page.locator('#revenue-table tbody tr').count() == 12
        passed += 1
        await context.close()
        await browser.close()
    print(json.dumps({'passed': passed, 'total': 8,
                      'note': 'Browser fixtures only; no remote Auth/payment verification.'}))


if __name__ == '__main__':
    asyncio.run(main())
