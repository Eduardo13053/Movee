# Movee — site e integração Supabase

Plataforma de logística para TCC com HTML5, CSS3, JavaScript puro, PHP 8.2+ e Supabase Auth, Storage e PostgreSQL. A marca é **Movee**.

## 1. Junte os dois pacotes

Extraia **Movee-site-GitHub.zip** e **Movee-Supabase-GitHub.zip** no mesmo destino, preservando a pasta superior `Movee`. Eles se complementam: o site fornece `public/`, `src/`, `bin/` e `auth/`; o banco fornece `sql/`, a documentação do modelo e `ORDEM-DO-BANCO.md`.

Você pode usar qualquer editor de texto. VS Code não é obrigatório.

## 2. Configure o Supabase

Em um projeto Supabase novo, execute os **20 scripts de produção** de `sql/`, na ordem de 01 a 20, ou execute o equivalente `sql/BANCO-SUPABASE-COMPLETO.sql`. Escolha uma das formas; não execute ambas na mesma base. Não execute os diretórios de testes na produção. Para uma base já instalada até 19, aplique somente 20; até 18, aplique 19 e 20.

Mantenha **Confirm email** ativado no Supabase Auth. Configure SMTP, Site URL igual a `APP_URL`, URLs permitidas e os templates de `auth/templates/`. O login exige confirmação canônica do e-mail. O bucket `movee-documents` permanece privado.

## 3. Configure e inicie o PHP

Instale PHP 8.2+ e as extensões descritas em [Instalação](docs/INSTALACAO.md). Copie `.env.example` para `.env`, configure as credenciais do seu projeto e mantenha `APP_DATA_BACKEND=supabase`. Gere `APP_KEY` conforme o guia. A chave `service_role` e todos os demais segredos ficam exclusivamente no servidor, fora de `public/` e do Git.

Na pasta `Movee`, execute:

```sh
php bin/check-environment.php
php -S 127.0.0.1:8080 -t public router.php
```

Abra `http://127.0.0.1:8080`. O servidor embutido é para desenvolvimento; publicação exige hospedagem PHP com HTTPS e raiz web em `public/`.

## 4. Coloque no GitHub

Siga [GITHUB.md](docs/GITHUB.md). Extraia os ZIPs e envie os **arquivos e pastas extraídos**, incluindo `.gitignore` e `.env.example`. O `.env` preenchido e os dados locais de `var/` não devem ser publicados.

GitHub armazena o código. **GitHub Pages não executa a API PHP**; o site completo precisa de hospedagem compatível com PHP.

## 5. Recursos e serviços externos

Inclui clientes, vendedores com CPF/CNPJ, entregadores com vários veículos, documentos privados, aprovação administrativa, entregas com mercadorias, frete por categoria/peso/volume/distância/combustível/pico, confirmação do veículo na coleta, rastreamento por eventos, suporte e notificações.

A comissão inicial é **30% Movee e 70% entregador**, preservada por entrega. Os rendimentos mensais usam comissões de pagamentos reais confirmados. O registro da parcela do entregador não realiza transferência bancária automática.

As tarifas iniciais são fictícias e configuráveis. Geoapify habilita rotas automáticas; sem o provedor, o site identifica a distância manual como estimativa. Mercado Pago exige credenciais e webhook para cobrança real. O modo `demo` identifica simulações e não cobra dinheiro. E-mails reais dependem do SMTP e dos provedores configurados.

## 6. Documentação

- [Instalação](docs/INSTALACAO.md): configuração completa, confirmação de e-mail e primeiro administrador.
- [GitHub](docs/GITHUB.md): envio dos dois pacotes extraídos.
- [Banco](docs/DATABASE.md): relações, dicionário e permissões; acompanha o ZIP Supabase.
- [Banco por extenso](docs/BANCO-SUPABASE-COMPLETO.md): SQL completo e numerado; acompanha o ZIP Supabase.
- [Confirmação de e-mail](docs/EMAIL-CONFIRMACAO.md).
- [Operação e segurança](docs/OPERACAO-SEGURANCA.md).
- [Testes](docs/TESTES.md): verificações locais e integrações externas pendentes.
