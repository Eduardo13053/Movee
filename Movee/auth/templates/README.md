# Modelos de e-mail do Supabase Auth

Os arquivos desta pasta são modelos para colar no painel Supabase. Eles não enviam e-mails por conta própria. O envio depende da configuração real do Supabase Auth e do provedor de e-mail.

## 1. Ativar confirmação obrigatória

No painel Supabase, abra **Authentication → Providers / Sign In → Email** e habilite **Confirm email**. Os nomes exatos dos menus podem variar na versão do painel. A confirmação deve estar ativada antes de liberar cadastros. O backend da Movee recusa uma sessão de cadastro emitida automaticamente sem o fluxo de confirmação esperado e exige o sinal canônico de e-mail confirmado do Auth para acesso protegido.

## 2. Configurar a URL confiável do site

Em **Authentication → URL Configuration**, defina **Site URL** com a mesma origem usada em `APP_URL` no `.env` privado do servidor, sem uma barra final. Exemplo de desenvolvimento: `http://127.0.0.1:8080`. Em produção, use a URL HTTPS correta.

Cadastre somente as URLs de retorno legítimas da sua instalação. O modelo usa `{{ .SiteURL }}` configurado pelo responsável; o visitante não escolhe esse endereço. `verificar.html` precisa ser servido pelo site PHP na mesma origem da API.

## 3. Configurar o modelo de confirmação

Em **Authentication → Email Templates → Confirm signup**, substitua o conteúdo HTML pelo arquivo `confirmar-cadastro.html`. Sugestão de assunto: **Confirme seu e-mail — Movee**.

Preserve literalmente as variáveis Go Template `{{ .SiteURL }}`, `{{ .TokenHash }}` e `{{ .Token }}`. O link principal aponta para:

```text
{{ .SiteURL }}/verificar.html?token_hash={{ .TokenHash }}&type=signup
```

No HTML do arquivo, o separador de parâmetros aparece como `&amp;`, que é a codificação HTML correta de `&`. O código `{{ .Token }}` permanece como alternativa de confirmação na página do site.

## 4. Configurar a recuperação de senha

Em **Authentication → Email Templates → Reset password / Recovery**, use `recuperar-senha.html`. Sugestão de assunto: **Recupere seu acesso — Movee**. O link usa `type=recovery`; não troque esse valor pelo tipo de cadastro. O código de recuperação também é mantido como alternativa.

## 5. Configurar o envio real

Configure o SMTP do Supabase com remetente e domínio autorizados. Confira os limites do provedor, a lista de destinatários permitidos quando aplicável e a entrega na caixa de entrada/spam. A chave de um provedor de mensagens da aplicação, como Resend, não substitui essa configuração do **Auth**. Nunca coloque senha SMTP ou chaves privadas dentro destes modelos ou em `public/`.

## 6. Validar o fluxo no projeto instalado

Crie uma conta de teste, verifique que o login é bloqueado antes da confirmação e abra a mensagem recebida. O link funciona em outro dispositivo sem depender de `sessionStorage` ou de informar o e-mail na URL. A página solicita uma ação explícita antes de enviar o token ao backend; a simples abertura da URL por uma prévia de e-mail não deve consumir a confirmação.

Confirme o e-mail, teste o login e tente reutilizar o link. Verifique também a mensagem de link inválido/expirado, o reenvio e o código alternativo. Para recuperação, confirme o link/código e só então envie a nova senha.

Os testes locais de interface ou de backend com respostas controladas não comprovam o recebimento de uma mensagem real. O recebimento só pode ser verificado depois de configurar o provedor e executar este fluxo na instalação final.
