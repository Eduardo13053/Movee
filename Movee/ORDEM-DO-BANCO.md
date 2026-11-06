# Movee — instalação do banco Supabase

## 1. Organize os dois pacotes

Extraia **Movee-site-GitHub.zip** e **Movee-Supabase-GitHub.zip** no mesmo destino, unindo a pasta superior `Movee`. O código fica em `public/` e `src/`; o banco fica em `sql/`. Este pacote de banco contém somente Supabase/PostgreSQL.

## 2. Escolha a forma de instalação nova

Em um projeto Supabase novo, execute os 20 arquivos abaixo, na ordem. Alternativamente, execute **somente** `sql/BANCO-SUPABASE-COMPLETO.sql`, que reúne os mesmos 20 scripts. Não execute as duas formas na mesma instalação.

1. `sql/01_initial.sql` — Estrutura inicial e parâmetros.
2. `sql/02_validations.sql` — Validações.
3. `sql/03_profiles.sql` — Perfis do Auth.
4. `sql/04_drivers.sql` — Entregadores.
5. `sql/05_approvals.sql` — Aprovações e histórico.
6. `sql/06_addresses.sql` — Endereços.
7. `sql/07_vehicle_categories.sql` — Categorias, capacidades e tarifas.
8. `sql/08_vehicles.sql` — Veículos dos entregadores.
9. `sql/09_documents.sql` — Documentos privados.
10. `sql/10_deliveries.sql` — Entregas, itens, eventos e rotas.
11. `sql/11_payments.sql` — Pagamentos.
12. `sql/12_communication.sql` — Notificações, suporte, auditoria e avaliações.
13. `sql/13_account_functions.sql` — Cadastro e aprovação.
14. `sql/14_delivery_functions.sql` — Frete, aceite, veículo e rastreamento.
15. `sql/15_admin_service_functions.sql` — Administração e serviços internos.
16. `sql/16_triggers.sql` — Triggers de integridade.
17. `sql/17_rls_storage.sql` — RLS, permissões e Storage privado.
18. `sql/18_indexes_views.sql` — Índices e views.
19. `sql/19_admin_monthly_revenue.sql` — Comissão 30/70 e rendimentos mensais.
20. `sql/20_email_confirmation.sql` — Confirmação obrigatória de e-mail.

Confira o sucesso de cada etapa antes de continuar. Os blocos finais atualizam funções criadas anteriormente; conclua a sequência inteira antes de usar o site.

## 3. Atualize uma base existente

Se a base já está até 19, execute somente `20_email_confirmation.sql`. Se está até 18, execute 19 e depois 20. Não recrie as tabelas de uma base em uso.

## 4. Configure Auth e o site

Ative Email e **Confirm email** no Supabase Auth. Configure Site URL igual a APP_URL, redirects permitidos, SMTP e os templates de `auth/templates/` do pacote do site. Preencha somente no servidor o `.env` a partir de `.env.example`, com APP_DATA_BACKEND=supabase e as credenciais do mesmo projeto. A service_role fica exclusivamente no PHP/CLI.

Os scripts criam o bucket privado `movee-documents`. Não publique esse bucket. O primeiro administrador deve cadastrar-se, confirmar e-mail, enviar identidade e passar pela conferência manual do operador antes do comando `php bin/bootstrap-admin.php UUID_DO_USUARIO`.

## 5. Separe produção, consulta e testes

`sql/consultas/01_admin_entregas_itens.sql` é uma consulta de leitura que mostra entrega, mercadorias, cliente, entregador e veículo. Não é uma migração adicional. A aplicação continua usando as RPCs/permissões do modelo.

`sql/tests/` e `tests/local/` são ferramentas para base descartável de testes. Não execute os stubs locais no Supabase: Auth e Storage já são nativos. Testes e limitações estão em `docs/TESTES.md`, no pacote do site.

## 6. Coloque os arquivos no GitHub

Depois de juntar os dois pacotes, envie o conteúdo da pasta `Movee` ao repositório, incluindo `.gitignore` e `.env.example`. Não envie `.env`, chaves, sessões, uploads ou dados reais. Veja `docs/GITHUB.md`, no pacote do site. GitHub Pages não executa a API PHP; para operar o site será necessário um servidor PHP.

## 7. Recursos alinhados ao site

O modelo mantém CPF/CNPJ de vendedores, entregadores com múltiplos veículos, mercadorias por entrega, veículo designado e conferido na coleta, frete calculado, análise administrativa, RLS, triggers, índices, comissão inicial de 30% para Movee/70% para entregador e gráfico de comissões de pagamentos reais confirmados. Confirmação de e-mail usa o estado canônico do Auth.
