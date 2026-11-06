# Movee — comece por aqui

## 1. Extraia os dois ZIPs

Extraia `Movee-site-GitHub.zip` e `Movee-Supabase-GitHub.zip` no mesmo local, unindo o conteúdo na mesma pasta `Movee`. O primeiro contém o site completo; o segundo contém somente o banco Supabase e suas instruções. VS Code não é obrigatório.

## 2. Instale o banco

Abra `ORDEM-DO-BANCO.md`. Para um projeto Supabase novo, execute os 20 scripts de `sql/` em ordem, de 01 a 20, ou use `sql/BANCO-SUPABASE-COMPLETO.sql`, sem executar as duas formas. Testes não fazem parte da instalação de produção. Em uma base já instalada até 19, execute somente 20; até 18, execute 19 e 20.

## 3. Configure o e-mail e o servidor

Ative **Confirm email** no Supabase Auth. Configure SMTP, Site URL, URLs permitidas e os templates de `auth/templates/`. Copie `.env.example` para `.env`, preencha as credenciais no servidor e mantenha `APP_DATA_BACKEND=supabase`. O `.env` deve ficar fora de `public/` e do Git.

## 4. Inicie para desenvolvimento

Com PHP 8.2+ e as extensões do guia instaladas, execute na pasta `Movee`:

```sh
php bin/check-environment.php
php -S 127.0.0.1:8080 -t public router.php
```

Abra `http://127.0.0.1:8080`. A configuração completa e o primeiro administrador estão em `docs/INSTALACAO.md`.

## 5. Envie ao GitHub

Leia `docs/GITHUB.md`. Envie os arquivos extraídos, incluindo `.gitignore` e `.env.example`, e preserve a estrutura. Não envie o `.env` preenchido nem `var/`. GitHub Pages não executa PHP; a publicação completa exige hospedagem PHP com HTTPS e raiz web em `public/`.

## 6. Confira os serviços externos

A confirmação de e-mail exige SMTP configurado. Rotas automáticas exigem Geoapify; cobranças reais exigem Mercado Pago e webhook. Simulações são identificadas. Consulte `docs/TESTES.md` para as verificações locais e os testes externos pendentes.
