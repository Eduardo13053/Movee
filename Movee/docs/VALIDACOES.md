# Validações dos campos do Movee

As regras principais ficam em `src/Validation.php` e `src/Fields.php`. O PHP valida antes de chamar qualquer adaptador de dados; portanto, elas se aplicam às variantes Supabase e MongoDB. Os formulários oferecem validação imediata e o PostgreSQL reforça integridade, permissões e concorrência. Nenhuma permissão administrativa depende de um campo enviado pelo navegador.

Os limites abaixo são de caracteres, salvo indicação. Campos opcionais aceitam texto vazio; valores obrigatórios não aceitam `null`, estruturas inesperadas ou ausência. O PHP recusa caracteres de controle e chaves desconhecidas nas mutações e nos argumentos dos RPCs. Textos são exibidos com escape HTML. A validação de formato de endereço ou telefone não comprova a existência física do endereço ou a titularidade do número.

| Campo | Regra do formulário/API | Persistência e proteção |
|---|---|---|
| Nome completo da conta | 4–140; pelo menos nome e sobrenome; letras Unicode, apóstrofo e hífen; sem números ou ponto | Nome capitalizado quando `mbstring` está disponível; partículas da/de/do/das/dos/e preservadas em minúsculas; SQL valida a mesma estrutura |
| E-mail | Sintaxe de e-mail válida; máximo 254 | Credenciais e confirmação pertencem ao Supabase Auth; não há senha em tabela de aplicação |
| Senha nova | 10–128; maiúscula, minúscula, número e símbolo; sem espaços | Supabase Auth armazena e protege a senha. Login aceita a senha existente, sem impor novamente requisitos de criação |
| Confirmação de senha | Deve coincidir exatamente com a senha | Usada no formulário; não é armazenada nem enviada como segundo segredo |
| CPF | 11 números, com os dois dígitos verificadores corretos; rejeita sequências repetidas; máscara é aceita na entrada | Normalizado sem pontuação; único em `profiles.cpf_cnpj`; obrigatório para cliente, entregador e solicitação administrativa |
| CPF ou CNPJ do vendedor | CPF válido **ou** CNPJ de 14 posições; CNPJ numérico e alfanumérico com 12 posições iniciais alfanuméricas e 2 dígitos verificadores | Normalizado para maiúsculas sem máscara; validação de CNPJ alfanumérico usa valor ASCII menos 48 e pesos oficiais; vendedor mantém papel operacional de cliente |
| Telefone | DDD brasileiro existente; fixo com 8 números iniciado em 2–5, ou celular com 9 números iniciado em 9 | API normaliza `+55`; SQL armazena os dígitos. Letras e símbolos fora da máscara são recusados. Confirmação SMS exige código real do Auth |
| Nascimento | Data civil real, entre 18 e 120 anos | Verificado no cadastro e atualização; o SQL também restringe o intervalo |
| Tipo de conta solicitado | `client`, `seller`, `driver` ou `admin` | É uma solicitação. Papel efetivo permanece `client` até aprovação quando necessária; não pode ser editado pelo usuário |
| Termos e privacidade | Aceite explícito `true` | Data de aceite registrada; não há caixa pré-marcada |
| Canal de confirmação | `email` ou `sms`; SMS só é selecionável quando configurado | Canal escolhido gravado no perfil. Para conta de acesso por e-mail, SMS requer primeiro confirmar e-mail e depois vincular/confirmar telefone. Pedidos exigem confirmação do canal correspondente |
| Código de confirmação | 6–128 caracteres alfanuméricos, `_` ou `-` | Validado pelo Supabase Auth, com limites locais de tentativas; nenhum código fictício é aceito |
| Justificativa administrativa/entregador | 10–2.000 | Solicitação pendente; aprovação exige administrador autorizado e documentos verificados; não permite autoaprovação |
| Decisão administrativa/documental | Somente estados previstos; motivo 3–2.000 | RPC verifica papel administrativo e registra auditoria/histórico |

## Endereços

| Campo | Regra |
|---|---|
| Identificação do endereço salvo | 2–40; por exemplo Casa, Trabalho ou personalizado |
| CEP | 8 dígitos, com hífen opcional na entrada; armazenado sem máscara |
| Rua | 2–200 |
| Número | 1–30; texto para permitir `s/n`, letras e complementos usuais de numeração |
| Complemento | Opcional, até 100 |
| Bairro e cidade | 2–100 cada |
| Estado | Uma das 27 siglas oficiais de UF, normalizada para maiúsculas |
| Ponto de referência | Opcional, até 250 |
| Principal | Booleano real; selecionar um principal desmarca o anterior |
| Quantidade de endereços | Até 3 por usuário; PostgreSQL bloqueia a linha do titular durante a operação, inclusive para requisições simultâneas |

Coleta e destino exigem CEP, rua, número, bairro, cidade e estado; não dependem da existência de um endereço salvo. Identificadores/titulares não podem ser trocados por parâmetros do formulário.

## Entregadores, veículos e documentos

| Campo | Regra |
|---|---|
| CNH | Exatamente 11 números |
| Categoria da CNH | A, B, AB, C, AC, D, AD, E ou AE |
| Validade da CNH | Data real, de hoje até aproximadamente 10 anos adiante; vencida bloqueia aprovação/aceite |
| Marca e modelo | 2–80 cada |
| Categoria do veículo | Identificador existente no catálogo; o servidor verifica o relacionamento |
| Placa | Padrão antigo `ABC1234` ou Mercosul `ABC1D23`; hífen opcional na entrada; letras maiúsculas, 7 posições armazenadas; bicicleta dispensa placa |
| Ano | 1980 até o ano atual mais 1 na API/formulário |
| Veículo ativo | Booleano real |
| Arquivo | JPEG, PNG ou PDF; mínimo 100 bytes, máximo 5 MB; assinatura MIME conferida pelo PHP; SVG/HTML/executáveis recusados |
| Imagem | Decodificação de dimensões válida; no máximo 15.000 pixels em cada eixo |
| PDF | Cabeçalho/final de PDF; conteúdo ativo evidente como JavaScript, Launch e anexos executáveis recusado |
| Nome/caminho de arquivo | Nome original ignorado; caminho com UUID do titular e nome aleatório gerado pelo servidor |
| Documento de veículo | Deve apontar para veículo do próprio usuário |
| Leitura e upload | Bucket privado sem leitura/escrita por JWT público; PHP usa chave de serviço após validar e autorizar. A consulta chama RPC de autorização/auditoria e gera URL assinada por 60 segundos |

A inspeção de formato não é uma certificação de autenticidade documental nem um antivírus completo. A decisão humana fica registrada. Alterações em CNH/veículos já aprovados exigem suporte/nova análise, conforme o estado do cadastro. Somente perfis aprovados e com documentação válida podem aceitar entregas.

## Solicitação, cotação e acompanhamento

| Campo | Regra |
|---|---|
| Itens por entrega | 1–30 |
| Descrição da mercadoria | 2–500 por item |
| Quantidade | Inteiro de 1 a 10.000 |
| Peso | Positivo e finito; unidade `mg`, `g`, `kg` ou `t`; peso unitário convertido entre 1 mg e 14 t |
| Conversões | 1 mg = 0,000001 kg; 1 g = 0,001 kg; 1 t = 1.000 kg. Peso informado é **por unidade**, multiplicado pela quantidade |
| Precisão | API aceita decimais com até 9 casas, sem NaN/Infinity; PostgreSQL usa `numeric`, peso padronizado em kg com 6 casas e volume total com 9 |
| Dimensões | Cada eixo maior que zero, de 0,001 até 10.000 cm na API; volume unitário = comprimento × largura × altura ÷ 1.000.000 m³ |
| Compatibilidade | Peso/volume totais e dimensões de cada item devem caber na categoria; servidor refaz o cálculo e impede veículo incompatível |
| Nome do destinatário | 3–160; não exige sobrenome, pois pode identificar recepção/portaria |
| Telefone do destinatário | Mesma validação brasileira de telefone |
| Agendamento | Data/hora real, de agora menos tolerância técnica de 5 minutos até aproximadamente 1 ano; interface envia data com fuso/UTC |
| Observações e instruções especiais | Opcionais, até 2.000 cada |
| Distância | Positiva, com até 3 casas persistidas; API recusa acima de 10.000 km. A configuração SQL inicial é mais restrita: **1.000 km**. É estimativa manual, sem alegação de rota/GPS real |
| Urgência e proteção | Booleanos reais; adicionais calculados pelo servidor |
| Serviços extras | Inteiro de 0 a 5; tarifa por serviço configurada no servidor |
| Pedágios | Não negativos; configuração inicial desabilitada e exige zero. Não se inventa uma cotação real de pedágio |
| Frete | Somente o backend/SQL calcula; campos de preço enviados pelo usuário são recusados na API. Tarifas iniciais são fictícias/configuráveis |
| Código de rastreio | 3–40; letras, números e hífen; convertido para maiúsculas. Código real gerado no banco: `MV-` e 12 caracteres hexadecimais |
| Mudança de status | Somente próxima etapa prevista; cliente só cancela nas fases autorizadas; entregador precisa estar designado e aprovado |
| Comprovante | Nome de quem recebeu 3–160, horário do servidor e observação até 2.000 |

## Pagamentos, suporte e administração

| Campo/operação | Regra |
|---|---|
| Método de pagamento | `pix`, `credit` ou `debit`, apresentado apenas na etapa/página de pagamento |
| Pagamento demonstrativo | Modo explícito; `is_demo=true`, sem movimentação de dinheiro; confirmação atômica por RPC exclusivo de serviço |
| Pagamento real | Checkout hospedado Mercado Pago; valor vem da entrega no servidor; não coleta PAN/CVV. Webhook exige assinatura HMAC, janela de 5 minutos, consulta autenticada ao provedor, moeda BRL, valor e referência correspondentes; confirmação idempotente |
| Avaliação | Nota inteira 1–5; comentário opcional até 1.000; uma avaliação por entrega concluída, feita pelo cliente vinculado |
| Suporte | Assunto 5–150; mensagem 10–4.000; entrega opcional deve pertencer ao solicitante; resposta administrativa até 4.000 |
| Status do suporte | `open`, `in_progress` ou `closed`; atualização somente administrativa |
| Nome da categoria | 2–100 |
| Descrição/proteção da categoria | Até 1.000 cada |
| Tarifas e adicionais | Números finitos não negativos, até 1.000.000 na API; somente administrador; `numeric` no SQL e auditoria da alteração |
| Capacidade configurável | Peso até 100.000 kg; volume até 1.000 m³; eixos até 10.000 cm; todos positivos |
| Paginação | `limit` inteiro 1–100, `offset` inteiro 0–1.000.000; ordenação estável por data e UUID. A interface avisa se atingir o limite de linhas carregadas |
| Identificadores | UUID válido para registros; slugs de categoria em minúsculas; filtros/colunas/operações em listas permitidas |

CPF/CNPJ e tipo solicitado são identificadores imutáveis na edição de perfil. Uma correção legítima deve ser tratada por operador autorizado, com conferência documental e auditoria, sem permitir que o próprio usuário troque identidade ou privilégios. Aprovações, entrega, pagamento e notificação não aceitam alteração direta de campos críticos pelo formulário.

Alguns limites de proteção são deliberadamente cumulativos: a API aplica limites gerais; a configuração e a capacidade da categoria podem impor limites menores; o Supabase Auth/provedor pode aplicar limites adicionais de envio e tentativa. Os valores gravados precisam passar por todas as camadas. Consulte `TESTES.md` para distinguir validação local executada de integrações externas que exigem credenciais.

## Regras adicionais: combustível, pico, rota e veículo

| Campo/operação | Regra adicional |
|---|---|
| Consumo de combustível da categoria | Número finito de 0 a 200 km/l; bicicleta usa zero |
| Preço do combustível | De 0 a R$ 100/l; valor configurado, sem consulta real a postos |
| Multiplicadores de pico e urgência | De 1 a 5 |
| Horários de pico | Até 8 pares de horas inteiras; início 0–23, fim 1–24, início menor que fim |
| Dias de pico | Dias ISO 1–7; até 7 valores; fuso `America/Sao_Paulo` |
| Tarifa de serviço extra | Não negativa e até R$ 1.000; quantidade máxima configurável de 0 a 5 |
| Prova de rota real | Token HMAC de até 2.048 caracteres, válido por 30 minutos e vinculado à conta, categoria e hashes dos endereços; registro SQL exclusivo de serviço |
| Rota obrigatória | Booleano configurável; `true` exige registro confiável no banco, inclusive em chamadas diretas ao Supabase |
| Distância automática | Geocodificação e roteamento reais somente quando Geoapify estiver configurado; distância em km com 3 casas; sem GPS em tempo real |
| Veículo usado na etapa | UUID obrigatório a cada atualização, exatamente igual ao veículo reservado na entrega |
| Conferência do cliente | Booleano real; divergência exige observação de 3–2.000; confirmação permite nota opcional até 2.000 |

A referência anterior a distância manual corresponde ao modo sem provedor configurado. No modo automático, a API exige token e o banco pode exigir a evidência com `route_required=true`; consulte `ROTAS_E_TARIFAS.md` para a configuração completa.

## Comissão e ano financeiro

- Comissão: percentual de 0 a 100, com até duas casas decimais; padrão 30%.
- Ano do relatório: inteiro entre 2000 e 2100. A consulta exige papel administrativo.
- Valores de comissão: calculados com precisão decimal no servidor, arredondados para centavos. A parcela do entregador é o valor do frete menos a comissão, para conservar o total.
- Taxa, valor e data de confirmação preservados no histórico não podem ser alterados pelos formulários.
