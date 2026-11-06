# Operação e segurança

## Publicação PHP

Publique somente `public/` como document root. Mantenha `.env`, `src/`, `bin/`, `sql/`, `var/` e backups fora da raiz HTTP. O servidor embutido do PHP é destinado a desenvolvimento. Em produção, use servidor compatível com PHP 8.2+, HTTPS, certificados válidos, permissões restritas e `display_errors=Off`.

Transfira para o servidor de produção os cabeçalhos de segurança aplicados por `router.php`/`Security.php` quando arquivos estáticos forem servidos diretamente por Nginx ou Apache. Configure o tamanho máximo de upload em todas as camadas. Não habilite CORS amplo para tentar contornar CSRF. `APP_URL` deve corresponder exatamente à origem publicada.

A sessão usa cookie HttpOnly, SameSite e atributo Secure quando a URL é HTTPS. O navegador não recebe tokens do Supabase em armazenamento persistente. A API confere CSRF e origem; parâmetros de tabela, coluna, operação e RPC passam por listas permitidas. O banco aplica RLS e verificações de negócio novamente.

Os limites locais de acesso são armazenados em `var/rate/` com bloqueio de arquivo, usando o endereço remoto observado pelo servidor. Se houver proxy reverso, configure a infraestrutura com cuidado; não confie em cabeçalhos encaminhados arbitrários enviados pelo cliente. Revise retenção desses arquivos operacionais e proteja o diretório contra acesso HTTP.

## Primeiro administrador

1. O responsável cria uma conta pelo **Cadastro de administrador**.
2. Confirma o e-mail e envia a identidade por upload autenticado.
3. Um operador autorizado de infraestrutura acessa o projeto Supabase/Storage pelo painel administrativo e **confere manualmente o documento e a identidade do responsável**.
4. O operador localiza o UUID correto em Auth/Users e executa no servidor:

```sh
php bin/bootstrap-admin.php UUID_DA_CONTA
```

O comando usa a chave de serviço no servidor. A função bloqueia bootstrap quando já existe administrador, exige cadastro administrativo, e-mail confirmado e documento, e registra aprovação/histórico/auditoria. O operador deve executar o comando somente após a conferência manual; a presença de arquivo não comprova identidade.

Não há senha administrativa padrão. O endereço corporativo recebe avisos, mas não é critério de privilégio. Depois do primeiro administrador, use a fila protegida de aprovação. A pessoa não pode aprovar a própria solicitação. Decisões exigem motivo e ficam registradas.

## Documentos e revisão

O bucket `movee-documents` permanece privado. Arquivos permitidos: JPEG, PNG e PDF até 5 MB; o servidor confere MIME/conteúdo. Administradores analisam os documentos e registram verificação ou rejeição. Corrigir um cadastro rejeitado exige reenviar os itens solicitados e submeter novamente quando permitido pelo fluxo.

Documentos e veículos já aprovados podem exigir nova análise após alteração. Não modifique o estado pelo SQL para contornar as regras usuais. Uma conta rejeitada/suspensa não deve aceitar entregas. Consulte as verificações do banco e `TESTES.md` para as evidências executadas.

URLs assinadas são temporárias e devem ser usadas somente para conferência. Evite copiá-las para suporte, e-mail ou logs. Formato válido não significa conteúdo autêntico nem varredura antivírus completa; antes de uso comercial, acrescente o serviço de análise de arquivos exigido pela política da organização.

## Notificações e e-mail

Configure SMTP no Supabase para mensagens de Auth. Para mensagens da aplicação, configure `RESEND_API_KEY`, `MAIL_FROM` com domínio/remetente autorizado e `ADMIN_NOTIFICATION_EMAIL` no servidor. O destinatário inicial é `MoveeEntregas@gmail.com`.

Execute a fila:

```sh
php bin/process-outbox.php
```

Agende a execução, por exemplo a cada minuto. O worker reivindica itens da fila com controle de concorrência, envia pelo provedor e registra sucesso/falha para novas tentativas. Monitore itens pendentes, falhas recorrentes e limites do provedor. Um registro na fila comprova a intenção de envio; o recebimento final depende do serviço e do destinatário.

Os avisos de aprovação direcionam para `/admin.html`. O destinatário ainda precisa entrar com uma conta administrativa autorizada. Não inclua documento ou dados pessoais completos no corpo desses avisos.

## Mercado Pago

No modo real, configure:

- `PAYMENT_MODE=live`.
- `MERCADOPAGO_ACCESS_TOKEN` no servidor.
- `MERCADOPAGO_WEBHOOK_SECRET` correspondente ao aplicativo do provedor.
- `APP_URL` com HTTPS público.

A URL de notificação é `APP_URL/api/webhook.php`. Registre-a e configure o segredo no painel Mercado Pago. Teste com as credenciais/contas de teste do provedor antes de usar credenciais produtivas.

O backend inicia o checkout hospedado. O webhook valida assinatura, consulta o pagamento no provedor e confere entrega de referência, valor e BRL antes de registrar a confirmação idempotente. O retorno do navegador à página de pagamentos não altera o estado por conta própria. Não aceite uma captura de tela ou parâmetro `status=approved` como confirmação financeira.

Em `PAYMENT_MODE=demo`, o sistema grava a marcação demonstrativa e não cobra dinheiro. A chave de serviço usada nessa rotina não deve aparecer em nenhuma resposta da API. Nenhum número completo de cartão ou CVV é coletado pelo Movee.

## LGPD e retenção

As páginas de termos e privacidade informam a finalidade do cadastro, a verificação documental e os dados necessários às entregas. Antes de utilização comercial, o controlador deve revisar os textos, identificar sua organização, contatos, base legal, prazos e procedimentos de atendimento aos titulares. O material técnico não substitui essa decisão organizacional.

A configuração inicial de retenção documental é de **180 dias**, ajustável por `DOCUMENT_RETENTION_DAYS`, com mínimo técnico de 30 dias. A rotina entregue seleciona documentos rejeitados mais antigos que o prazo, em lotes de até 100; documentos ativos/aprovados não são removidos automaticamente. Revise o prazo conforme finalidade, obrigação legal e necessidade de defesa de direitos. Antes da exclusão, confirme se existem entregas em andamento, investigação, obrigação de conservação ou outra razão documentada para manter o dado.

Execute primeiro `php bin/retention.php` para consulta sem remover arquivos. Examine os candidatos antes da execução. O comando de remoção é:

```sh
php bin/retention.php --execute
```

A exclusão em Storage e banco precisa ser acompanhada por registro de auditoria. Guarde backups de forma restrita e alinhe seus próprios prazos de retenção; apagar o objeto ativo não apaga automaticamente cópias de backup externas. Não agende uma remoção irreversível sem revisar os critérios implementados no comando.

Pedidos de acesso, correção e exclusão podem ser abertos pela central de ajuda. O responsável confirma a identidade do solicitante e verifica quais registros podem ser removidos e quais precisam ser retidos. Não exponha dados de terceiros no atendimento.

## Rotina recomendada

| Frequência | Verificação |
|---|---|
| Após instalar/alterar configuração | Cadastro, confirmação, login, upload e autorização com contas distintas. |
| A cada execução da fila | Quantidade de itens pendentes/falhos, erros do provedor e tentativas. |
| Diária | Solicitações de aprovação, suporte, pagamentos divergentes e entregas com atraso/ocorrência. |
| Periodicamente | Documentos vencidos, usuários suspensos, retenção, acesso dos administradores e restauração de backup. |
| Antes de publicar nova versão | Testes de preço, capacidade, concorrência, RLS/isolamento e fluxos de autenticação. |

Não registre senhas, tokens, chaves, números de documentos completos ou URLs assinadas nos logs. Em caso de exposição de uma credencial privilegiada, revogue e substitua a chave afetada, revise os logs e encerre os acessos que dependerem dela.

## Links de confirmação

O site valida o token de confirmação somente após ação explícita da pessoa. A página `verificar.html` remove o token da URL antes de suas chamadas de API, usa `no-referrer` e é servida pelo router com `Cache-Control: no-store, private`. Na hospedagem que serve HTML diretamente, aplique esses mesmos cabeçalhos nessa página e evite registrar o parâmetro `token_hash` em logs. O link é uma credencial temporária de uso único do Supabase Auth.
