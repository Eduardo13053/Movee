# Testes executados e limites da verificação

Os resultados abaixo foram obtidos no ambiente local desta entrega. Não foram usadas credenciais de um projeto Supabase real nem de provedores de pagamento, mensagens ou mapas. As contas e os documentos dos testes são dados fictícios, separados da instalação de produção.

## 1. Ambiente utilizado

- PHP 8.4.24; o código exige PHP 8.2 ou superior.
- PostgreSQL 17.11 em base nova, com representações locais mínimas de `auth` e `storage` para executar os scripts e as políticas. Não é uma instância remota do Supabase.
- MongoDB 8.0 em replica set, extensão PHP mongodb 2.0 e bcmath.
- Chromium com Playwright; servidor PHP local.

## 2. Sintaxe e limites da API PHP

As verificações de sintaxe de todos os PHP e JavaScript entregues passaram: 30 arquivos de código verificados. `tests/backend.php` executou **59 verificações, sem falhas**. Incluem CPF, CNPJ numérico e alfanumérico, nome, e-mail, telefone, senha, datas, limites de campos, números inválidos, colunas protegidas, RPCs privilegiados, CSRF, origem da requisição, recuperação sem código e assinatura/expiração/vínculos do token de rota.

Esses testes usam um adaptador controlado nos limites da API; não comprovam envio real de código ou login em Supabase remoto.

## 3. PostgreSQL e permissões

Os **18 scripts de produção** foram executados, na ordem, em uma base PostgreSQL vazia. Todos concluíram sem erro. As quatro suítes em `sql/tests/` passaram:

1. Validações de CPF/CNPJ, telefone e conversões de peso.
2. Fluxo de cadastro sem escalada de papel, documentos, aprovações, endereços, cotação, entrega, pagamento demonstrativo idempotente, aceite, conferência de veículo, status, comprovante, avaliação, rastreamento, notificações e isolamento.
3. Entradas malformadas, limites e proteções de permissões.
4. Combustível, horário de pico em São Paulo, bicicleta sem combustível, rota confiável exclusiva de serviço, distância/endereço/titular adulterados e criação vinculada à rota.

Foi encontrado e corrigido um alias SQL reservado, um alias ambíguo no cálculo de pico e uma validação de nomes dependente da localidade do PostgreSQL. A execução final em base nova passou após as correções.

## 4. Concorrência no PostgreSQL

`tests/local/concurrency.py` executou conexões simultâneas reais:

- A partir de dois endereços, dois cadastros concorrentes: um sucesso, uma rejeição, **três endereços ao final**.
- Dois entregadores aprovados aceitando a mesma entrega: um sucesso, uma rejeição, **um único entregador designado**.

O script é exclusivo para uma base local descartável com as representações de `auth`/`storage` de `tests/local/supabase-stubs.sql`. Nunca execute esse arquivo de representações no Supabase real.

## 5. MongoDB real

O inicializador foi executado em uma base nova de replica set. `tests/mongodb-workflow.php` executou **55 verificações aprovadas** sobre coleções e transações reais, usando identidades Auth substituídas por fixtures. Foram exercitados aprovação, isolamento, endereços, conversões, cálculo decimal, combustível/pico, rotas confiáveis, documentos de teste, pagamento demonstrativo, confirmação financeira de domínio, aceite, veículo exato, conferência do cliente, histórico, comprovante, avaliação, suporte e relatórios.

`tests/mongodb-concurrency.php` passou nas duas disputas reais: limite de três endereços e apenas um aceite/evento de atribuição por entrega. Não foram usados mocks de coleções. Supabase Auth/Storage e chamadas de provedor financeiro não foram executados nesses testes.

## 6. Interface pública e responsividade

`tests/browser_public.py` executou **255 verificações aprovadas** contra o servidor PHP real sem credenciais, nos tamanhos 360, 390, 768 e 1440 pixels. Foram verificados páginas públicas, modalidades de cadastro, menus, navegação por teclado, foco, validações, apresentação sem configuração externa, ausência de largura horizontal indevida e recursos locais. Não houve erros JavaScript não tratados nem recursos locais com falha.

A apresentação do veículo no rastreamento passou em **seis verificações com dados controlados**, incluindo ausência de veículo, conferência pendente e conferência registrada em 360 e 1440 pixels. Esses resultados validam a apresentação, não uma consulta a uma entrega real.

## 7. Interface autenticada e solicitação

`tests/browser_mock.py` usa respostas de API interceptadas para testar a interface: 20 combinações de página/tamanho, oito abas administrativas, configurações de combustível/pico, confirmação do veículo pelo cliente, identificador exato no avanço do entregador, sete etapas de solicitação e pagamento demonstrativo, conversão em mg e rota automática/token.

Esses testes passaram e revelaram um problema de largura no menu mobile e um token vazio no modo manual, ambos corrigidos. Eles não substituem o teste completo com PHP, Auth, Storage e Supabase remoto conectados.

## 8. O que depende da configuração do usuário

Ainda precisam de verificação no projeto final:

- Cadastro, login, confirmação e recuperação pelo Supabase Auth real, incluindo configuração dos templates de código e provedores de SMTP/SMS.
- Upload e consulta HTTP reais no Storage privado, com tentativa de acesso por outro usuário e arquivos inválidos.
- Entrega real de notificações por e-mail/SMS.
- Geocodificação e rotas reais do Geoapify, quotas, precisão dos endereços e perfil dos veículos.
- Checkout Mercado Pago com credenciais de teste, webhook HTTPS público, duplicidade, falhas e aprovação real de sandbox.
- Implantação HTTPS, permissões da hospedagem, Atlas quando escolhido, backups e rotina de retenção.
- Conferência física do veículo e autenticidade dos documentos. A aplicação registra a conferência; não identifica fisicamente o veículo sozinha.

Não foram declaradas como executadas essas verificações externas.

## 9. Reprodução

Na raiz do projeto, com as extensões instaladas:

```sh
php tests/backend.php
php -S 127.0.0.1:8080 -t public router.php
```

Em outro terminal, os testes opcionais de navegador exigem Python, `pip install -r requirements-dev.txt` e Chromium/Playwright configurado. Use `MOVEE_TEST_URL` para mudar a origem de teste e `CHROMIUM_EXECUTABLE` para selecionar o navegador quando necessário:

```sh
python tests/browser_public.py
python tests/browser_mock.py
```

Os testes PostgreSQL podem ser executados no SQL Editor somente em um projeto de testes descartável, após os scripts de produção, conforme seus cabeçalhos. As fixtures de `tests/local/` são destinadas apenas ao PostgreSQL local vazio.

Para MongoDB, siga `MONGODB.md`, inicialize uma base descartável cujo nome termine em `_test` e execute:

```sh
php tests/mongodb-workflow.php
php tests/mongodb-concurrency.php
```

Os scripts de teste usam dados fictícios e podem limpar coleções da base de teste. Não aponte seus comandos para uma instalação com dados reais.

## 10. Atualização administrativa, comissões e marca Movee

A atualização seguinte acrescentou as páginas administrativas de entregas, entregadores e rendimentos, além de padronizar a marca com M maiúsculo no nome e monograma.

- **PostgreSQL 17:** instalação limpa com os 19 scripts, incluindo a nova migração 19, passou. As cinco suítes SQL passaram. O script 19 também foi aplicado e reaplicado sobre a versão anterior 01..18 sem recriar suas tabelas. A nova suíte verifica a divisão de R$ 10,00 em R$ 3,00/R$ 7,00, mudanças futuras de taxa, snapshots e datas imutáveis, meses vazios, virada de mês em São Paulo, exclusão de simulações/estornos e permissões.
- **PHP:** 68 verificações passaram, incluindo os novos limites de ano e percentual de comissão. As verificações finais de sintaxe passaram em 31 arquivos PHP/JavaScript.
- **MongoDB 8.0:** 20 verificações novas de comissão e agregação mensal passaram sobre coleções reais, usando Auth de teste. Incluem o exemplo 30/70, histórico preservado, confirmação idempotente, doze meses, limites, permissões e a virada local de mês às 03:00 UTC.
- **Interface administrativa:** 41 verificações com respostas de API controladas passaram em 1440 e 390 pixels, incluindo as três páginas, filtros/histórico, aprovação e rejeição, ano, tabela, gráfico, CSV, alteração de taxa e estados de erro. Não houve erros JavaScript não tratados. As capturas foram inspecionadas: a marca está como Movee e o gráfico/tabela têm rolagem interna no celular.
- **Regressão da interface:** os fluxos anteriores de solicitação, rotas, conferência de veículo, oito abas administrativas e vinte combinações de página/tamanho continuaram passando no teste com API controlada.

Testes de navegador com dados controlados não representam um pagamento real nem cadastro remoto. As pendências externas da seção 8 continuam válidas. O gráfico representa receita de comissões confirmadas antes de custos e impostos, e o valor destinado aos entregadores não confirma transferência bancária automática.

## 11. Confirmação obrigatória e pacotes finais separados

- Instalação final do PostgreSQL17 feita do zero: **20 scripts e seis suítes SQL passaram**. O script20 também foi aplicado sobre01..19 e as seis suítes continuaram passando.
- Backend: **30 novas verificações de confirmação passaram**, além das68 anteriores. Foram exercitados login/sessão/renovação de usuário não confirmado, metadata e telefone sem valor de prova, revalidação canônica, token hash inválido/expirado, OTP alternativo, recuperação, CSRF e configuração indevida de sessão automática no cadastro.
- Interface: **34 verificações de confirmação com API controlada passaram**, em1440/390, incluindo outro dispositivo sem e-mail em sessão, limpeza da URL, ausência de consumo por GET, ação explícita, reenvio, login bloqueado, recuperação, OTP e SMS. A regressão pública real sem credenciais passou em255 verificações.
- MongoDB8: os55 testes de fluxo, os20 de rendimentos e as duas disputas concorrentes continuaram passando com a verificação de identidade confirmada no adaptador. Auth e provedores permaneceram substituídos por fixtures nesses testes de domínio.
- A conferência dos contratos não encontrou tabelas ou RPCs da API ausentes nos scripts PostgreSQL ou no adaptador MongoDB.
- A entrega foi separada em site e banco. Os arquivos devem ser extraídos no mesmo local, combinando a pasta Movee. Banco contém scripts numerados, SQL consolidado, MongoDB, dados de testes separados e guia de execução.

Não foi executado envio real de e-mail, abertura de caixa de entrada, confirmação no projeto Supabase remoto nem configuração SMTP. Para isso, é necessário habilitar Confirm email, copiar os templates e configurar o provedor conforme EMAIL-CONFIRMACAO.md. O bloqueio usa o estado canônico retornado pelo Auth e depende dessa configuração obrigatória do serviço.
