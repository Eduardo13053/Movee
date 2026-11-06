# Movee — colocar os arquivos no GitHub

## 1. Prepare a pasta completa

Baixe `Movee-site-GitHub.zip` e `Movee-Supabase-GitHub.zip`. Extraia os dois no mesmo destino, mantendo a pasta superior `Movee` de ambos. Confira que `public/`, `src/`, `bin/`, `auth/`, `sql/`, `docs/`, `.gitignore`, `.env.example`, `README.md` e `ORDEM-DO-BANCO.md` estão juntos.

Os ZIPs são pacotes de transporte. Para o GitHub apresentar os arquivos do projeto, envie o conteúdo extraído.

## 2. Confira o que será publicado

Envie o modelo `.env.example`, com os campos de segredo vazios, e o arquivo `.gitignore`. Arquivos cujo nome começa com ponto podem ficar ocultos no explorador; habilite a exibição desses arquivos.

Mantenha o `.env` preenchido, arquivos de sessão/documentos locais, logs e a pasta `var/` fora do repositório. No envio pelo navegador, selecione somente os arquivos permitidos: o navegador não aplica automaticamente as exclusões de `.gitignore` ao formulário de upload.

## 3. Envie pelo navegador

1. Entre em sua conta no GitHub e crie um repositório, por exemplo `movee`.
2. Escolha a visibilidade desejada e abra a opção **uploading an existing file** ou **Add file → Upload files**.
3. Abra a pasta `Movee` extraída e arraste os arquivos e pastas de seu conteúdo para o formulário. Assim `README.md` e `public/` ficarão na raiz do repositório.
4. Confira que `.gitignore`, `.env.example`, `src/` e `sql/` foram incluídos. Adicione os arquivos ocultos separadamente se necessário.
5. Escreva uma mensagem, por exemplo `Adicionar site Movee e banco Supabase`, e conclua em **Commit changes**.
6. Confira na página do repositório que o código aparece em pastas e que nenhuma credencial foi enviada.

Não é necessário instalar VS Code para esse envio.

## 4. Alternativa pelo Git no terminal

Crie um repositório vazio no GitHub e substitua `SEU-USUARIO` e `SEU-REPOSITORIO` pela URL real. Na pasta `Movee` já combinada:

```sh
git init
git branch -M main
git add .
git status --short
git commit -m "Adicionar site Movee e banco Supabase"
git remote add origin https://github.com/SEU-USUARIO/SEU-REPOSITORIO.git
git push -u origin main
```

Antes do commit, confirme em `git status` que o `.env` e `var/` não aparecem. A autenticação do GitHub é feita pelos mecanismos do Git/GitHub; não coloque tokens em arquivos do projeto ou na URL versionada.

## 5. Instale e publique o site

O upload do código no GitHub não executa o SQL nem configura os serviços. Siga `ORDEM-DO-BANCO.md` e `docs/INSTALACAO.md` para configurar Supabase, Auth, SMTP e o servidor PHP.

**GitHub Pages serve arquivos estáticos e não executa PHP.** Para o site completo, utilize hospedagem compatível com PHP 8.2+, HTTPS e raiz pública apontada para `public/`. Configure as variáveis de ambiente diretamente na hospedagem, sem publicá-las no repositório.
