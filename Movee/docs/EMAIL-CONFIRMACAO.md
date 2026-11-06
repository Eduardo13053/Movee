# Confirmação obrigatória de e-mail — configuração e uso

## 1. O que este fluxo exige

O cadastro inicia uma solicitação no Supabase Auth. O usuário recebe um e-mail, abre o link e seleciona **Confirmar meu e-mail** na página do Movee. Somente uma resposta válida do Supabase permite iniciar a sessão da conta. O código numérico do mesmo e-mail permanece disponível como alternativa.

O backend verifica o campo oficial `email_confirmed_at` devolvido pelo Supabase Auth antes de aceitar o login, renovar uma sessão ou permitir operações protegidas. Um campo enviado no formulário, em metadata ou em um parâmetro de URL não serve como confirmação. A aplicação não mantém uma segunda tabela de senhas nem uma confirmação paralela controlada pelo navegador.

O requisito é aplicado à entrada na conta e às operações protegidas. Caso a conta também tenha escolhido SMS, a confirmação inicial do e-mail ocorre antes da confirmação complementar do telefone.

## 2. Preparar os dois arquivos da entrega

Os dois ZIPs têm uma pasta principal chamada `Movee`. Extraia os dois no mesmo local, mesclando essa pasta. O pacote do site fornece `public/`, `src/`, `bin/`, `auth/` e `.env.example`; o pacote do banco acrescenta `sql/`, `mongodb/`, os modelos completos e `ORDEM-DO-BANCO.md`. Abra a pasta `Movee` no Visual Studio Code e siga a ordem numerada do banco. Os scripts não precisam ser publicados no servidor web.

A variante Supabase usa PostgreSQL, Supabase Auth e Storage. A variante MongoDB substitui a persistência dos dados de domínio, mas continua usando Supabase Auth e Storage. Configure a confirmação de e-mail no Supabase em ambas as alternativas.

## 3. Configurar a origem do site e as credenciais

Copie `.env.example` para `.env` na raiz do site, fora de `public/`, e configure:

```dotenv
APP_URL=http://127.0.0.1:8080
APP_KEY=CHAVE_ALEATORIA_GERADA_LOCALMENTE
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_PUBLISHABLE_KEY=CHAVE_PUBLICAVEL_DO_PROJETO
SUPABASE_SERVICE_ROLE_KEY=CHAVE_PRIVADA_DE_SERVICO_SOMENTE_NO_SERVIDOR
```

Gere a `APP_KEY` com o comando indicado em `.env.example`. Substitua os exemplos; eles não são credenciais funcionais. Em produção, use a origem HTTPS real em `APP_URL`. A chave de serviço é necessária para os serviços privados da plataforma e nunca deve ser colocada em HTML ou JavaScript.

No Supabase, configure **Authentication → URL Configuration**:

1. **Site URL:** a mesma origem de `APP_URL`, sem barra final. Exemplo de desenvolvimento: `http://127.0.0.1:8080`.
2. **Redirect URLs:** inclua as páginas de verificação autorizadas da instalação, como `http://127.0.0.1:8080/verificar.html` e a equivalente de produção. Se a configuração exigir padrão para os parâmetros da recuperação, restrinja-o à página de verificação da sua própria origem.
3. Evite alternar entre `localhost` e `127.0.0.1` sem alterar a configuração; são origens diferentes para sessão e CSRF.

## 4. Ativar a confirmação no Supabase Auth

Em **Authentication → Providers / Sign In → Email** — o nome da seção pode variar conforme a versão do painel — habilite o provedor de e-mail e a opção **Confirm email**.

Essa opção é obrigatória. O cadastro não deve confirmar contas automaticamente. Se o Supabase devolver uma sessão imediatamente no cadastro, o Movee trata a situação como configuração incompatível e não aceita essa sessão como confirmação por e-mail.

A configuração do provedor faz parte da instalação: o código entregue não pode ativar remotamente esse recurso sem acesso administrativo ao seu projeto. Revise também limites de envio, expiração dos códigos/links e limites de tentativas disponíveis no Auth.

## 5. Configurar o envio real por SMTP

Configure um serviço SMTP autorizado na seção de SMTP do Supabase Auth. Informe remetente, domínio, host, porta, usuário e senha conforme seu provedor. As credenciais SMTP ficam no painel do Supabase; não são colocadas no navegador.

O envio padrão de desenvolvimento do Supabase pode ter limites e destinatários permitidos. Para validar com usuários reais, use o SMTP configurado e confira logs de Auth e do provedor. Uma chamada de cadastro aceita não comprova a entrega na caixa de entrada. Confira também spam, quota, domínio verificado e autenticações de domínio exigidas pelo provedor.

As mensagens de confirmação e recuperação são do **Supabase Auth**. A fila de notificações da aplicação e o provedor Resend configurado em outras partes do projeto são serviços distintos; configurar somente o worker de notificações não configura os e-mails de Auth.

## 6. Copiar o modelo de confirmação de cadastro

Abra o arquivo do site:

```text
auth/templates/confirmar-cadastro.html
```

Copie seu conteúdo para o template **Confirm signup / Confirmação de cadastro** do Supabase Auth e salve. O botão aponta para a página do Movee com a prova de confirmação de uso único:

```html
<a href="{{ .SiteURL }}/verificar.html?token_hash={{ .TokenHash }}&amp;type=signup">
  Confirmar meu e-mail
</a>
```

O modelo também inclui `{{ .Token }}` para permitir o código alternativo. As expressões entre chaves são variáveis do Supabase: não as substitua manualmente por um código fixo.

Neste fluxo, o link principal leva primeiro à página do Movee; a confirmação ocorre após o clique no botão da página. Usar somente `{{ .ConfirmationURL }}` cria um caminho diferente, que pode consumir a confirmação diretamente no endereço padrão do Supabase antes da tela do aplicativo. Para reproduzir o fluxo entregue, utilize o modelo fornecido com `TokenHash`.

O `Site URL` vem da configuração confiável do projeto. Não monte links a partir de um domínio arbitrário informado pelo visitante. Não copie o link de confirmação para suporte ou logs: ele contém uma prova de uso único. Configure a hospedagem para ocultar o parâmetro `token_hash` nos logs HTTP e mantenha essa página fora de rastreamento por ferramentas de analytics.

## 7. Configurar a recuperação e o SMS

Quando houver template de recuperação junto aos modelos entregues, copie-o para **Reset password / Recuperação de senha**. O caminho de recuperação usa a mesma página, com `type=recovery`. O código `{{ .Token }}` permanece uma alternativa compatível com a tela de verificação.

Depois que o Supabase validar o link ou código de recuperação, o usuário poderá escolher uma senha nova na janela de recuperação autorizada pelo backend. Informar apenas um e-mail, um parâmetro `type=recovery` ou uma senha nova não concede essa autorização.

Para SMS, configure um provedor suportado em Supabase Auth e só então habilite `SMS_ENABLED=true` no `.env`. O telefone é confirmado depois do e-mail. Sem provedor SMS configurado, a plataforma não inventa um código válido.

## 8. Usar a confirmação

1. Faça o cadastro com um endereço de e-mail ao qual tenha acesso.
2. A tela orientará a abrir a mensagem recebida. Nenhuma sessão de conta é criada apenas pelo envio do formulário.
3. Abra o link **Confirmar meu e-mail** da mensagem.
4. Na página do Movee, selecione o botão de confirmação. A API envia o `token_hash` ao Supabase, que valida a prova e sua validade.
5. Após a validação, conclua o perfil e os documentos. Quando aplicável, siga a confirmação complementar por SMS.
6. Nos próximos acessos, use e-mail e senha normalmente.

O link pode ser aberto em outro navegador/dispositivo: ele não depende de um e-mail retido em `sessionStorage`. O segredo da URL é mantido apenas em memória na página e retirado da URL visível; não é salvo como token de acesso no navegador.

A página não confirma a conta automaticamente em um simples GET. Isso reduz o risco de um verificador de links de e-mail consumir a prova antes do usuário. A confirmação exige a ação explícita na página e a validação do serviço.

Links inválidos, usados ou expirados não iniciam a sessão. Use o reenvio disponível para solicitar uma nova mensagem. Se a conta já foi confirmada, volte à página de login. Não há código universal de teste aceito como confirmação.

## 9. Executar o banco em ordem

Para instalação PostgreSQL/Supabase nova, execute os scripts de produção **01 a 20**, conforme o guia numerado do pacote do banco. O script 20 reforça a exigência de e-mail confirmado nas políticas e operações protegidas.

Se a versão anterior já possui 01..19, execute somente o **20**. Se possui apenas 01..18, aplique **19 e depois 20**. Não recrie as tabelas existentes para aplicar esta atualização. Testes e dados fictícios estão separados dos scripts de produção.

Na alternativa MongoDB, siga o inicializador e a ordem próprios do pacote do banco. Não execute os SQL de domínio PostgreSQL nessa alternativa. O adaptador PHP exige confirmação no Auth antes de provisionar/usar o perfil de uma sessão comum; não cria senhas em coleções.

## 10. Validar após a configuração

1. Cadastre uma conta nova e tente entrar antes da confirmação: o acesso à conta deve ser recusado.
2. Abra a página de um link sem clicar na confirmação: a conta não deve ser confirmada apenas pela abertura.
3. Confirme pelo link e confira que a entrada passa a funcionar.
4. Teste um link incorreto, um link já usado e um link expirado; solicite reenvio.
5. Confirme em outro dispositivo, sem estado anterior do cadastro.
6. Teste a alternativa por código, a recuperação e o SMS quando estiver configurado.
7. Tente acessar dados ou operações protegidas com uma sessão não confirmada; o backend/banco devem bloquear.
8. Repita os testes de cliente, vendedor, entregador e administrador, mantendo aprovações documentais e permissões específicas de cada papel.

Os resultados efetivamente executados localmente são registrados em `TESTES.md`. Não foram fornecidas credenciais de SMTP/Supabase remoto nesta entrega; por isso, o recebimento real do e-mail, quotas e links do seu domínio precisam ser verificados na sua instalação. Não se declara envio real de mensagens sem essa execução.

Em desenvolvimento, `127.0.0.1` só funciona no dispositivo que está executando o servidor. Para confirmar por um telefone ou outro computador, configure `APP_URL`/Site URL com uma origem acessível por esse dispositivo, preferencialmente HTTPS público. A confirmação continua exigindo o token real do e-mail.
