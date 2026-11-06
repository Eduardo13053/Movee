# Instalação do zero

Este guia trata da configuração PostgreSQL/Supabase incluída nos dois pacotes para GitHub.

## 1. Extrair e abrir o projeto

Extraia **Movee-site-GitHub.zip** e **Movee-Supabase-GitHub.zip** no mesmo local, preservando a pasta superior `Movee` de ambos. O primeiro traz PHP/HTML/CSS/JS e modelos de e-mail; o segundo traz `sql/`, o banco por extenso e `ORDEM-DO-BANCO.md`. Abra a pasta `Movee` em qualquer editor e use um terminal nessa pasta; VS Code é opcional. Para enviar os arquivos extraídos ao GitHub, siga `docs/GITHUB.md`.

Não abra `index.html` por `file://`. As operações precisam da API PHP na mesma origem. A extensão Live Server, isoladamente, serve arquivos estáticos e não executa PHP.

## 2. Preparar PHP

Use PHP 8.2 ou superior. No Windows, uma distribuição atual do PHP ou ambiente como Laragon/XAMPP pode ser usado desde que a versão e extensões sejam compatíveis. No macOS/Linux, instale pelos meios usuais do sistema. Confirme:

```sh
php -v
php -m
```

Habilite `openssl`, `fileinfo`, `mbstring` e suporte JSON. cURL é recomendado; o cliente HTTP também pode usar streams HTTPS quando `allow_url_fopen` estiver habilitado. Mantenha a validação de certificados TLS ativa.

No `php.ini` de desenvolvimento, permita arquivos de até 5 MB e requisições um pouco maiores, por exemplo `upload_max_filesize=5M` e `post_max_size=8M`. O backend aplica seu próprio limite e valida o conteúdo. O processo PHP deve poder criar/escrever em `var/` para limites de acesso e rotinas locais; esses dados ficam fora de `public/`.

## 3. Criar o projeto Supabase

Crie um projeto novo no painel Supabase. Escolha região e senha de banco fortes, guarde a senha em um gerenciador e aguarde o provisionamento. Não reutilize a URL ou chave publicável do arquivo original recebido: a entrega foi planejada para banco vazio.

Nas configurações de API do projeto, copie a **Project URL** e a chave **publishable** (ou chave pública legada `anon` correspondente). A chave privilegiada `service_role` fica na área de chaves/API do projeto. Os nomes do painel podem variar; confira a classificação da chave antes de copiá-la. Uma chave publicável e uma chave de serviço têm permissões muito diferentes.

## 4. Executar o SQL de produção

Abra o **SQL Editor** do projeto Supabase. Na pasta `sql/` do pacote do banco, execute os 20 arquivos de produção numerados da raiz, um por vez, de 01 a 20 em ordem numérica crescente. O mapa completo dos arquivos e dependências está em `DATABASE.md`.

Para cada arquivo:

1. Abra o arquivo completo no editor local.
2. Copie seu conteúdo inteiro para uma consulta nova no SQL Editor.
3. Execute e confirme sucesso antes de continuar.
4. Se houver erro, interrompa a sequência e corrija a causa. Não pule arquivos nem execute só parte de uma transação.

Os scripts foram escritos para um projeto novo. Reexecutar uma criação que já foi concluída pode acusar objeto existente; não apague objetos de um projeto em uso para tentar instalar novamente. Utilize outro projeto vazio quando desejar reinstalar para testes.

Arquivos em diretórios de **testes** e **demonstração** são separados da instalação. Leia suas instruções antes de executar. Dados fictícios não devem entrar automaticamente em produção. Os esquemas `auth` e `storage` são os padrões fornecidos pelo Supabase, não tabelas legadas do Movee.

## 5. Configurar o ambiente PHP

Copie `.env.example` para `.env` na raiz. No terminal Unix:

```sh
cp .env.example .env
php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
```

No Windows, use `Copy-Item .env.example .env` no PowerShell e execute o comando PHP equivalente para gerar a chave. Cole o valor gerado em `APP_KEY`.

Use `.env.example` como referência completa dos nomes aceitos. Configure pelo menos:

| Variável | Valor |
|---|---|
| `APP_URL` | `http://127.0.0.1:8080` no desenvolvimento; URL HTTPS exata em produção. |
| `APP_KEY` | Segredo aleatório de pelo menos 32 caracteres. |
| `SUPABASE_URL` | URL do novo projeto. |
| `SUPABASE_PUBLISHABLE_KEY` | Chave publicável/anon do mesmo projeto. |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave privilegiada, exclusivamente no servidor; necessária às rotinas de serviço. |
| `PAYMENT_MODE` | `demo` para apresentação identificada; `live` somente com o provedor configurado. |

Não coloque credenciais em HTML, JavaScript, imagens, SQL versionado ou capturas de tela. O `.env` fica fora de `public/` e não deve ser enviado ao Git. Se o servidor oferece variáveis de ambiente, elas têm precedência sobre o arquivo local.

## 6. Configurar Supabase Auth

Em Authentication → Providers → Email, habilite o provedor e mantenha **Confirm email ativado**. Configure **Site URL** exatamente igual a `APP_URL`, além das URLs permitidas de redirecionamento. No template **Confirm signup**, copie o conteúdo integral de `auth/templates/confirmar-cadastro.html`. Ele envia um botão para `{{ .SiteURL }}/verificar.html?token_hash={{ .TokenHash }}&type=signup` e também inclui `{{ .Token }}` como alternativa por código. No template **Reset password**, use `auth/templates/recuperar-senha.html`. Consulte o guia numerado `EMAIL-CONFIRMACAO.md`.

A pessoa precisa abrir o e-mail e clicar em **Confirmar meu e-mail** na página de destino; a simples abertura automática do link não consome o token. O backend valida a confirmação canônica do Auth antes de aceitar login ou operação protegida. Se o cadastro retornar sessão automática, o site informa que a configuração de confirmação precisa ser corrigida. Não substitua os templates entregues por um link padrão que devolva access tokens ao navegador.

Configure SMTP próprio em Auth para envio confiável a destinatários reais. O serviço padrão do Supabase pode impor restrições e limites de teste. Configure remetente, host, porta, usuário e senha no painel do Supabase; a senha SMTP não pertence ao JavaScript do Movee.

Mantenha limites de tentativas no Supabase e revise as opções de proteção disponíveis no plano. O backend também aplica limites de requisições. Use senhas com os requisitos apresentados na interface; nenhuma senha é gravada no banco de domínio.

### Confirmação por SMS

Configure um provedor SMS suportado na seção Phone/Auth do Supabase, com suas credenciais, remetente e limites. Só então habilite a opção correspondente no `.env`, conforme `.env.example`.

O fluxo de cadastro mantém e-mail e senha como forma de entrada. A opção SMS inclui a confirmação inicial necessária de e-mail e a vinculação/confirmação do telefone pelo código enviado ao número. Conclua as telas de verificação exibidas. Desabilitar a interface SMS não configura um provedor automaticamente; um número de teste ou código fixo não deve ser usado como confirmação real fora das ferramentas de teste do provedor.

## 7. Configurar Storage privado

As migrações criam/configuram o bucket privado `movee-documents`. O acesso a arquivos ocorre pelo backend com credencial de serviço, após autenticar e autorizar o usuário; não há permissão direta de upload/leitura para anon/authenticated. Confira no Storage que o bucket **não está público**. Não altere para público para resolver um erro de upload.

São aceitos JPEG, PNG e PDF, com limite de 5 MB. O cadastro pede documento oficial com foto; o entregador também envia CNH e documento do veículo. O envio acontece depois de entrar, na conclusão do perfil e na gestão de veículos. Arquivos ficam vinculados ao usuário; administradores autorizados acessam por URL assinada de curta duração.

## 8. Iniciar

Na raiz:

```sh
php -S 127.0.0.1:8080 -t public router.php
```

Abra `http://127.0.0.1:8080`. Use a mesma origem em `APP_URL`; alternar entre `localhost` e `127.0.0.1` sem ajustar a configuração pode ser bloqueado pela proteção de origem/CSRF. Atualize a página depois de alterar `.env`; reinicie o processo PHP quando necessário.

Sem configuração válida, a interface informa a necessidade de configuração e não cria contas ou entregas fictícias silenciosamente.

## 9. Configurar o primeiro administrador

Cadastre a conta destinada ao responsável pela opção Cadastro de administrador, confirme o e-mail, entre e envie o documento. Um operador de infraestrutura autorizado deve conferir manualmente a identidade e o arquivo no painel Supabase antes de executar o comando. Localize seu UUID em Authentication/Users no painel Supabase. No terminal do servidor:

```sh
php bin/bootstrap-admin.php UUID_DA_CONTA
```

Esse comando exige a chave privilegiada no servidor, verifica os requisitos definidos no banco e é destinado ao primeiro administrador. Leia a mensagem do comando e as regras em `OPERACAO-SEGURANCA.md`. Não existe promoção baseada só no endereço `MoveeEntregas@gmail.com`. Demais solicitações são analisadas no painel protegido e ficam auditadas.

## 10. E-mails da aplicação e fila

E-mails de Auth usam SMTP/Supabase Auth. Avisos da aplicação usam o provedor configurado no `.env.example` e a fila `outbox`. Configure a chave do provedor e um remetente autorizado. Execute:

```sh
php bin/process-outbox.php
```

Agende esse comando no servidor, por exemplo a cada minuto, depois de validar o envio. A solicitação administrativa gera aviso para `MoveeEntregas@gmail.com` com link ao painel protegido; o link não concede acesso sem autenticação e autorização.

## 11. Pagamentos

Em `demo`, o sistema registra uma operação identificada como demonstrativa, sem cobrar dinheiro e sem pedir número de cartão/CVV. A chave de serviço permanece somente no servidor para confirmar a operação demonstrativa autorizada.

Para Mercado Pago real, configure as variáveis de token e segredo de webhook indicadas em `.env.example`, selecione `PAYMENT_MODE=live` e use uma URL HTTPS publicamente acessível. Registre no painel do provedor a rota `APP_URL/api/webhook.php`. Use primeiro as credenciais e os meios de teste do próprio provedor. O checkout acontece na página hospedada do Mercado Pago; o retorno do navegador não é confirmação de pagamento. O backend valida a notificação, consulta a transação e verifica referência, moeda e valor antes de confirmar no banco.

A falta de credenciais não autoriza marcar um pagamento real como confirmado. Consulte `TESTES.md` para distinguir os testes locais dos que exigem o provedor externo.

## 12. Roteiro inicial de validação

Cadastre um cliente, confirme o canal, envie identidade, salve três endereços e tente um quarto. Cadastre um entregador, conclua CNH/veículo/documentos e analise com administrador. Solicite entrega com vários itens e unidades de peso, escolha veículo compatível, confira a cotação, conclua pagamento no modo escolhido e aceite a entrega pelo entregador. Avance os status, registre o recebedor e consulte comprovante/avaliação/notificações.

Faça as verificações negativas: acessar entrega de outra conta, alterar papel pelo navegador, escolher veículo pequeno, pular status, abrir documento sem autorização e aceitar simultaneamente a mesma entrega. A lista completa e as evidências disponíveis estão em `TESTES.md`.

## Rota real e parâmetros de frete

Configure `GEOAPIFY_API_KEY` no servidor para habilitar o cálculo real de rota. A chave não é enviada ao navegador. A rota calculada é persistida e vinculada à conta, categoria, endereços e prazo de validade; alterá-los exige calcular novamente. A administração pode ativar `route_required` para exigir a distância confiável. Sem a integração/exigência, a interface identifica a distância manual como estimativa do TCC. Não é GPS em tempo real nem cálculo automático de pedágio.

Os parâmetros administrativos incluem preço por litro, consumo de cada categoria, multiplicador de urgência e adicional de pico por dias/horários no fuso America/Sao_Paulo. Os valores iniciais são fictícios/configuráveis. Antes da coleta, o cliente confere modelo/placa do veículo designado; uma divergência abre ocorrência e não libera a coleta.
